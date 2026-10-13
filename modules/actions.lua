--[[
  REAPER timeline actions module:
  - Setting / clearing project regions
  - Creating / clearing track "subtitle" and media items
  - Transport and edit cursor navigation
  - Dynamic filter synchronization
]]

local parser = require('parser')
local actions = {}

-- Find existing track named "subtitle"
function actions.find_subtitle_track()
  if not reaper or not reaper.CountTracks or not reaper.GetTrack or not reaper.GetSetMediaTrackInfo_String then return nil end

  local num_tracks = reaper.CountTracks(0)
  for i = 0, num_tracks - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    if name and name:lower() == "subtitle" then
      return tr
    end
  end
  return nil
end

-- Find or create track named "subtitle"
function actions.get_or_create_subtitle_track()
  local existing = actions.find_subtitle_track()
  if existing then return existing end

  if not reaper or not reaper.CountTracks or not reaper.InsertTrackAtIndex or not reaper.GetTrack or not reaper.GetSetMediaTrackInfo_String then return nil end
  local num_tracks = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(num_tracks, true)
  local new_tr = reaper.GetTrack(0, num_tracks)
  reaper.GetSetMediaTrackInfo_String(new_tr, "P_NAME", "subtitle", true)
  return new_tr
end

-- Clear all items on "subtitle" track
function actions.clear_subtitle_track()
  if not reaper then return 0 end

  local tr = actions.find_subtitle_track()
  if not tr then return 0 end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local item_count = reaper.CountTrackMediaItems(tr)
  local count_removed = 0
  for j = item_count - 1, 0, -1 do
    local item = reaper.GetTrackMediaItem(tr, j)
    if item then
      reaper.DeleteTrackMediaItem(tr, item)
      count_removed = count_removed + 1
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Clear Subtitle Track Items (" .. count_removed .. ")", -1)

  return count_removed
end

-- Create media items on "subtitle" track
function actions.create_items(subtitles, palette, state)
  if not reaper or not subtitles or #subtitles == 0 then return 0 end

  if reaper.Undo_BeginBlock then reaper.Undo_BeginBlock() end
  if reaper.PreventUIRefresh then reaper.PreventUIRefresh(1) end

  local track = actions.get_or_create_subtitle_track()
  if not track then
    if reaper.PreventUIRefresh then reaper.PreventUIRefresh(-1) end
    if reaper.Undo_EndBlock then reaper.Undo_EndBlock("Create Subtitle Items", -1) end
    return 0
  end

  -- Clear existing items on the subtitle track before creating
  local existing_count = reaper.CountTrackMediaItems(track)
  for j = existing_count - 1, 0, -1 do
    local old_item = reaper.GetTrackMediaItem(track, j)
    if old_item then
      reaper.DeleteTrackMediaItem(track, old_item)
    end
  end

  palette = palette or {}
  local count_created = 0

  for i, sub in ipairs(subtitles) do
    local item = reaper.AddMediaItemToTrack(track)
    if item then
      reaper.SetMediaItemPosition(item, sub.start_time, false)
      local len = math.max(0.05, sub.end_time - sub.start_time)
      reaper.SetMediaItemLength(item, len, false)

      local real_idx = (state and state.find_subtitle_index and state.find_subtitle_index(sub)) or i
      reaper.GetSetMediaItemInfo_String(item, "P_EXT:NUTNOTES_SUB_IDX", tostring(real_idx), true)

      -- Take name: Raw actor + character or actor
      local take = reaper.AddTakeToMediaItem(item)
      if take then
        local take_name = sub.raw_actor or sub.actor or ""
        if take_name == "NoActor" then take_name = "" end
        reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", take_name, true)
      end

      -- Subtitle text in Item Notes
      reaper.GetSetMediaItemInfo_String(item, "P_NOTES", parser.strip_invisible_unicode(sub.text), true)

      -- Item color: gentle pastel from primary actor's palette or default (0)
      local primary_actor = (sub.actors and sub.actors[1]) or sub.actor
      if primary_actor ~= "NoActor" and palette[primary_actor] then
        local col = palette[primary_actor].reaper_color or 0
        reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", col)
      else
        reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", 0)
      end

      count_created = count_created + 1
    end
  end

  if reaper.PreventUIRefresh then reaper.PreventUIRefresh(-1) end
  if reaper.UpdateArrange then reaper.UpdateArrange() end
  if reaper.Undo_EndBlock then reaper.Undo_EndBlock("Create Subtitle Items (" .. count_created .. ")", -1) end

  if state and actions.init_timeline_sync then
    actions.init_timeline_sync(state)
  end

  return count_created
end

-- Clear all existing project regions
function actions.clear_regions()
  if not reaper or not reaper.CountProjectMarkers or not reaper.EnumProjectMarkers3 or not reaper.DeleteProjectMarker then return 0 end

  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  local count_deleted = 0

  for i = (num_markers + num_regions) - 1, 0, -1 do
    local retval, isrgn, pos, rgnend, name, markrgnidx, color = reaper.EnumProjectMarkers3(0, i)
    if retval > 0 and isrgn then
      reaper.DeleteProjectMarker(0, markrgnidx, true)
      count_deleted = count_deleted + 1
    end
  end

  return count_deleted
end

-- Clear all regions with dedicated Undo point
function actions.clear_regions_with_undo()
  if not reaper then return 0 end

  if reaper.Undo_BeginBlock then reaper.Undo_BeginBlock() end
  if reaper.PreventUIRefresh then reaper.PreventUIRefresh(1) end
  local count = actions.clear_regions()
  if reaper.PreventUIRefresh then reaper.PreventUIRefresh(-1) end
  if reaper.UpdateTimeline then reaper.UpdateTimeline() end
  if reaper.Undo_EndBlock then reaper.Undo_EndBlock("Clear All Regions (" .. count .. ")", -1) end
  return count
end

-- Set regions: deletes existing regions and loads subtitles into project regions
function actions.set_regions(subtitles, palette, state)
  if not reaper or not subtitles or not reaper.AddProjectMarker2 then return 0 end

  if reaper.Undo_BeginBlock then reaper.Undo_BeginBlock() end
  if reaper.PreventUIRefresh then reaper.PreventUIRefresh(1) end

  -- Delete all current regions
  actions.clear_regions()

  palette = palette or {}
  local count_created = 0

  for i, sub in ipairs(subtitles) do
    local name = ""
    local color = 0

    local single_line_text = parser.strip_invisible_unicode(sub.text:gsub("\r\n", " "):gsub("\n", " "))
    local primary_actor = (sub.actors and sub.actors[1]) or sub.actor

    if primary_actor ~= "NoActor" then
      local actor_label = sub.raw_actor or sub.actor
      name = "[" .. actor_label .. "] " .. single_line_text
      if palette[primary_actor] then
        color = palette[primary_actor].reaper_color or 0
      end
    else
      name = single_line_text
      color = 0 -- Default REAPER color for NoActor
    end

    local real_idx = (state and state.find_subtitle_index and state.find_subtitle_index(sub)) or i
    reaper.AddProjectMarker2(0, true, sub.start_time, sub.end_time, name, real_idx, color)
    count_created = count_created + 1
  end

  if reaper.PreventUIRefresh then reaper.PreventUIRefresh(-1) end
  if reaper.UpdateTimeline then reaper.UpdateTimeline() end
  if reaper.Undo_EndBlock then reaper.Undo_EndBlock("Set Subtitle Regions (" .. count_created .. ")", -1) end

  if state and actions.init_timeline_sync then
    actions.init_timeline_sync(state)
  end

  return count_created
end

-- Synchronize both regions and items to the current filter
function actions.sync_filter_to_timeline(state)
  if not state.sync_with_filter then return end
  local filtered = state.get_filtered_subtitles()

  -- 1. Sync project regions
  actions.set_regions(filtered, state.actor_palette, state)

  -- 2. Sync track items if track "subtitle" exists
  local tr = actions.find_subtitle_track()
  if tr then
    actions.create_items(filtered, state.actor_palette, state)
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
    "Setup/assets"
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

-- Ensure NutNotes action is registered in reaper-kb.ini so REAPER can invoke it by action ID
-- Returns the action command ID string (e.g. "_RS458e8fd72200237182e91979ee7b7dd971227cf5" or "_RS_NUTNOTES_LAUNCHER")
function actions.ensure_action_registered()
  if not reaper or not reaper.GetResourcePath then return "_RS_NUTNOTES_LAUNCHER" end
  local res_path = reaper.GetResourcePath()
  local kb_file = res_path .. "/reaper-kb.ini"

  local f = io.open(kb_file, "r")
  local found_cmd = nil
  if f then
    for line in f:lines() do
      if line:match("^SCR%s+") and line:find("NutNotes.lua", 1, true) then
        local parts = {}
        for p in line:gmatch("%S+") do table.insert(parts, p) end
        if parts[4] and parts[4]:match("^RS") then
          found_cmd = "_" .. parts[4]
          break
        elseif parts[4] and parts[4]:match("^_RS") then
          found_cmd = parts[4]
          break
        end
      end
    end
    f:close()
  end

  if found_cmd then
    return found_cmd
  end

  -- Detect relative script path inside REAPER
  local script_rel_path = "NutNotes/NutNotes.lua"
  local check_paths = {
    { full = res_path .. "/Scripts/NutNotes/NutNotes.lua", rel = "NutNotes/NutNotes.lua" },
    { full = res_path .. "/Scripts/MyScripts/NutNotes.lua", rel = "MyScripts/NutNotes.lua" },
    { full = res_path .. "/Scripts/NutNotes.lua", rel = "NutNotes.lua" },
  }
  for _, cp in ipairs(check_paths) do
    local tf = io.open(cp.full, "r")
    if tf then
      tf:close()
      script_rel_path = cp.rel
      break
    end
  end

  local line = string.format('\nSCR 4 0 _RS_NUTNOTES_LAUNCHER "Script: NutNotes.lua" "%s"\n', script_rel_path)
  local f_out = io.open(kb_file, "a")
  if f_out then
    f_out:write(line)
    f_out:close()
    return "_RS_NUTNOTES_LAUNCHER"
  end
  return "_RS_NUTNOTES_LAUNCHER"
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

-- Check if any popup is open in ReaImGui
function actions.is_popup_open(ctx, ImGui)
  if not ctx or not ImGui or not ImGui.IsPopupOpen then return false end
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
  if state.text_edit_idx ~= nil and state.text_edit_focused then return true end
  if state.open_sub_actor_modal or state.sub_actor_modal_idx ~= nil then return true end
  if state.open_rename_actor_modal or (state.rename_actor_orig and state.rename_actor_orig ~= "") then return true end
  if ctx and ImGui and ImGui.IsPopupOpen then
    if ImGui.IsPopupOpen(ctx, "Изменить текст субтитра###SUB_TEXT_EDIT_MODAL") then return true end
    if ImGui.IsPopupOpen(ctx, "Изменить актера субтитра###SUB_ACTOR_EDIT_MODAL") then return true end
    if ImGui.IsPopupOpen(ctx, "Переименовать актера###RENAME_ACTOR_MODAL") then return true end
    if ImGui.IsPopupOpen(ctx, "Переименовать / объединить актера###RENAME_ACTOR_MODAL") then return true end
  end
  if ctx and ImGui and ImGui.IsAnyItemActive and ImGui.IsAnyItemActive(ctx) then
    if not ImGui.IsAnyMouseDown or not ImGui.IsAnyMouseDown(ctx) then
      return true
    end
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
  undo_snapshot = nil,
  changed_sub_idx = nil,
  sub_map = {},
  last_item_count = -1,
  last_rgn_count = -1,
}

-- Initialize timeline sync mapping
function actions.init_timeline_sync(state)
  if not reaper or not state or not state.subtitles or #state.subtitles == 0 then
    actions.timeline_sync.sub_map = {}
    return
  end

  local sync = actions.timeline_sync
  sync.sub_map = {}

  local tr = actions.find_subtitle_track()
  local track_items = {}
  local num_items = 0
  if tr then
    num_items = reaper.CountTrackMediaItems(tr)
    for j = 0, num_items - 1 do
      local item = reaper.GetTrackMediaItem(tr, j)
      local _, stored_idx_str = reaper.GetSetMediaItemInfo_String(item, "P_EXT:NUTNOTES_SUB_IDX", "", false)
      local stored_idx = tonumber(stored_idx_str)
      if stored_idx and stored_idx >= 1 and stored_idx <= #state.subtitles then
        track_items[stored_idx] = item
      end
    end
    -- Fallback 1: match by P_NOTES
    for j = 0, num_items - 1 do
      local item = reaper.GetTrackMediaItem(tr, j)
      local _, notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
      if notes and #notes > 0 then
        for s_idx, sub in ipairs(state.subtitles) do
          if not track_items[s_idx] and parser.strip_invisible_unicode(sub.text) == notes then
            track_items[s_idx] = item
            reaper.GetSetMediaItemInfo_String(item, "P_EXT:NUTNOTES_SUB_IDX", tostring(s_idx), true)
            break
          end
        end
      end
    end
    -- Fallback 2: 1-to-1 sequential mapping
    if num_items == #state.subtitles then
      for j = 0, num_items - 1 do
        local sub_idx = j + 1
        if not track_items[sub_idx] then
          local item = reaper.GetTrackMediaItem(tr, j)
          track_items[sub_idx] = item
          reaper.GetSetMediaItemInfo_String(item, "P_EXT:NUTNOTES_SUB_IDX", tostring(sub_idx), true)
        end
      end
    end
  end

  -- Map regions
  local regions_map = {}
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  for m = 0, num_markers + num_regions - 1 do
    local retval, isrgn, pos, rgnend, name, markrgnidx, color = reaper.EnumProjectMarkers3(0, m)
    if retval > 0 and isrgn then
      if markrgnidx >= 1 and markrgnidx <= #state.subtitles then
        regions_map[markrgnidx] = { markrgnidx = markrgnidx, pos = pos, rgnend = rgnend, name = name, color = color }
      end
    end
  end
  if num_regions == #state.subtitles and next(regions_map) == nil then
    local r_idx = 1
    for m = 0, num_markers + num_regions - 1 do
      local retval, isrgn, pos, rgnend, name, markrgnidx, color = reaper.EnumProjectMarkers3(0, m)
      if retval > 0 and isrgn and r_idx <= #state.subtitles then
        regions_map[r_idx] = { markrgnidx = markrgnidx, pos = pos, rgnend = rgnend, name = name, color = color }
        r_idx = r_idx + 1
      end
    end
  end

  for i, sub in ipairs(state.subtitles) do
    local item = track_items[i]
    local rgn_info = regions_map[i]
    local item_pos = item and reaper.GetMediaItemInfo_Value(item, "D_POSITION") or sub.start_time
    local item_len = item and reaper.GetMediaItemInfo_Value(item, "D_LENGTH") or math.max(0.05, sub.end_time - sub.start_time)
    local rgn_pos = rgn_info and rgn_info.pos or sub.start_time
    local rgn_end = rgn_info and rgn_info.rgnend or sub.end_time

    sync.sub_map[i] = {
      item = item,
      markrgnidx = rgn_info and rgn_info.markrgnidx or nil,
      item_pos = item_pos,
      item_len = item_len,
      rgn_pos = rgn_pos,
      rgn_end = rgn_end
    }
  end

  sync.last_item_count = num_items
  sync.last_rgn_count = num_regions
end

-- Check and synchronize timeline durations (Item <-> Region <-> Subtitles)
function actions.check_timeline_sync(state)
  if not reaper or not state or not state.subtitles or #state.subtitles == 0 then return end
  local sync = actions.timeline_sync
  if sync.is_syncing then return end

  local tr = actions.find_subtitle_track()
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  local num_items = tr and reaper.CountTrackMediaItems(tr) or 0

  if num_items == 0 and num_regions == 0 then
    return
  end

  -- Auto-rescan if counts changed or mapping uninitialized
  if not sync.sub_map or #sync.sub_map ~= #state.subtitles
     or num_items ~= sync.last_item_count
     or num_regions ~= sync.last_rgn_count then
    actions.init_timeline_sync(state)
  end

  -- Cache regions for O(1) lookup
  local current_regions = {}
  if num_regions > 0 then
    for m = 0, num_markers + num_regions - 1 do
      local retval, isrgn, pos, rgnend, name, markrgnidx, color = reaper.EnumProjectMarkers3(0, m)
      if retval > 0 and isrgn then
        current_regions[markrgnidx] = { pos = pos, rgnend = rgnend, name = name, color = color }
      end
    end
  end

  local any_changed = false
  local now_time = reaper.time_precise and reaper.time_precise() or os.clock()

  for i, sub in ipairs(state.subtitles) do
    local entry = sync.sub_map[i]
    if entry then
      local cur_item_pos, cur_item_len = nil, nil
      if entry.item and reaper.ValidatePtr2(0, entry.item, "MediaItem*") then
        cur_item_pos = reaper.GetMediaItemInfo_Value(entry.item, "D_POSITION")
        cur_item_len = reaper.GetMediaItemInfo_Value(entry.item, "D_LENGTH")
      end

      local cur_rgn_info = entry.markrgnidx and current_regions[entry.markrgnidx]
      local cur_rgn_pos = cur_rgn_info and cur_rgn_info.pos
      local cur_rgn_end = cur_rgn_info and cur_rgn_info.rgnend

      local item_diff = cur_item_pos and (math.abs(cur_item_pos - entry.item_pos) > 0.005 or math.abs(cur_item_len - entry.item_len) > 0.005)
      local rgn_diff = cur_rgn_pos and (math.abs(cur_rgn_pos - entry.rgn_pos) > 0.005 or math.abs(cur_rgn_end - entry.rgn_end) > 0.005)

      if item_diff or rgn_diff then
        sync.is_syncing = true

        if not sync.drag_active then
          sync.drag_active = true
          sync.undo_snapshot = deep_copy_subs(state.subtitles)
          if reaper.Undo_BeginBlock2 then reaper.Undo_BeginBlock2(0) end
        end
        sync.last_change_time = now_time
        sync.changed_sub_idx = i
        any_changed = true

        if item_diff and not rgn_diff then
          -- User modified item -> update region & subtitle
          local new_start = cur_item_pos
          local new_end = cur_item_pos + cur_item_len
          sub.start_time = new_start
          sub.end_time = new_end

          if entry.markrgnidx and cur_rgn_info then
            reaper.SetProjectMarker3(0, entry.markrgnidx, true, new_start, new_end, cur_rgn_info.name, cur_rgn_info.color)
            if reaper.UpdateTimeline then reaper.UpdateTimeline() end
          end

          entry.item_pos = cur_item_pos
          entry.item_len = cur_item_len
          entry.rgn_pos = new_start
          entry.rgn_end = new_end

        elseif rgn_diff and not item_diff then
          -- User modified region -> update item & subtitle
          local new_start = cur_rgn_pos
          local new_end = cur_rgn_end
          sub.start_time = new_start
          sub.end_time = new_end

          if entry.item and reaper.ValidatePtr2(0, entry.item, "MediaItem*") then
            reaper.SetMediaItemPosition(entry.item, new_start, false)
            reaper.SetMediaItemLength(entry.item, math.max(0.05, new_end - new_start), false)
            if reaper.UpdateArrange then reaper.UpdateArrange() end
          end

          entry.rgn_pos = cur_rgn_pos
          entry.rgn_end = cur_rgn_end
          entry.item_pos = new_start
          entry.item_len = math.max(0.05, new_end - new_start)

        elseif item_diff and rgn_diff then
          -- Both changed together (e.g. REAPER Undo)
          sub.start_time = cur_item_pos
          sub.end_time = cur_item_pos + cur_item_len
          entry.item_pos = cur_item_pos
          entry.item_len = cur_item_len
          if cur_rgn_pos then
            entry.rgn_pos = cur_rgn_pos
            entry.rgn_end = cur_rgn_end
          end
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
      if sync.undo_snapshot then
        if not state.undo_stack then state.undo_stack = {} end
        table.insert(state.undo_stack, {
          subtitles = sync.undo_snapshot,
          name = "Синхронизация длительности строки #" .. ch_idx
        })
        if #state.undo_stack > 50 then table.remove(state.undo_stack, 1) end
      end
      if reaper.Undo_EndBlock2 then
        reaper.Undo_EndBlock2(0, "NutNotes: Синхронизация длительности субтитра #" .. ch_idx, -1)
      end
      sync.undo_snapshot = nil
      state.save_to_project()
    end
  end
end

-- Update subtitle appearance on timeline (take name, notes, region name, colors)
function actions.update_subtitle_timeline(state, idx)
  if not reaper or not state or not state.subtitles or not state.subtitles[idx] then return end
  local sub = state.subtitles[idx]

  -- 1. Update MediaItem on track "subtitle"
  local tr = actions.find_subtitle_track()
  if tr then
    local num_items = reaper.CountTrackMediaItems(tr)
    for j = 0, num_items - 1 do
      local item = reaper.GetTrackMediaItem(tr, j)
      local _, stored_idx = reaper.GetSetMediaItemInfo_String(item, "P_EXT:NUTNOTES_SUB_IDX", "", false)
      if stored_idx == tostring(idx) or (stored_idx == "" and j == (idx - 1)) then
        local take = reaper.GetActiveTake(item)
        if take then
          local take_name = sub.raw_actor or sub.actor or ""
          if take_name == "NoActor" then take_name = "" end
          reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", take_name, true)
        end
        local primary_actor = (sub.actors and sub.actors[1]) or sub.actor
        if primary_actor ~= "NoActor" and state.actor_palette and state.actor_palette[primary_actor] then
          reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", state.actor_palette[primary_actor].reaper_color or 0)
        else
          reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", 0)
        end
        reaper.GetSetMediaItemInfo_String(item, "P_NOTES", parser.strip_invisible_unicode(sub.text), true)
        break
      end
    end
    if reaper.UpdateArrange then reaper.UpdateArrange() end
  end

  -- 2. Update project region
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  for m = 0, num_markers + num_regions - 1 do
    local retval, isrgn, pos, rgnend, name, markrgnidx, color = reaper.EnumProjectMarkers3(0, m)
    if retval > 0 and isrgn and markrgnidx == idx then
      local single_line_text = parser.strip_invisible_unicode(sub.text:gsub("\r\n", " "):gsub("\n", " "))
      local primary_actor = (sub.actors and sub.actors[1]) or sub.actor
      local rgn_name = ""
      local rgn_color = 0
      if primary_actor ~= "NoActor" then
        local actor_label = sub.raw_actor or sub.actor
        rgn_name = "[" .. actor_label .. "] " .. single_line_text
        if state.actor_palette and state.actor_palette[primary_actor] then
          rgn_color = state.actor_palette[primary_actor].reaper_color or 0
        end
      else
        rgn_name = single_line_text
        rgn_color = 0
      end
      reaper.SetProjectMarker3(0, markrgnidx, true, pos, rgnend, rgn_name, rgn_color)
      if reaper.UpdateTimeline then reaper.UpdateTimeline() end
      break
    end
  end
end

-- Update all timeline representations when actors are renamed or reset
function actions.update_all_timeline_actors(state)
  if not reaper or not state or not state.subtitles then return end
  for i = 1, #state.subtitles do
    actions.update_subtitle_timeline(state, i)
  end

  -- Clean up any extra media items on subtitle track whose index exceeds #state.subtitles
  local tr = actions.find_subtitle_track()
  if tr and reaper.CountTrackMediaItems and reaper.DeleteTrackMediaItem then
    local num_items = reaper.CountTrackMediaItems(tr)
    for j = num_items - 1, 0, -1 do
      local item = reaper.GetTrackMediaItem(tr, j)
      if item then
        local _, stored_idx_str = reaper.GetSetMediaItemInfo_String(item, "P_EXT:NUTNOTES_SUB_IDX", "", false)
        local s_idx = tonumber(stored_idx_str)
        if s_idx and s_idx > #state.subtitles then
          reaper.DeleteTrackMediaItem(tr, item)
        elseif not s_idx and j >= #state.subtitles then
          reaper.DeleteTrackMediaItem(tr, item)
        end
      end
    end
    if reaper.UpdateArrange then reaper.UpdateArrange() end
  end

  -- Clean up any extra project regions whose markrgnidx exceeds #state.subtitles
  if reaper.CountProjectMarkers and reaper.EnumProjectMarkers3 and reaper.DeleteProjectMarker then
    local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
    for m = (num_markers or 0) + (num_regions or 0) - 1, 0, -1 do
      local retval, isrgn, pos, rgnend, name, markrgnidx, color = reaper.EnumProjectMarkers3(0, m)
      if retval > 0 and isrgn and markrgnidx > #state.subtitles then
        reaper.DeleteProjectMarker(0, markrgnidx, true)
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

return actions
