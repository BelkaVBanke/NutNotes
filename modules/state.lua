--[[
  State management and per-project persistence module for REAPER Subtitle Plugin.
]]

local json = require('json')
local colors = require('colors')
local parser = require('parser')

local state = {
  version = "0.3.0-beta",
  -- Project identifier tracker
  last_proj = nil,

  -- Subtitles data
  filepath = nil,
  filename = nil,
  format = nil,
  subtitles = {},      -- Array of { start_time, end_time, actor, text }
  actors = {},         -- Array of string actor names
  actor_counts = {},   -- Map of { [actor] = count }
  actor_palette = {},  -- Map of { [actor] = { r, g, b, a, u32, reaper_color } }

  -- Filtering
  selected_actors = {}, -- Array of selected actor names for filtering (OR rule)
  selected_actors_set = {}, -- Quick lookup set { [actor] = true }

  -- Settings
  sync_with_filter = true,
  jump_on_click = true,
  auto_scroll = true,
  auto_scroll_mode = 3, -- 1: "нет", 2: "при воспроизведении", 3: "всегда"
  focus_mode = false, -- Lock mode: true = full-height distraction-free view

  -- Text & Typography settings
  text_font_family = "Segoe UI",
  text_font_size = 18.0,
  scroll_center_ratio = 0.40,
  text_active_larger = true,
  text_active_font_scale = 1.18,
  text_active_spacing = true,
  text_active_spacing_px = 8.0,
  text_highlight_brightness = 0.28,
  text_lead_in_time = 0.35,       -- Pre-roll interval (sec) before line begins to smoothly glide and enlarge
  smooth_scroll_enabled = true,   -- Smooth scroll interpolation
  smooth_scroll_speed = 14.0,     -- Exponential lerp speed for smooth scrolling
  row_alternating_bg = false,     -- Subtle alternating row background for inactive lines
  row_alternating_strength = 0.07, -- Subtle darkness factor for alternating rows (0.01 to 0.20)
  text_preview_collapsed = false, -- Collapsed state of live text preview in Tab 3

  -- General & Accent settings
  accent_color = { 0.16, 0.55, 0.35 }, -- Default accent RGB (Emerald: 0x298C59FF)
  control_box_palette = 1, -- 1: Graphite, 2: Light Tint, 3: Moderate Tint
  watermark_style = 1,     -- 1: Лесной орех и изумрудная дымка, 2: Адаптивная органика, 3: Карамельный орех

  -- Overlay settings
  overlay_enabled = false,
  overlay_always_on_top = false,
  overlay_bg_alpha = 0.75,
  overlay_bg_color = { 0.0, 0.0, 0.0, 0.75 },
  overlay_text_color = { 1.0, 1.0, 1.0, 1.0 },
  overlay_auto_fit = true,
  overlay_font_scale = 1.0,
  overlay_font_size = 24.0, -- Base font size for overlay lines (px)
  overlay_actor_font_size = 18.0, -- Dedicated font size for actor badge in overlay (px)
  overlay_next_font_size = 16.0, -- Dedicated font size for next subtitle preview in overlay (px)
  overlay_show_actor = true,
  overlay_actor_position = "top", -- Actor badge position in overlay: "top" (сверху) or "left" (слева)
  overlay_actor_left_layout = "grid", -- Layout when actor is on the left: "line" (строка [Актер] Текст) or "grid" (сетка: актеры слева, текст по центру)
  overlay_actor_gap = 12.0, -- Gap between actor column and text column in left grid mode (px)
  overlay_outline = true,
  overlay_align = 1, -- 0: Left, 1: Center, 2: Right
  overlay_show_next_preview = true, -- Preview next line below progress bar
  overlay_show_all_actors = true, -- If true, show lines from all actors regardless of filter
  overlay_tint_lines = false, -- Tint subtitle lines in overlay using actor's pastel color
  overlay_tint_only_filtered = false, -- If true, tint only lines belonging to filtered actors

  -- Undo Stack (Ctrl+Z)
  undo_stack = {},

  -- UI scale settings
  ui_font_size = 11.0,            -- Font size for interface controls, settings blocks, and actors table (px)
  tooltip_font_size = 14.0,       -- Font size for tooltips (px)
  popup_font_size = 16.0,         -- Font size for popups, context menus and modals (px)

  -- UI state
  active_tab = "TAB_SUBS",
  last_centered_idx = -1,
  active_sub_idx = nil,
  row_heights = {},
  suppress_autoscroll_until = 0,
  show_replace_modal = false,
  pending_filepath = nil,
  editing_idx = nil,
  show_inline_edit = false,
  edit_sub_data = nil,
  open_text_edit_popup = false,
  text_edit_idx = nil,
  text_edit_content = "",
  open_sub_actor_modal = false,
  sub_actor_modal_idx = nil,
  sub_actor_modal_name = "",
  sub_actor_modal_focused = false,
  open_rename_actor_modal = false,
  rename_actor_orig = nil,
  rename_actor_input = "",
  rename_actor_focused = false,
  startup_enabled = nil,
  toolbar_button_enabled = nil,
}

local EXT_SECTION = "NUTNOTES"
local LEGACY_EXT_SECTION = "REAPER_SUB_PLUGIN"

function state.refresh_filter_set()
  state.selected_actors_set = {}
  for _, actor in ipairs(state.selected_actors) do
    state.selected_actors_set[actor] = true
  end
  state.row_heights = {}
  state.last_centered_idx = -1
end

function state.is_actor_selected(actor)
  return state.selected_actors_set[actor] == true
end

function state.add_actor_filter(actor)
  if not state.selected_actors_set[actor] then
    table.insert(state.selected_actors, actor)
    state.refresh_filter_set()
    state.save_to_project()
  end
end

function state.remove_actor_filter(actor)
  for i, name in ipairs(state.selected_actors) do
    if name == actor then
      table.remove(state.selected_actors, i)
      break
    end
  end
  state.refresh_filter_set()
  state.save_to_project()
end

function state.toggle_actor_filter(actor)
  if state.is_actor_selected(actor) then
    state.remove_actor_filter(actor)
  else
    state.add_actor_filter(actor)
  end
end

function state.clear_actor_filter()
  state.selected_actors = {}
  state.refresh_filter_set()
  state.save_to_project()
end

-- Get filtered subtitles (if filter empty, returns all)
function state.get_filtered_subtitles()
  if #state.selected_actors == 0 then
    return state.subtitles
  end

  local filtered = {}
  for _, sub in ipairs(state.subtitles) do
    local is_match = false
    if sub.actors and #sub.actors > 0 then
      for _, a in ipairs(sub.actors) do
        if state.selected_actors_set[a] then
          is_match = true
          break
        end
      end
    else
      if state.selected_actors_set[sub.actor] then
        is_match = true
      end
    end

    if is_match then
      table.insert(filtered, sub)
    end
  end
  return filtered
end

-- Find subtitles active at time t
function state.get_active_subtitles(t)
  local active = {}
  local list = state.get_filtered_subtitles()
  for _, sub in ipairs(list) do
    if t >= sub.start_time and t <= sub.end_time then
      table.insert(active, sub)
    end
  end
  return active
end

-- Helper to deep copy subtitles table for undo snapshot
local function deep_copy_subtitles(subs)
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
      for j, a in ipairs(s.actors) do
        entry.actors[j] = a
      end
    end
    copy[i] = entry
  end
  return copy
end
state.deep_copy_subtitles = deep_copy_subtitles

local function deep_copy_table(t)
  if not t then return nil end
  local copy = {}
  for k, v in pairs(t) do
    if type(v) == "table" then
      copy[k] = deep_copy_table(v)
    else
      copy[k] = v
    end
  end
  return copy
end

-- Push snapshot to undo stack
function state.push_undo(action_name)
  if not state.undo_stack then state.undo_stack = {} end
  local snapshot = deep_copy_subtitles(state.subtitles)
  table.insert(state.undo_stack, {
    subtitles = snapshot,
    actor_palette = deep_copy_table(state.actor_palette),
    selected_actors = deep_copy_table(state.selected_actors),
    name = action_name or "Действие с субтитрами"
  })
  if #state.undo_stack > 50 then
    table.remove(state.undo_stack, 1)
  end
  if reaper and reaper.Undo_BeginBlock2 then
    reaper.Undo_BeginBlock2(0)
    reaper.Undo_EndBlock2(0, "NutNotes: " .. (action_name or "Редактирование"), -1)
  end
end

-- Perform Undo (Ctrl+Z)
function state.undo()
  if not state.undo_stack or #state.undo_stack == 0 then
    return false
  end
  local last_snapshot = table.remove(state.undo_stack)
  state.subtitles = deep_copy_subtitles(last_snapshot.subtitles)
  if last_snapshot.actor_palette then
    state.actor_palette = deep_copy_table(last_snapshot.actor_palette)
  end
  if last_snapshot.selected_actors then
    state.selected_actors = deep_copy_table(last_snapshot.selected_actors)
  end
  state.row_heights = {}
  state.active_sub_idx = nil
  state.last_centered_idx = -1
  state.refresh_actors_from_subtitles()
  state.refresh_filter_set()
  state.save_to_project()
  return true
end

-- Find real index of a subtitle table inside state.subtitles
function state.find_subtitle_index(sub_obj)
  if not sub_obj or not state.subtitles then return nil end
  for idx, s in ipairs(state.subtitles) do
    if s == sub_obj then
      return idx
    end
  end
  return nil
end

-- Refresh actors list and counts from current subtitles
function state.refresh_actors_from_subtitles()
  local actors_set = {}
  local actor_counts = {}
  local actors_list = {}
  for _, sub in ipairs(state.subtitles) do
    if sub.actors and #sub.actors > 0 then
      local seen_in_sub = {}
      for _, ma in ipairs(sub.actors) do
        if not seen_in_sub[ma] then
          seen_in_sub[ma] = true
          if not actors_set[ma] then
            actors_set[ma] = true
            table.insert(actors_list, ma)
          end
          actor_counts[ma] = (actor_counts[ma] or 0) + 1
        end
      end
    else
      local a = sub.actor or "NoActor"
      if not actors_set[a] then
        actors_set[a] = true
        table.insert(actors_list, a)
      end
      actor_counts[a] = (actor_counts[a] or 0) + 1
    end
  end
  state.actors = actors_list
  state.actor_counts = actor_counts
  if not state.actor_palette then state.actor_palette = {} end
  local full_pal = colors.generate_actor_palette(state.actors)
  for _, a in ipairs(state.actors) do
    if not state.actor_palette[a] then
      state.actor_palette[a] = full_pal[a]
    end
  end
end

-- Update subtitle at index (Undoable)
function state.update_subtitle(idx, new_sub)
  if state.subtitles[idx] then
    state.push_undo("Изменить строку #" .. idx)
    if new_sub.text then
      new_sub.text = parser.strip_invisible_unicode(new_sub.text)
    end
    state.subtitles[idx] = new_sub
    state.row_heights = {}
    state.refresh_actors_from_subtitles()
    state.save_to_project()
  end
end

-- Delete subtitle at index (Undoable)
function state.delete_subtitle(idx)
  if state.subtitles[idx] then
    state.push_undo("Удалить строку #" .. idx)
    table.remove(state.subtitles, idx)
    state.row_heights = {}
    state.active_sub_idx = nil
    state.last_centered_idx = -1
    state.refresh_actors_from_subtitles()
    state.save_to_project()
  end
end

function state.delete_subtitle_with_undo(idx)
  state.delete_subtitle(idx)
end

-- Change actor for a single subtitle line (Undoable)
function state.change_subtitle_actor_with_undo(idx, new_actor)
  local sub = state.subtitles[idx]
  if not sub then return false end

  new_actor = (new_actor and #new_actor > 0) and new_actor or "NoActor"
  local old_actor = sub.raw_actor or sub.actor or "NoActor"
  if old_actor == new_actor then return false end

  state.push_undo("Изменить актера строки #" .. idx .. " (" .. old_actor .. " -> " .. new_actor .. ")")

  local actors, character, display_actor = parser.parse_actor_and_character(new_actor)
  sub.raw_actor = new_actor
  sub.actor = display_actor
  sub.actors = actors
  sub.character = character

  state.row_heights = {}
  state.refresh_actors_from_subtitles()
  state.refresh_filter_set()
  state.save_to_project()
  return true
end

-- Helper to replace and deduplicate actor occurrences in raw actor strings (preserving character tags and brackets)
local function replace_and_dedup_actor_in_raw(cur_raw, from_actor, to_actor)
  if not cur_raw or cur_raw == "" then return to_actor end
  if cur_raw == from_actor then return to_actor end

  -- Check if bracketed: [A][B]...
  local bracket_matches = {}
  for b in cur_raw:gmatch("%[([^%]]+)%]") do
    table.insert(bracket_matches, b)
  end

  if #bracket_matches > 0 then
    local new_brackets = {}
    local seen_actors = {}
    for _, b_item in ipairs(bracket_matches) do
      local a_part = b_item
      local c_part = ""
      local dash_start, dash_end = b_item:find("%s+[%-—–]%s*")
      if not dash_start then dash_start, dash_end = b_item:find("%s*[%-—–]%s+") end
      if dash_start then
        a_part = b_item:sub(1, dash_start - 1):match("^%s*(.-)%s*$")
        c_part = b_item:sub(dash_end + 1):match("^%s*(.-)%s*$")
      else
        local p_act, p_char = b_item:match("^([^%(%)]+)%s*%(([^%(%)]+)%)%s*$")
        if p_act and p_char then
          a_part = p_act:match("^%s*(.-)%s*$")
          c_part = p_char:match("^%s*(.-)%s*$")
        end
      end

      local new_a = (a_part == from_actor) and to_actor or a_part
      if not seen_actors[new_a] then
        seen_actors[new_a] = true
        if #c_part > 0 then
          if dash_start then
            table.insert(new_brackets, string.format("[%s - %s]", new_a, c_part))
          else
            table.insert(new_brackets, string.format("[%s (%s)]", new_a, c_part))
          end
        else
          table.insert(new_brackets, string.format("[%s]", new_a))
        end
      end
    end

    if #new_brackets == 1 then
      local single_b = new_brackets[1]:match("^%[(.*)%]$")
      return single_b or new_brackets[1]
    else
      return table.concat(new_brackets, "")
    end
  end

  -- Check if single actor with character like "Actor (Char)" or "Actor - Char"
  local dash_start, dash_end = cur_raw:find("%s+[%-—–]%s*")
  if not dash_start then dash_start, dash_end = cur_raw:find("%s*[%-—–]%s+") end
  if dash_start then
    local a_part = cur_raw:sub(1, dash_start - 1):match("^%s*(.-)%s*$")
    local c_part = cur_raw:sub(dash_end + 1):match("^%s*(.-)%s*$")
    local parts = {}
    local seen = {}
    for part in a_part:gsub("%s*[%/;%&%+]%s*", "|"):gmatch("[^|]+") do
      local a = part:match("^%s*(.-)%s*$")
      local new_a = (a == from_actor) and to_actor or a
      if not seen[new_a] then
        seen[new_a] = true
        table.insert(parts, new_a)
      end
    end
    return string.format("%s - %s", table.concat(parts, "; "), c_part)
  end

  local p_act, p_char = cur_raw:match("^([^%(%)]+)%s*%(([^%(%)]+)%)%s*$")
  if p_act and p_char then
    local a_part = p_act:match("^%s*(.-)%s*$")
    local c_part = p_char:match("^%s*(.-)%s*$")
    local parts = {}
    local seen = {}
    for part in a_part:gsub("%s*[%/;%&%+]%s*", "|"):gmatch("[^|]+") do
      local a = part:match("^%s*(.-)%s*$")
      local new_a = (a == from_actor) and to_actor or a
      if not seen[new_a] then
        seen[new_a] = true
        table.insert(parts, new_a)
      end
    end
    return string.format("%s (%s)", table.concat(parts, "; "), c_part)
  end

  -- Plain delimited string: "A; B" or "A / B"
  local parts = {}
  local seen = {}
  for part in cur_raw:gsub("%s*[%/;%&%+]%s*", "|"):gmatch("[^|]+") do
    local a = part:match("^%s*(.-)%s*$")
    local new_a = (a == from_actor) and to_actor or a
    if not seen[new_a] then
      seen[new_a] = true
      table.insert(parts, new_a)
    end
  end
  return table.concat(parts, "; ")
end

-- Rename actor globally across all subtitle occurrences (Undoable)
-- Fails if new_name already exists in state.actors (strictly disallows merging via rename)
function state.rename_actor_globally_with_undo(old_name, new_name)
  if not old_name or not new_name or old_name == "" or new_name == "" or old_name == new_name then
    return false
  end

  -- Disallow renaming to an existing actor name
  for _, a in ipairs(state.actors) do
    if a == new_name and a ~= old_name then
      return false, "Actor already exists"
    end
  end

  state.push_undo(string.format("Переименовать актера %s -> %s", old_name, new_name))

  local count_changed = 0
  for _, sub in ipairs(state.subtitles) do
    local cur_raw = sub.raw_actor or sub.actor or "NoActor"
    local has_old = (cur_raw == old_name or sub.actor == old_name)

    if sub.actors then
      for _, a in ipairs(sub.actors) do
        if a == old_name then
          has_old = true
          break
        end
      end
    end

    if has_old then
      local new_raw = replace_and_dedup_actor_in_raw(cur_raw, old_name, new_name)
      local actors, character, display_actor = parser.parse_actor_and_character(new_raw)
      sub.raw_actor = new_raw
      sub.actor = display_actor
      sub.actors = actors
      sub.character = character
      count_changed = count_changed + 1
    end
  end

  -- Update selected_actors filter
  local new_selected = {}
  for _, a in ipairs(state.selected_actors) do
    local target = (a == old_name) and new_name or a
    table.insert(new_selected, target)
  end
  state.selected_actors = new_selected

  -- Transfer color palette mapping to new_name
  if state.actor_palette then
    if state.actor_palette[old_name] then
      state.actor_palette[new_name] = state.actor_palette[old_name]
      state.actor_palette[old_name] = nil
    end
  end

  state.row_heights = {}
  state.refresh_actors_from_subtitles()
  state.refresh_filter_set()
  state.save_to_project()
  return true
end

-- Merge source_actor into target_actor across all subtitle occurrences (Undoable)
-- Reassigns all lines of source_actor to target_actor, removes source_actor, preserves target_actor's color
function state.merge_actors_with_undo(source_actor, target_actor)
  if not source_actor or not target_actor or source_actor == "" or target_actor == "" or source_actor == target_actor then
    return false
  end

  state.push_undo(string.format("Объединить актера %s с %s", source_actor, target_actor))

  local count_changed = 0
  for _, sub in ipairs(state.subtitles) do
    local cur_raw = sub.raw_actor or sub.actor or "NoActor"
    local has_source = (cur_raw == source_actor or sub.actor == source_actor)

    if sub.actors then
      for _, a in ipairs(sub.actors) do
        if a == source_actor then
          has_source = true
          break
        end
      end
    end

    if has_source then
      local new_raw = replace_and_dedup_actor_in_raw(cur_raw, source_actor, target_actor)
      local actors, character, display_actor = parser.parse_actor_and_character(new_raw)
      sub.raw_actor = new_raw
      sub.actor = display_actor
      sub.actors = actors
      sub.character = character
      count_changed = count_changed + 1
    end
  end

  -- Deduplicate identical subtitle lines (same timing, actor, and text)
  local dedup_subs = {}
  local seen_lines = {}
  for _, s in ipairs(state.subtitles) do
    local key = string.format("%.3f_%.3f_%s_%s", s.start_time, s.end_time, s.actor or "", s.text or "")
    if not seen_lines[key] then
      seen_lines[key] = true
      table.insert(dedup_subs, s)
    end
  end
  state.subtitles = dedup_subs

  -- Update selected_actors filter (with deduplication on merge)
  local new_selected = {}
  local seen_selected = {}
  for _, a in ipairs(state.selected_actors) do
    local target = (a == source_actor) and target_actor or a
    if not seen_selected[target] then
      seen_selected[target] = true
      table.insert(new_selected, target)
    end
  end
  state.selected_actors = new_selected

  -- Preserve target_actor's palette color; remove source_actor from palette
  if state.actor_palette then
    state.actor_palette[source_actor] = nil
  end

  state.row_heights = {}
  state.refresh_actors_from_subtitles()
  state.refresh_filter_set()
  state.save_to_project()
  return true
end

-- Pack all settings into a serializable table
function state.get_settings_table()
  return {
    sync_with_filter = state.sync_with_filter,
    jump_on_click = state.jump_on_click,
    auto_scroll = state.auto_scroll,
    auto_scroll_mode = state.auto_scroll_mode,
    focus_mode = state.focus_mode,
    -- Text & Typography settings
    text_font_family = state.text_font_family,
    text_font_size = state.text_font_size,
    scroll_center_ratio = state.scroll_center_ratio,
    text_active_larger = state.text_active_larger,
    text_active_font_scale = state.text_active_font_scale,
    text_active_spacing = state.text_active_spacing,
    text_active_spacing_px = state.text_active_spacing_px,
    text_highlight_brightness = state.text_highlight_brightness,
    text_lead_in_time = state.text_lead_in_time,
    smooth_scroll_enabled = state.smooth_scroll_enabled,
    smooth_scroll_speed = state.smooth_scroll_speed,
    row_alternating_bg = state.row_alternating_bg,
    row_alternating_strength = state.row_alternating_strength,
    text_preview_collapsed = state.text_preview_collapsed,
    -- General & Accent settings
    accent_color = state.accent_color,
    control_box_palette = state.control_box_palette,
    watermark_style = state.watermark_style,
    -- Overlay settings
    overlay_enabled = state.overlay_enabled,
    overlay_always_on_top = state.overlay_always_on_top,
    overlay_bg_alpha = state.overlay_bg_alpha,
    overlay_bg_color = state.overlay_bg_color,
    overlay_text_color = state.overlay_text_color,
    overlay_auto_fit = state.overlay_auto_fit,
    overlay_font_scale = state.overlay_font_scale,
    overlay_font_size = state.overlay_font_size,
    overlay_actor_font_size = state.overlay_actor_font_size,
    overlay_next_font_size = state.overlay_next_font_size,
    overlay_show_actor = state.overlay_show_actor,
    overlay_actor_position = state.overlay_actor_position,
    overlay_actor_left_layout = state.overlay_actor_left_layout,
    overlay_actor_gap = state.overlay_actor_gap,
    overlay_outline = state.overlay_outline,
    overlay_align = state.overlay_align,
    overlay_show_next_preview = state.overlay_show_next_preview,
    overlay_show_all_actors = state.overlay_show_all_actors,
    overlay_tint_lines = state.overlay_tint_lines,
    overlay_tint_only_filtered = state.overlay_tint_only_filtered,
    -- UI scale settings
    ui_font_size = state.ui_font_size,
    tooltip_font_size = state.tooltip_font_size,
    popup_font_size = state.popup_font_size,
  }
end

-- Apply settings table
function state.apply_settings_table(s)
  if not s then return end
  if s.sync_with_filter ~= nil then state.sync_with_filter = s.sync_with_filter end
  if s.jump_on_click ~= nil then state.jump_on_click = s.jump_on_click end
  if s.auto_scroll ~= nil then state.auto_scroll = s.auto_scroll end
  if s.auto_scroll_mode ~= nil then state.auto_scroll_mode = s.auto_scroll_mode end
  if s.focus_mode ~= nil then state.focus_mode = s.focus_mode end

  if s.text_font_family ~= nil then state.text_font_family = s.text_font_family end
  if s.text_font_size ~= nil then state.text_font_size = s.text_font_size end
  if s.scroll_center_ratio ~= nil then state.scroll_center_ratio = s.scroll_center_ratio end
  if s.text_active_larger ~= nil then state.text_active_larger = s.text_active_larger end
  if s.text_active_font_scale ~= nil then state.text_active_font_scale = s.text_active_font_scale end
  if s.text_active_spacing ~= nil then state.text_active_spacing = s.text_active_spacing end
  if s.text_active_spacing_px ~= nil then state.text_active_spacing_px = s.text_active_spacing_px end
  if s.text_highlight_brightness ~= nil then state.text_highlight_brightness = s.text_highlight_brightness end
  if s.text_lead_in_time ~= nil then state.text_lead_in_time = s.text_lead_in_time end
  if s.smooth_scroll_enabled ~= nil then state.smooth_scroll_enabled = s.smooth_scroll_enabled end
  if s.smooth_scroll_speed ~= nil then state.smooth_scroll_speed = s.smooth_scroll_speed end
  if s.row_alternating_bg ~= nil then state.row_alternating_bg = s.row_alternating_bg end
  if s.row_alternating_strength ~= nil then state.row_alternating_strength = s.row_alternating_strength end
  if s.text_preview_collapsed ~= nil then state.text_preview_collapsed = s.text_preview_collapsed end
  if s.accent_color then state.accent_color = s.accent_color end
  if s.control_box_palette ~= nil then state.control_box_palette = s.control_box_palette end
  if s.watermark_style ~= nil then state.watermark_style = s.watermark_style end

  if s.overlay_enabled ~= nil then state.overlay_enabled = s.overlay_enabled end
  if s.overlay_always_on_top ~= nil then state.overlay_always_on_top = s.overlay_always_on_top end
  if s.overlay_bg_alpha ~= nil then state.overlay_bg_alpha = s.overlay_bg_alpha end
  if s.overlay_bg_color then state.overlay_bg_color = s.overlay_bg_color end
  if s.overlay_text_color then state.overlay_text_color = s.overlay_text_color end
  if s.overlay_auto_fit ~= nil then state.overlay_auto_fit = s.overlay_auto_fit end
  if s.overlay_font_scale ~= nil then state.overlay_font_scale = s.overlay_font_scale end
  if s.overlay_font_size ~= nil then state.overlay_font_size = s.overlay_font_size end
  if s.overlay_actor_font_size ~= nil then state.overlay_actor_font_size = s.overlay_actor_font_size end
  if s.overlay_next_font_size ~= nil then state.overlay_next_font_size = s.overlay_next_font_size end
  if s.overlay_show_actor ~= nil then state.overlay_show_actor = s.overlay_show_actor end
  if s.overlay_actor_position ~= nil then state.overlay_actor_position = s.overlay_actor_position end
  if s.overlay_actor_left_layout ~= nil then state.overlay_actor_left_layout = s.overlay_actor_left_layout end
  if s.overlay_actor_gap ~= nil then state.overlay_actor_gap = s.overlay_actor_gap end
  if s.overlay_outline ~= nil then state.overlay_outline = s.overlay_outline end
  if s.overlay_align ~= nil then state.overlay_align = s.overlay_align end
  if s.overlay_show_next_preview ~= nil then state.overlay_show_next_preview = s.overlay_show_next_preview end
  if s.overlay_show_all_actors ~= nil then state.overlay_show_all_actors = s.overlay_show_all_actors end
  if s.overlay_tint_lines ~= nil then state.overlay_tint_lines = s.overlay_tint_lines end
  if s.overlay_tint_only_filtered ~= nil then state.overlay_tint_only_filtered = s.overlay_tint_only_filtered end

  if s.ui_font_size ~= nil then state.ui_font_size = s.ui_font_size end
  if s.tooltip_font_size ~= nil then state.tooltip_font_size = s.tooltip_font_size end
  if s.popup_font_size ~= nil then state.popup_font_size = s.popup_font_size end
end

-- Save settings both to reaper-extstate.ini (globally across sessions) and to project
function state.save_settings()
  local settings = state.get_settings_table()
  local encoded = json.encode(settings)
  if reaper then
    if reaper.SetExtState then
      reaper.SetExtState(EXT_SECTION, "GLOBAL_SETTINGS", encoded, true)
    end
    if reaper.SetProjExtState then
      reaper.SetProjExtState(0, EXT_SECTION, "SETTINGS", encoded)
    end
  end
end

-- Load settings from global reaper-extstate.ini
function state.load_global_settings()
  if not reaper or not reaper.GetExtState then return end
  local str = reaper.GetExtState(EXT_SECTION, "GLOBAL_SETTINGS")
  if (not str or #str == 0) and reaper.GetExtState then
    str = reaper.GetExtState(LEGACY_EXT_SECTION, "GLOBAL_SETTINGS")
  end
  if str and #str > 0 then
    local s = json.decode(str)
    if s then
      state.apply_settings_table(s)
    end
  end
end

-- Save current state to REAPER active project
function state.save_to_project()
  if not reaper or not reaper.SetProjExtState then return end

  local meta = {
    filename = state.filename,
    filepath = state.filepath,
    format = state.format,
    count = #state.subtitles
  }
  reaper.SetProjExtState(0, EXT_SECTION, "META", json.encode(meta))

  -- Subtitles
  reaper.SetProjExtState(0, EXT_SECTION, "SUBTITLES", json.encode(state.subtitles))

  -- Actors & Palette
  local actors_save = {
    actors = state.actors,
    actor_counts = state.actor_counts,
    actor_palette = state.actor_palette
  }
  reaper.SetProjExtState(0, EXT_SECTION, "ACTORS", json.encode(actors_save))

  -- Persist settings globally and in project
  state.save_settings()
end

-- Load state from REAPER active project
function state.load_from_project()
  -- Always restore global settings first so user preferences are intact
  state.load_global_settings()

  if not reaper or not reaper.GetProjExtState then return false end

  local _, meta_str = reaper.GetProjExtState(0, EXT_SECTION, "META")
  local sec_to_use = EXT_SECTION
  if not meta_str or #meta_str == 0 then
    -- Fallback to legacy project state
    local _, leg_meta = reaper.GetProjExtState(0, LEGACY_EXT_SECTION, "META")
    if leg_meta and #leg_meta > 0 then
      meta_str = leg_meta
      sec_to_use = LEGACY_EXT_SECTION
    end
  end

  if not meta_str or #meta_str == 0 then
    -- No saved subtitles in this project
    state.filepath = nil
    state.filename = nil
    state.format = nil
    state.subtitles = {}
    state.actors = {}
    state.actor_counts = {}
    state.actor_palette = {}
    state.selected_actors = {}
    state.refresh_filter_set()
    return false
  end

  local meta = json.decode(meta_str)
  if meta then
    state.filename = meta.filename
    state.filepath = meta.filepath
    state.format = meta.format
  end

  local _, subs_str = reaper.GetProjExtState(0, sec_to_use, "SUBTITLES")
  if subs_str and #subs_str > 0 then
    state.subtitles = json.decode(subs_str) or {}
    for _, s in ipairs(state.subtitles) do
      if s.text then
        s.text = parser.strip_invisible_unicode(s.text)
      end
    end
  else
    state.subtitles = {}
  end

  local _, actors_str = reaper.GetProjExtState(0, sec_to_use, "ACTORS")
  if actors_str and #actors_str > 0 then
    local actors_data = json.decode(actors_str)
    if actors_data then
      state.actors = actors_data.actors or {}
      state.actor_counts = actors_data.actor_counts or {}
      state.actor_palette = actors_data.actor_palette or {}
    end
  end

  local _, settings_str = reaper.GetProjExtState(0, EXT_SECTION, "SETTINGS")
  if settings_str and #settings_str > 0 then
    local s = json.decode(settings_str)
    if s and s.selected_actors then
      state.selected_actors = s.selected_actors
    end
  end

  state.refresh_filter_set()
  return true
end

-- Load from a file path
function state.load_file(filepath)
  local res = parser.parse_file(filepath)
  if not res or not res.ok then
    return false, res and res.error or "Unknown parse error"
  end

  state.undo_stack = {}
  state.filepath = filepath
  state.filename = res.filename
  state.format = res.format
  state.subtitles = res.subtitles
  for _, s in ipairs(state.subtitles) do
    if s.text then
      s.text = parser.strip_invisible_unicode(s.text)
    end
  end
  state.actors = res.actors
  state.actor_counts = res.actor_counts

  -- Generate default pastel palette for actors
  state.actor_palette = colors.generate_actor_palette(state.actors)

  -- Reset filter selection and runtime active state
  state.selected_actors = {}
  state.refresh_filter_set()
  state.active_sub_idx = nil
  state.row_heights = {}

  -- Save to current project
  state.save_to_project()
  return true
end

-- Detect if active project changed (e.g. project tab switch)
function state.check_project_changed()
  if not reaper or not reaper.EnumProjects then return false end
  local cur_proj = reaper.EnumProjects(-1)
  if cur_proj ~= state.last_proj then
    state.last_proj = cur_proj
    state.load_from_project()
    return true
  end
  return false
end

-- Initialize global settings on module load
state.load_global_settings()

return state
