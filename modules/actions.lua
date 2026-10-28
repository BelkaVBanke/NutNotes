--[[
  REAPER timeline actions module:
  - Setting / clearing project regions
  - Transport and edit cursor navigation
  - Dynamic filter synchronization and region duration sync
]]

local parser = require('parser')
local actions = {}

-- Invisible UTF-8 signature: Zero-Width Space (U+200B) + Zero-Width Non-Joiner (U+200C)
local REGION_SIGNATURE = "\xE2\x80\x8B\xE2\x80\x8C"

-- Tag a region display name with NutNotes invisible signature and subtitle index
function actions.tag_region_name(display_name, idx)
  return REGION_SIGNATURE .. tostring(idx or 0) .. ":" .. (display_name or "")
end

-- Check if a region name was created by NutNotes
function actions.is_plugin_region(name)
  if not name or type(name) ~= "string" then return false end
  return name:sub(1, #REGION_SIGNATURE) == REGION_SIGNATURE
end

-- Parse subtitle index and original display name from a tagged region name
function actions.parse_plugin_region(name)
  if not actions.is_plugin_region(name) then return nil, name end
  local payload = name:sub(#REGION_SIGNATURE + 1)
  local idx_str, original_name = payload:match("^(%d+):(.*)$")
  if idx_str then
    return tonumber(idx_str), original_name
  end
  return nil, payload
end

-- Delete legacy subtitle tracks if present from earlier versions
function actions.delete_subtitle_track()
  if not reaper or not reaper.CountTracks or not reaper.GetTrack or not reaper.GetSetMediaTrackInfo_String or not reaper.DeleteTrack then return false end
  local num_tracks = reaper.CountTracks(0)
  for i = num_tracks - 1, 0, -1 do
    local tr = reaper.GetTrack(0, i)
    local _, name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    if name then
      local lower_name = name:lower()
      if lower_name == "sub-items-track" or lower_name == "subtitle" then
        reaper.DeleteTrack(tr)
      end
    end
  end
  if reaper.UpdateArrange then reaper.UpdateArrange() end
  return true
end

-- Legacy backward compatibility stubs (no-op)
function actions.clear_subtitle_track()
  return actions.delete_subtitle_track()
end

function actions.has_track_items() return false end
function actions.find_subtitle_track() return nil end
function actions.create_items() return 0 end

-- Clear only plugin-created project regions (leaves user markers/regions intact)
function actions.clear_regions()
  if not reaper or not reaper.CountProjectMarkers or not reaper.EnumProjectMarkers3 or not reaper.DeleteProjectMarker then return 0 end

  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  local count_deleted = 0

  for i = (num_markers + num_regions) - 1, 0, -1 do
    local retval, isrgn, pos, rgnend, name, markrgnidx, color = reaper.EnumProjectMarkers3(0, i)
    if retval > 0 and isrgn and actions.is_plugin_region(name) then
      if reaper.DeleteProjectMarkerByIndex then
        reaper.DeleteProjectMarkerByIndex(0, i)
      else
        reaper.DeleteProjectMarker(0, markrgnidx, true)
      end
      count_deleted = count_deleted + 1
    end
  end

  return count_deleted
end

-- Check if there are any active NutNotes plugin regions in project
function actions.has_plugin_regions()
  if not reaper or not reaper.CountProjectMarkers or not reaper.EnumProjectMarkers3 then return false end
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  for i = 0, (num_markers + num_regions) - 1 do
    local retval, isrgn, pos, rgnend, name = reaper.EnumProjectMarkers3(0, i)
    if retval > 0 and isrgn and actions.is_plugin_region(name) then
      return true
    end
  end
  return false
end



-- Clear all plugin regions
function actions.clear_regions_with_undo()
  if not reaper then return 0 end

  if reaper.PreventUIRefresh then reaper.PreventUIRefresh(1) end
  local count = actions.clear_regions()
  actions.delete_subtitle_track()
  if reaper.PreventUIRefresh then reaper.PreventUIRefresh(-1) end
  if reaper.UpdateTimeline then reaper.UpdateTimeline() end
  return count
end

-- Set regions: deletes existing plugin regions and loads subtitles into project regions
function actions.set_regions(subtitles, palette, state)
  if not reaper or not subtitles or not reaper.AddProjectMarker2 then return 0 end

  if reaper.PreventUIRefresh then reaper.PreventUIRefresh(1) end

  -- Delete only NutNotes plugin regions (user markers and regions stay untouched)
  actions.clear_regions()
  -- Clean up legacy subtitle track if leftover
  actions.delete_subtitle_track()

  palette = palette or {}
  local count_created = 0

  local is_streaming = state and state.timeline_streaming_enabled and (#subtitles >= (state.timeline_streaming_min_subs or 3000))
  local stream_min_t = -1
  local stream_max_t = -1
  if is_streaming and reaper.GetCursorPosition then
    local cur_t = 0
    if (reaper.GetPlayState() & 1) ~= 0 and reaper.GetPlayPosition then
      cur_t = reaper.GetPlayPosition()
    else
      cur_t = reaper.GetCursorPosition()
    end
    local radius_sec = (state.timeline_streaming_radius_min or 5.0) * 60.0
    stream_min_t = math.max(0, cur_t - radius_sec)
    stream_max_t = cur_t + radius_sec
    if actions.timeline_sync then
      actions.timeline_sync.streaming_center = cur_t
    end
  end

  for i, sub in ipairs(subtitles) do
    -- If dynamic streaming is active, skip regions outside the time radius
    if not is_streaming or (sub.end_time >= stream_min_t and sub.start_time <= stream_max_t) then
    local display_name = ""
    local color = 0

    local single_line_text = parser.strip_invisible_unicode(sub.text:gsub("\r\n", " "):gsub("\n", " "))
    local primary_actor = (sub.actors and sub.actors[1]) or sub.actor

    if primary_actor ~= "NoActor" then
      local actor_label = sub.raw_actor or sub.actor
      display_name = "[" .. actor_label .. "] " .. single_line_text
      if palette[primary_actor] then
        color = palette[primary_actor].reaper_color or 0
      end
    else
      display_name = single_line_text
      if palette["NoActor"] and palette["NoActor"].reaper_color then
        color = palette["NoActor"].reaper_color
      elseif state and state.get_default_region_reaper_color then
        color = state.get_default_region_reaper_color()
      else
        color = 0 -- Default REAPER color for NoActor
      end
    end

    local real_idx = (state and state.find_subtitle_index and state.find_subtitle_index(sub)) or i
    local tagged_name = actions.tag_region_name(display_name, real_idx)
    reaper.AddProjectMarker2(0, true, sub.start_time, sub.end_time, tagged_name, real_idx, color)
    count_created = count_created + 1
    end -- close is_streaming window check
  end

  if reaper.PreventUIRefresh then reaper.PreventUIRefresh(-1) end
  if reaper.UpdateTimeline then reaper.UpdateTimeline() end

  if state and actions.init_timeline_sync then
    actions.init_timeline_sync(state)
  end

  return count_created
end

-- Synchronize colors of existing timeline regions and items to current palette
function actions.sync_palette_to_timeline(state)
  if not reaper or not reaper.CountProjectMarkers or not reaper.EnumProjectMarkers3 or not reaper.SetProjectMarker3 then return end
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  if num_regions > 0 then
    for m = 0, num_markers + num_regions - 1 do
      local retval, isrgn, pos, rgnend, name, markrgnidx, color = reaper.EnumProjectMarkers3(0, m)
      if retval > 0 and isrgn and actions.is_plugin_region(name) then
        local idx = actions.parse_plugin_region(name)
        if idx and state.subtitles and state.subtitles[idx] then
          local sub = state.subtitles[idx]
          local primary_actor = (sub.actors and sub.actors[1]) or sub.actor
          local rgn_color = 0
          if primary_actor ~= "NoActor" and state.actor_palette and state.actor_palette[primary_actor] then
            rgn_color = state.actor_palette[primary_actor].reaper_color or 0
          else
            rgn_color = (state.actor_palette and state.actor_palette["NoActor"] and state.actor_palette["NoActor"].reaper_color) or (state.get_default_region_reaper_color and state.get_default_region_reaper_color()) or 0
          end
          if color ~= rgn_color then
            reaper.SetProjectMarker3(0, markrgnidx, true, pos, rgnend, name, rgn_color)
          end
        end
      end
    end
    if reaper.UpdateTimeline then reaper.UpdateTimeline() end
  end


end

-- Synchronize regions to the current filter
function actions.sync_filter_to_timeline(state)
  if not state then return end
  if state.regions_enabled == false then
    actions.clear_regions()
    return
  end
  if not state.sync_with_filter then
    actions.set_regions(state.subtitles or {}, state.actor_palette, state)
    return
  end
  local filtered = (state.get_filtered_subtitles and state.get_filtered_subtitles()) or (state.subtitles or {})
  actions.set_regions(filtered, state.actor_palette, state)
end

-- Ensure timeline regions match state.subtitles upon undo/redo or sync flag change
function actions.ensure_regions_synced(state)
  if not reaper or not state then return end
  if state.regions_enabled == false then
    actions.clear_regions()
    return
  end

  local subs = (state.sync_with_filter and state.get_filtered_subtitles) and state.get_filtered_subtitles() or (state.subtitles or {})
  if #subs == 0 then
    actions.clear_regions()
    return
  end

  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  local rgn_count = 0
  local existing_plugin_regions = {}

  for m = 0, num_markers + num_regions - 1 do
    local retval, isrgn, pos, rgnend, name, markrgnidx, color = reaper.EnumProjectMarkers3(0, m)
    if retval > 0 and isrgn and actions.is_plugin_region(name) then
      rgn_count = rgn_count + 1
      local idx = actions.parse_plugin_region(name)
      if idx then
        existing_plugin_regions[idx] = markrgnidx
      end
    end
  end

  if rgn_count ~= #subs then
    actions.set_regions(subs, state.actor_palette, state)
    return
  end

  for i, _ in ipairs(subs) do
    if not existing_plugin_regions[i] then
      actions.set_regions(subs, state.actor_palette, state)
      return
    end
  end

  if actions.init_timeline_sync then
    actions.init_timeline_sync(state)
  end
end

-- Check if auto-launch on REAPER startup is enabled in Scripts/__startup.lua
function actions.is_startup_enabled()
  if not reaper or not reaper.GetResourcePath then return false end
  local res_path = reaper.GetResourcePath()
  local f = io.open(res_path .. "/Scripts/__startup.lua", "r")
  if not f then return false end
  local content = f:read("*a")
  f:close()
  return content:find(">>> NutNotes Startup >>>", 1, true) ~= nil or content:find(">>> REAPER Subtitle Plugin Startup >>>", 1, true) ~= nil
end

-- Enable or disable auto-launch in Scripts/__startup.lua
function actions.set_startup_enabled(enable)
  if not reaper or not reaper.GetResourcePath then return false end
  local res_path = reaper.GetResourcePath()
  local path = res_path .. "/Scripts/__startup.lua"
  local existing = ""
  local f = io.open(path, "r")
  if f then
    existing = f:read("*a")
    f:close()
  end

  -- Strip out NutNotes or legacy sections if present
  local cleaned = existing:gsub("%s*%-%-%s*>>> NutNotes Startup >>>.-%-%-%s*<<< NutNotes Startup <<<%s*", "\n")
  cleaned = cleaned:gsub("%s*%-%-%s*>>> REAPER Subtitle Plugin Startup >>>.-%-%-%s*<<< REAPER Subtitle Plugin Startup <<<%s*", "\n")
  cleaned = cleaned:gsub("%s*%-%-%s*REAPER Startup Script%s*", "\n")
  cleaned = cleaned:gsub("%s*%-%-%s*Auto%-launch.-startup%s*", "\n")
  cleaned = cleaned:gsub("^%s+", ""):gsub("%s+$", "")

  if enable then
    local block = [[

-- >>> NutNotes Startup >>>
reaper.defer(function()
  local res = reaper.GetResourcePath()
  local cmd_id = reaper.NamedCommandLookup("_RS_NUTNOTES_LAUNCHER")
  if not cmd_id or cmd_id <= 0 then
    cmd_id = reaper.NamedCommandLookup("_RS2dc2e136e0d96f0d14a4948732a1c5629b86ef37")
  end
  if cmd_id and cmd_id > 0 then
    reaper.Main_OnCommand(cmd_id, 0)
  else
    local candidate_paths = {
      res .. "/Scripts/NutNotes/NutNotes.lua",
      res .. "/Scripts/MyScripts/NutNotes.lua",
      res .. "/Scripts/NutNotes.lua"
    }
    for _, p in ipairs(candidate_paths) do
      local fl = io.open(p, "r")
      if fl then
        fl:close()
        dofile(p)
        break
      end
    end
  end
end)
-- <<< NutNotes Startup <<<
]]
    local new_content = (cleaned ~= "" and (cleaned .. "\n" .. block) or block:gsub("^\n", ""))
    local out = io.open(path, "w")
    if out then
      out:write(new_content)
      out:close()
      return true
    end
  else
    if cleaned == "" then
      os.remove(path)
    else
      local out = io.open(path, "w")
      if out then
        out:write(cleaned .. "\n")
        out:close()
      end
    end
    return true
  end
  return false
end

-- Helper to copy file in binary mode
local function copy_file_binary(src, dst)
  local f_in = io.open(src, "rb")
  if not f_in then return false end
  local content = f_in:read("*a")
  f_in:close()
  local f_out = io.open(dst, "wb")
  if not f_out then return false end
  f_out:write(content)
  f_out:close()
  return true
end

-- Ensure toolbar icons are present in REAPER's Data/toolbar_icons directory
function actions.ensure_toolbar_icons()
  if not reaper or not reaper.GetResourcePath then return false end
  local res_path = reaper.GetResourcePath()
  local dst_dir = res_path .. "/Data/toolbar_icons"
  
  -- Create directory if needed via reaper or os
  local test_f = io.open(dst_dir .. "/nutnotes_toolbar.png", "rb")
  if test_f then
    test_f:close()
    return true
  end

  local candidate_dirs = {
    res_path .. "/Scripts/NutNotes/assets",
    res_path .. "/Scripts/MyScripts/assets",
    res_path .. "/Scripts/assets",
    "assets",
    "installer/assets"
  }

  for _, cdir in ipairs(candidate_dirs) do
    local src_file = cdir .. "/nutnotes_toolbar.png"
    local f = io.open(src_file, "rb")
    if f then
      f:close()
      copy_file_binary(src_file, dst_dir .. "/nutnotes_toolbar.png")
      local src30 = cdir .. "/nutnotes_icon_30.png"
      local f30 = io.open(src30, "rb")
      if f30 then
        f30:close()
        copy_file_binary(src30, dst_dir .. "/nutnotes_icon_30.png")
      end
      return true
    end
  end
  return false
end

-- Ensure NutNotes actions are registered in reaper-kb.ini so REAPER can invoke them by action ID
-- Returns the action command ID string (e.g. "_RS458e8fd72200237182e91979ee7b7dd971227cf5" or "_RS_NUTNOTES_LAUNCHER")
function actions.ensure_action_registered()
  if not reaper or not reaper.GetResourcePath then return "_RS_NUTNOTES_LAUNCHER" end
  local res_path = reaper.GetResourcePath()
  local kb_file = res_path .. "/reaper-kb.ini"

  local f = io.open(kb_file, "r")
  local found_cmd = nil
  local found_create_sub = false
  if f then
    for line in f:lines() do
      if line:match("^SCR%s+") and line:find("NutNotes.lua", 1, true) then
        local parts = {}
        for p in line:gmatch("%S+") do table.insert(parts, p) end
        if parts[4] and parts[4]:match("^RS") then
          found_cmd = "_" .. parts[4]
        elseif parts[4] and parts[4]:match("^_RS") then
          found_cmd = parts[4]
        end
      elseif line:match("^SCR%s+") and line:find("NutNotes_CreateSubtitle.lua", 1, true) then
        found_create_sub = true
      end
    end
    f:close()
  end

  local lines_to_append = ""
  if not found_cmd then
    lines_to_append = lines_to_append .. '\nSCR 4 0 _RS_NUTNOTES_LAUNCHER "Script: NutNotes.lua" "NutNotes/NutNotes.lua"'
    found_cmd = "_RS_NUTNOTES_LAUNCHER"
  end
  if not found_create_sub then
    lines_to_append = lines_to_append .. '\nSCR 4 0 _RS_NUTNOTES_CREATE_SUBTITLE "Script: NutNotes_CreateSubtitle.lua" "NutNotes/NutNotes_CreateSubtitle.lua"'
  end

  if #lines_to_append > 0 then
    local f_out = io.open(kb_file, "a")
    if f_out then
      f_out:write(lines_to_append .. "\n")
      f_out:close()
    end
  end

  return found_cmd
end

-- Check if NutNotes launcher button is present on the Main toolbar or Toolbar 1 in reaper-menu.ini
function actions.is_toolbar_button_enabled()
  if not reaper or not reaper.GetResourcePath then return false end
  local res_path = reaper.GetResourcePath()
  local menu_file = res_path .. "/reaper-menu.ini"

  local f = io.open(menu_file, "r")
  if not f then return false end

  local in_target_toolbar = false
  local found = false

  for line in f:lines() do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed:match("^%[Main toolbar%]") or trimmed:match("^%[toolbar:1%]") or trimmed:match("^%[Floating toolbar 1%]") then
      in_target_toolbar = true
    elseif in_target_toolbar and trimmed:sub(1, 1) == "[" then
      in_target_toolbar = false
    elseif in_target_toolbar then
      if trimmed:find("NUTNOTES", 1, true) or
         (trimmed:find("NutNotes", 1, true) and (trimmed:match("^item_") or trimmed:match("^text_"))) then
        found = true
        break
      end
    end
  end
  f:close()
  return found
end

-- Default REAPER Main toolbar definition (used when reaper-menu.ini is clean / doesn't have [Main toolbar] yet)
local DEFAULT_MAIN_TOOLBAR_LINES = {
  "default=095da8527a5acf0e",
  "title=Main toolbar",
  "item_0=40023 New project...",
  "item_1=40025 Open project...",
  "item_2=40026 Save project",
  "item_3=40021 Project settings...",
  "item_4=40029 Undo",
  "item_5=40030 Redo",
  "item_6=40364 Enable metronome",
  "item_7=-1",
  "item_8=42616 Marquee selection",
  "item_9=-1",
  "item_10=40041 Enable auto-crossfade",
  "item_11=1156 Enable item grouping and track media/razor edit grouping",
  "item_12=1155 Enable ripple editing",
  "item_13=40070 Move envelope points with media items",
  "item_14=40145 Show arrange view grid",
  "item_15=1157 Enable snapping",
  "item_16=1135 Enable locking",
  "item_17=-1",
  "item_18=42618 Razor editing",
}

-- Add or remove NutNotes launcher button from Main toolbar in reaper-menu.ini
function actions.set_toolbar_button_enabled(enable)
  if not reaper or not reaper.GetResourcePath then return false end
  local res_path = reaper.GetResourcePath()
  local menu_file = res_path .. "/reaper-menu.ini"

  actions.ensure_toolbar_icons()
  local action_cmd = actions.ensure_action_registered() or "_RS_NUTNOTES_LAUNCHER"

  local f = io.open(menu_file, "r")
  local lines = {}
  if f then
    for line in f:lines() do
      table.insert(lines, line)
    end
    f:close()
  end

  -- Only target [Main toolbar] (or existing docked toolbar if user already configured it)
  -- If [Main toolbar] doesn't exist, we must populate it with REAPER's full default toolbar!
  local sec_name = "Main toolbar"
  local sec_start = nil
  local sec_end = nil
  local sec_already = false

  local in_sec = false
  for i, line in ipairs(lines) do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed == "[Main toolbar]" then
      in_sec = true
      sec_start = i
    elseif in_sec and trimmed:sub(1, 1) == "[" then
      sec_end = i - 1
      break
    elseif in_sec then
      if trimmed:find("NUTNOTES", 1, true) or
         (trimmed:find("NutNotes", 1, true) and (trimmed:match("^item_") or trimmed:match("^text_"))) then
        sec_already = true
      end
    end
  end
  if in_sec and not sec_end then
    sec_end = #lines
  end

  if enable then
    if not sec_already then
      if not sec_start then
        -- Clean REAPER: [Main toolbar] section does NOT exist in reaper-menu.ini.
        -- We MUST write all default REAPER toolbar items first, then append NutNotes!
        if #lines > 0 and lines[#lines] ~= "" then
          table.insert(lines, "")
        end
        table.insert(lines, "[Main toolbar]")
        for _, def_line in ipairs(DEFAULT_MAIN_TOOLBAR_LINES) do
          table.insert(lines, def_line)
        end
        local next_num = 19 -- follows default item_18
        table.insert(lines, string.format("item_%d=%s Script: NutNotes.lua", next_num, action_cmd))
        table.insert(lines, string.format("icon_%d=nutnotes_toolbar.png", next_num))
        table.insert(lines, string.format("text_%d=NutNotes", next_num))
      else
        -- Section already exists (customized by user or previous run)
        local max_item_num = -1
        for i = sec_start, sec_end do
          local num = lines[i]:match("^item_(%d+)=")
          if num then
            local n = tonumber(num)
            if n and n > max_item_num then max_item_num = n end
          end
        end
        local next_num = max_item_num + 1
        local insert_pos = sec_end + 1
        table.insert(lines, insert_pos, string.format("item_%d=%s Script: NutNotes.lua", next_num, action_cmd))
        table.insert(lines, insert_pos + 1, string.format("icon_%d=nutnotes_toolbar.png", next_num))
        table.insert(lines, insert_pos + 2, string.format("text_%d=NutNotes", next_num))
      end
    end
  else
    if sec_already and sec_start then
      local new_lines = {}
      local i = 1
      while i <= #lines do
        if i == sec_start then
          local sec_hdr = lines[i]
          i = i + 1
          local raw_items = {}
          local sec_props = {}
          while i <= #lines do
            local l = lines[i]
            local trimmed = l:match("^%s*(.-)%s*$")
            if trimmed:sub(1, 1) == "[" then break end
            local k, v = trimmed:match("^([^=]+)=(.*)$")
            if k and v then
              local prefix, num_s = k:match("^(%a+)_(%d+)$")
              if prefix and num_s then
                local n = tonumber(num_s)
                raw_items[n] = raw_items[n] or {}
                raw_items[n][prefix] = v
              else
                table.insert(sec_props, l)
              end
            elseif #trimmed > 0 then
              table.insert(sec_props, l)
            end
            i = i + 1
          end

          table.insert(new_lines, sec_hdr)
          for _, p in ipairs(sec_props) do table.insert(new_lines, p) end

          local reindex = 0
          local max_k = -1
          for k_idx in pairs(raw_items) do if k_idx > max_k then max_k = k_idx end end
          for idx = 0, max_k do
            local it = raw_items[idx]
            if it then
              local is_nut = false
              if it.item and it.item:find("NUTNOTES", 1, true) then is_nut = true end
              if it.item and it.item:find("NutNotes", 1, true) then is_nut = true end
              if it.text and it.text:find("NutNotes", 1, true) then is_nut = true end
              if not is_nut then
                if it.item then table.insert(new_lines, string.format("item_%d=%s", reindex, it.item)) end
                if it.icon then table.insert(new_lines, string.format("icon_%d=%s", reindex, it.icon)) end
                if it.text then table.insert(new_lines, string.format("text_%d=%s", reindex, it.text)) end
                reindex = reindex + 1
              end
            end
          end
        else
          table.insert(new_lines, lines[i])
          i = i + 1
        end
      end
      lines = new_lines
    end
  end

  local f_out = io.open(menu_file, "w")
  if f_out then
    for _, l in ipairs(lines) do
      f_out:write(l .. "\n")
    end
    f_out:close()
    return true
  end
  return false
end
function actions.return_focus_to_reaper()
  if not reaper then return end
  local main_hwnd = reaper.GetMainHwnd and reaper.GetMainHwnd()
  if main_hwnd and reaper.JS_Window_SetFocus then
    local track_view = reaper.JS_Window_FindChildByID and reaper.JS_Window_FindChildByID(main_hwnd, 1000)
    if not track_view and reaper.JS_Window_FindChild then
      track_view = reaper.JS_Window_FindChild(main_hwnd, "trackview", true)
    end
    if track_view then
      pcall(reaper.JS_Window_SetFocus, track_view)
    else
      pcall(reaper.JS_Window_SetFocus, main_hwnd)
    end
  end
  if reaper.SetCursorContext then
    pcall(reaper.SetCursorContext, 1, nil)
  end
end

-- Bring NutNotes window into foreground and set keyboard focus
function actions.focus_nutnotes_window()
  if not reaper then return end
  if reaper.JS_Window_FindTop and reaper.JS_Window_SetFocus then
    local wnd = reaper.JS_Window_FindTop("NutNotes", false)
    if not wnd and reaper.JS_Window_Find then
      wnd = reaper.JS_Window_Find("NutNotes", false)
    end
    if wnd then
      if reaper.JS_Window_SetForeground then
        pcall(reaper.JS_Window_SetForeground, wnd)
      end
      pcall(reaper.JS_Window_SetFocus, wnd)
    end
  end
end

-- Check if any popup is open in ReaImGui
function actions.is_popup_open(ctx, ImGui)
  if not ctx or not ImGui or not ImGui.IsPopupOpen then return false end
  if ImGui.ValidatePtr and not ImGui.ValidatePtr(ctx, 'ImGui_Context*') then return false end
  local any_flags = 0
  if ImGui.PopupFlags_AnyPopupId then any_flags = any_flags | ImGui.PopupFlags_AnyPopupId end
  if ImGui.PopupFlags_AnyPopupLevel then any_flags = any_flags | ImGui.PopupFlags_AnyPopupLevel end
  local ok, open = pcall(ImGui.IsPopupOpen, ctx, nil, any_flags)
  if ok and open then return true end
  return false
end

-- Check if user is actively editing text in any InputText field or modal popup
function actions.is_text_editing_active(ctx, state, ImGui)
  if not state then return false end
  if state.open_text_edit_popup then return true end
  if state.editing_idx ~= nil then return true end
  if state.text_edit_idx ~= nil then return true end
  if state.open_sub_actor_modal or state.sub_actor_modal_idx ~= nil then return true end
  if state.open_rename_actor_modal or (state.rename_actor_orig and state.rename_actor_orig ~= "") then return true end
  if state.search_input_active then return true end
  if not ctx or not ImGui then return false end
  if ImGui.ValidatePtr and not ImGui.ValidatePtr(ctx, 'ImGui_Context*') then return false end

  if ImGui.IsPopupOpen then
    local function check_popup(name)
      local ok, res = pcall(ImGui.IsPopupOpen, ctx, name)
      return ok and res
    end
    if check_popup("Изменить текст субтитра###SUB_TEXT_EDIT_MODAL") then return true end
    if check_popup("Изменить актера субтитра###SUB_ACTOR_EDIT_MODAL") then return true end
    if check_popup("Переименовать актера###RENAME_ACTOR_MODAL") then return true end
    if check_popup("Переименовать / объединить актера###RENAME_ACTOR_MODAL") then return true end
  end

  return false
end

-- Deep copy helper for timeline undo snapshots
local function deep_copy_subs(subs)
  if not subs then return {} end
  local copy = {}
  for i, s in ipairs(subs) do
    local entry = {
      start_time = s.start_time,
      end_time = s.end_time,
      actor = s.actor,
      character = s.character,
      raw_actor = s.raw_actor,
      text = s.text,
    }
    if s.actors then
      entry.actors = {}
      for j, a in ipairs(s.actors) do entry.actors[j] = a end
    end
    copy[i] = entry
  end
  return copy
end

actions.timeline_sync = {
  is_syncing = false,
  drag_active = false,
  last_change_time = 0,
  last_poll_time = 0,
  last_change_count = -1,
  undo_snapshot = nil,
  changed_sub_idx = nil,
  sub_map = {},
  last_item_count = -1,
  last_rgn_count = -1,
}

-- Initialize timeline sync mapping (Regions only)
function actions.init_timeline_sync(state)
  if not reaper or not state or not state.subtitles or #state.subtitles == 0 then
    actions.timeline_sync.sub_map = {}
    return
  end

  local sync = actions.timeline_sync
  sync.sub_map = {}

  -- Map regions (only NutNotes plugin regions)
  local regions_map = {}
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  for m = 0, num_markers + num_regions - 1 do
    local retval, isrgn, pos, rgnend, name, markrgnidx, color = reaper.EnumProjectMarkers3(0, m)
    if retval > 0 and isrgn and actions.is_plugin_region(name) then
      local parsed_idx = actions.parse_plugin_region(name)
      local target_idx = parsed_idx or markrgnidx
      if target_idx >= 1 and target_idx <= #state.subtitles then
        regions_map[target_idx] = { markrgnidx = markrgnidx, pos = pos, rgnend = rgnend, name = name, color = color }
      end
    end
  end

  for i, sub in ipairs(state.subtitles) do
    local rgn_info = regions_map[i]
    local rgn_pos = rgn_info and rgn_info.pos or sub.start_time
    local rgn_end = rgn_info and rgn_info.rgnend or sub.end_time

    sync.sub_map[i] = {
      markrgnidx = rgn_info and rgn_info.markrgnidx or nil,
      rgn_pos = rgn_pos,
      rgn_end = rgn_end
    }
  end

  sync.last_rgn_count = num_regions
end

-- Delete a single subtitle's region incrementally without full recreation
function actions.delete_single_timeline_item(state, real_idx)
  if not reaper or not real_idx then return end
  local sync = actions.timeline_sync
  if sync and sync.sub_map and sync.sub_map[real_idx] then
    local entry = sync.sub_map[real_idx]
    if entry.markrgnidx and reaper.DeleteProjectMarker then
      reaper.DeleteProjectMarker(0, entry.markrgnidx, true)
    end
    table.remove(sync.sub_map, real_idx)
    if sync.last_rgn_count and sync.last_rgn_count > 0 then
      sync.last_rgn_count = sync.last_rgn_count - 1
    end
  end
  if reaper.UpdateTimeline then reaper.UpdateTimeline() end
end

-- Add a single subtitle's region incrementally
function actions.add_single_timeline_item(state, real_idx)
  if not reaper or not state or not real_idx then return end
  local sub = state.subtitles and state.subtitles[real_idx]
  if not sub then return end

  local sync = actions.timeline_sync

  local is_streaming = state and state.timeline_streaming_enabled and (#state.subtitles >= (state.timeline_streaming_min_subs or 3000))
  local in_streaming_window = true
  if is_streaming and sync and sync.streaming_center then
    local radius_sec = (state.timeline_streaming_radius_min or 5.0) * 60.0
    local min_t = math.max(0, sync.streaming_center - radius_sec)
    local max_t = sync.streaming_center + radius_sec
    if sub.end_time < min_t or sub.start_time > max_t then
      in_streaming_window = false
    end
  end

  local has_rgns = (state and state.regions_enabled ~= false)

  local markrgnidx = nil
  if has_rgns and in_streaming_window and reaper.AddProjectMarker2 then
    local display_num = #state.subtitles
    local single_line_text = parser.strip_invisible_unicode((sub.text or ""):gsub("[\r\n]+", " "))
    local primary_actor = (sub.actors and sub.actors[1]) or sub.actor
    local display_name = ""
    local rgn_color = 0

    if primary_actor and primary_actor ~= "NoActor" then
      local actor_label = sub.raw_actor or sub.actor
      display_name = "[" .. actor_label .. "] " .. single_line_text
      if state.actor_palette and state.actor_palette[primary_actor] then
        rgn_color = state.actor_palette[primary_actor].reaper_color or 0
      end
    else
      display_name = single_line_text
      if state.actor_palette and state.actor_palette["NoActor"] and state.actor_palette["NoActor"].reaper_color then
        rgn_color = state.actor_palette["NoActor"].reaper_color
      elseif state.get_default_region_reaper_color then
        rgn_color = state.get_default_region_reaper_color()
      end
    end

    local tagged_name = actions.tag_region_name(display_name, display_num)
    markrgnidx = reaper.AddProjectMarker2(0, true, sub.start_time, sub.end_time, tagged_name, display_num, rgn_color)
  end

  if sync and sync.sub_map then
    local entry = {
      markrgnidx = markrgnidx,
      rgn_pos = sub.start_time,
      rgn_end = sub.end_time
    }
    table.insert(sync.sub_map, real_idx, entry)
    if sync.last_rgn_count and markrgnidx then sync.last_rgn_count = sync.last_rgn_count + 1 end
  end

  if reaper.UpdateTimeline then reaper.UpdateTimeline() end
end

-- Check and synchronize timeline durations (Region <-> Subtitles)
function actions.check_timeline_sync(state)
  if not reaper or not state or not state.subtitles or #state.subtitles == 0 then return end
  local sync = actions.timeline_sync
  if sync.is_syncing then return end

  local now_time = reaper.time_precise and reaper.time_precise() or os.clock()
  if sync.suppress_until and now_time < sync.suppress_until then
    return
  end
  local proj_changes = reaper.GetProjectStateChangeCount and reaper.GetProjectStateChangeCount(0) or -1

  -- Throttle checks when idle to eliminate frame drops on large files (>1000 subtitles)
  if not sync.drag_active then
    if sync.last_change_count == proj_changes and (now_time - (sync.last_poll_time or 0)) < 0.25 then
      return
    end
    sync.last_poll_time = now_time
    sync.last_change_count = proj_changes
  end

  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  if num_regions == 0 then
    return
  end

  -- Auto-rescan if counts changed or mapping uninitialized
  if not sync.sub_map or #sync.sub_map ~= #state.subtitles
     or num_regions ~= sync.last_rgn_count then
    actions.init_timeline_sync(state)
  end

  -- Dynamic streaming window auto-shift during playback or scrub
  if state.timeline_streaming_enabled and (#state.subtitles >= (state.timeline_streaming_min_subs or 3000)) and sync.streaming_center then
    local cur_t = 0
    if (reaper.GetPlayState() & 1) ~= 0 and reaper.GetPlayPosition then
      cur_t = reaper.GetPlayPosition()
    elseif reaper.GetCursorPosition then
      cur_t = reaper.GetCursorPosition()
    end
    local radius_sec = (state.timeline_streaming_radius_min or 5.0) * 60.0
    if math.abs(cur_t - sync.streaming_center) > (radius_sec * 0.4) then
      local filtered = state.get_filtered_subtitles()
      local has_rgns = (sync.last_rgn_count and sync.last_rgn_count > 0) or (actions.has_plugin_regions and actions.has_plugin_regions())
      if has_rgns then
        actions.set_regions(filtered, state.actor_palette, state)
      end
    end
  end

  -- Cache regions for O(1) lookup
  local current_regions = {}
  for m = 0, num_markers + num_regions - 1 do
    local retval, isrgn, pos, rgnend, name, markrgnidx, color = reaper.EnumProjectMarkers3(0, m)
    if retval > 0 and isrgn then
      current_regions[markrgnidx] = { pos = pos, rgnend = rgnend, name = name, color = color }
    end
  end

  local any_changed = false
  for i, sub in ipairs(state.subtitles) do
    local entry = sync.sub_map[i]
    if entry then
      local cur_rgn_info = entry.markrgnidx and current_regions[entry.markrgnidx]
      local cur_rgn_pos = cur_rgn_info and cur_rgn_info.pos
      local cur_rgn_end = cur_rgn_info and cur_rgn_info.rgnend

      local rgn_diff = cur_rgn_pos and (math.abs(cur_rgn_pos - entry.rgn_pos) > 0.005 or math.abs(cur_rgn_end - entry.rgn_end) > 0.005)

      if rgn_diff then
        sync.is_syncing = true

        if not sync.drag_active then
          sync.drag_active = true
          sync.undo_snapshot = deep_copy_subs(state.subtitles)
        end
        sync.last_change_time = now_time
        sync.changed_sub_idx = i
        any_changed = true

        sub.start_time = cur_rgn_pos
        sub.end_time = cur_rgn_end
        entry.rgn_pos = cur_rgn_pos
        entry.rgn_end = cur_rgn_end

        -- Immediately recalculate CPS and update subtitle properties
        local dur = math.max(0.001, sub.end_time - sub.start_time)
        local char_cnt = sub.char_cnt or (parser and parser.utf8_len and parser.utf8_len(sub.text)) or (sub.text and #sub.text) or 0
        sub.char_cnt = char_cnt
        sub.cps = char_cnt / dur
        if state.prepare_sub_props then
          state.prepare_sub_props(sub)
        end

        state.row_heights = {}
        sync.is_syncing = false
      end
    end
  end

  -- Detect drag completion and commit undo block
  if sync.drag_active and not any_changed then
    local mouse_down = false
    if reaper.JS_Mouse_GetState then
      local ok, st = pcall(reaper.JS_Mouse_GetState, 1)
      if ok and (st & 1) ~= 0 then mouse_down = true end
    end

    if not mouse_down and (now_time - sync.last_change_time > 0.18) then
      sync.drag_active = false
      local ch_idx = sync.changed_sub_idx or 1

      local needs_reorder = false
      for k = 1, #state.subtitles - 1 do
        if state.subtitles[k].start_time > state.subtitles[k + 1].start_time then
          needs_reorder = true
          break
        end
      end
      if needs_reorder and parser and parser.sort_subtitles then
        parser.sort_subtitles(state.subtitles)
        actions.init_timeline_sync(state)
      end
      if sync.undo_snapshot and state.push_undo then
        local old_snap = {
          subtitles = sync.undo_snapshot,
          actor_palette = state.deep_copy_table and state.deep_copy_table(state.actor_palette),
          selected_actors = state.deep_copy_table and state.deep_copy_table(state.selected_actors),
          regions_displayed = actions.has_plugin_regions(),
          name = "Синхронизация длительности субтитра #" .. ch_idx
        }
        state.push_undo("Синхронизация длительности субтитра #" .. ch_idx, old_snap, function() end)
      end
      sync.undo_snapshot = nil
      state.save_to_project()
    end
  end
end

-- Update subtitle appearance on timeline (region name, colors)
function actions.update_subtitle_timeline(state, idx)
  if not reaper or not state or not state.subtitles or not state.subtitles[idx] then return end
  local sub = state.subtitles[idx]

  -- Update project region (only NutNotes plugin region)
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  for m = 0, num_markers + num_regions - 1 do
    local retval, isrgn, pos, rgnend, name, markrgnidx, color = reaper.EnumProjectMarkers3(0, m)
    if retval > 0 and isrgn and actions.is_plugin_region(name) then
      local parsed_idx = actions.parse_plugin_region(name)
      if markrgnidx == idx or parsed_idx == idx then
        local single_line_text = parser.strip_invisible_unicode(sub.text:gsub("\r\n", " "):gsub("\n", " "))
        local primary_actor = (sub.actors and sub.actors[1]) or sub.actor
        local display_name = ""
        local rgn_color = 0
        if primary_actor ~= "NoActor" then
          local actor_label = sub.raw_actor or sub.actor
          display_name = "[" .. actor_label .. "] " .. single_line_text
          if state.actor_palette and state.actor_palette[primary_actor] then
            rgn_color = state.actor_palette[primary_actor].reaper_color or 0
          end
        else
          display_name = single_line_text
          rgn_color = (state.actor_palette and state.actor_palette["NoActor"] and state.actor_palette["NoActor"].reaper_color) or (state.get_default_region_reaper_color and state.get_default_region_reaper_color()) or 0
        end
        local tagged_name = actions.tag_region_name(display_name, idx)
        reaper.SetProjectMarker3(0, markrgnidx, true, pos, rgnend, tagged_name, rgn_color)
        if reaper.UpdateTimeline then reaper.UpdateTimeline() end
        break
      end
    end
  end
end

-- Update all timeline representations when actors are renamed or reset
function actions.update_all_timeline_actors(state)
  if not reaper or not state or not state.subtitles then return end
  for i = 1, #state.subtitles do
    actions.update_subtitle_timeline(state, i)
  end



  -- Clean up any extra plugin project regions whose index exceeds #state.subtitles
  if reaper.CountProjectMarkers and reaper.EnumProjectMarkers3 and reaper.DeleteProjectMarker then
    local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
    for m = (num_markers or 0) + (num_regions or 0) - 1, 0, -1 do
      local retval, isrgn, pos, rgnend, name, markrgnidx, color = reaper.EnumProjectMarkers3(0, m)
      if retval > 0 and isrgn and actions.is_plugin_region(name) then
        local parsed_idx = actions.parse_plugin_region(name)
        local eff_idx = parsed_idx or markrgnidx
        if eff_idx > #state.subtitles then
          reaper.DeleteProjectMarker(0, markrgnidx, true)
        end
      end
    end
    if reaper.UpdateTimeline then reaper.UpdateTimeline() end
  end
end

-- Jump cursor to timestamp (and seek playback to this position if playing)
function actions.jump_to_time(sec)
  if not reaper or not sec then return end
  if reaper.SetEditCurPos2 then
    reaper.SetEditCurPos2(0, sec, true, true)
  else
    reaper.SetEditCurPos(sec, true, true)
  end
  if reaper.UpdateTimeline then
    reaper.UpdateTimeline()
  end
end

-- Create a new subtitle from REAPER Time Selection (Loop Selection)
function actions.create_subtitle_from_time_selection(state)
  if not reaper or not state then return false end

  local now_p = (reaper and reaper.time_precise and reaper.time_precise()) or os.clock()
  if state._last_create_sub_time and (now_p - state._last_create_sub_time) < 0.25 then
    return false
  end
  state._last_create_sub_time = now_p

  local start_time, end_time = 0, 0
  if reaper.GetSet_LoopTimeRange then
    start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  end

  if not start_time or not end_time or math.abs(end_time - start_time) < 0.05 then
    -- No time selection active: trigger error sound and show red toast
    local now_p = (reaper and reaper.time_precise and reaper.time_precise()) or os.clock()
    state.time_selection_error_msg = "Выделите временной отрезок"
    state.time_selection_error_until = now_p + 3.0

    -- Cross-platform system beep / error sound
    local beeped = false
    if reaper and reaper.JS_Window_MessageBeep then
      pcall(reaper.JS_Window_MessageBeep, 0x10) -- MB_ICONHAND / error sound
      beeped = true
    end
    if not beeped and reaper and reaper.StuffMIDIMessage then
      -- Fallback or terminal bell
      io.write("\a")
    end

    return false
  end

  if end_time < start_time then
    start_time, end_time = end_time, start_time
  end

  -- Subtitle created with noActor
  local default_actor = "NoActor"

  -- Record native REAPER undo point immediately upon creation
  local new_idx, new_sub = state.add_subtitle_with_undo(start_time, end_time, default_actor, "", false)
  if new_idx and new_sub then
    state._is_creating_new_sub = new_idx

    -- Clear any previous error toast upon success
    state.time_selection_error_msg = nil
    state.time_selection_error_until = 0

    -- Selection and auto-scroll (timeline entry already added incrementally)
    -- Select newly created subtitle and scroll to it without opening popup modal
    state._is_creating_new_sub = nil
    return true

  end
  return false
end

return actions
