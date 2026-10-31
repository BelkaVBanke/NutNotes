--[[
  State management and per-project persistence module for REAPER Subtitle Plugin.
]]

local json = require('json')
local colors = require('colors')
local parser = require('parser')

local state = {
  version = "0.5.1-beta",
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

  -- Filtering & Search
  selected_actors = {}, -- Array of selected actor names for filtering (OR rule)
  selected_actors_set = {}, -- Quick lookup set { [actor] = true }
  search_query = "",        -- Text search filter for subtitles

  -- Settings
  sync_with_filter = true,
  jump_on_click = true,
  auto_scroll = true,
  auto_scroll_mode = 3, -- 1: "нет", 2: "при воспроизведении", 3: "всегда"
  focus_mode = false, -- Lock mode: true = full-height distraction-free view
  show_actor_in_row = false, -- Display actor name tag in subtitle list rows
  text_actor_display_mode = 1, -- 1: "Актер", 2: "Актер - Персонаж"
  text_tint_lines = true, -- Tint subtitle dialogue lines with actor's color (default true for current behavior)
  text_custom_color = { 175 / 255, 175 / 255, 175 / 255 }, -- Default monochrome text color when text_tint_lines == false (0xAFAFAFFF)
  text_tint_actor_names = true, -- Tint actor badge name with actor's color (default true for current behavior)
  hotkey_create_sub = "Shift+T", -- Hotkey to create subtitle from REAPER time selection
  parse_srt_actors = true, -- Parse actors from SRT with smart heuristics (if false, load all as NoActor)

  -- Text & Typography settings
  text_font_family = "Segoe UI",
  text_font_size = 18.0,
  scroll_center_ratio = 0.40,
  text_active_larger = true,
  text_active_font_scale = 1.18,
  text_active_spacing = true,
  text_active_spacing_px = 8.0,
  text_highlight_brightness = 0.28,
  text_fixed_lead_in = false,     -- If true, fixed lookahead; if false, triggers immediately upon replica completion
  text_lead_in_time = 0.35,       -- Pre-roll interval (sec) before line begins to smoothly glide and enlarge
  smooth_scroll_enabled = true,   -- Smooth scroll interpolation
  smooth_scroll_speed = 14.0,     -- Exponential lerp speed for smooth scrolling
  row_alternating_bg = false,     -- Subtle alternating row background for inactive lines
  row_alternating_strength = 0.07, -- Subtle darkness factor for alternating rows (0.01 to 0.20)
  text_preview_collapsed = false, -- Collapsed state of live text preview in Tab 3

  -- View mode settings
  view_mode = "table",           -- "table" (default full table list) or "note" (single active line SWS style)
  note_auto_wrap = true,         -- Auto-wrap lines in Note view to maximize font size
  note_min_font_size = 18.0,     -- Minimum font size in Note view (px)
  note_max_font_size = 72.0,     -- Maximum font size in Note view (px)
  note_show_actor = true,        -- Show actor badge in Note view
  note_show_progress = true,     -- Show progress bar and hold indication in Note view
  note_edit_font_size = 20.0,    -- Editable text font size in non-focus Note view (px)

  -- Region sync flag
  regions_enabled = true,        -- Timeline regions enabled flag (checkbox)

  -- General & Accent settings
  accent_color = { 35 / 255, 35 / 255, 35 / 255 }, -- Default accent RGB: Black (35, 35, 35) (0x232323FF)
  default_region_color = nil, -- Default region color {r, g, b} for NoActor or single actor (nil = theme default)
  control_box_palette = 1, -- 1: Graphite, 2: Light Tint, 3: Moderate Tint
  watermark_style = 1,     -- 1: Лесной орех и изумрудная дымка, 2: Адаптивная органика, 3: Карамельный орех

  -- Overlay settings
  overlay_enabled = false,
  timer_overlay_enabled = false, -- Dedicated floating timer overlay for script-based recording
  timer_overlay_font_family = "Segoe UI", -- Font family for timer overlay
  timer_overlay_format = 1, -- 1: MM:SS.dd, 2: HH:MM:SS.dd, 3: SS.dd, 4: MM:SS.d, 5: HH:MM:SS.d, 6: SS.d, 7: MM:SS, 8: HH:MM:SS
  timer_overlay_color_mode = 1, -- 1: Нет (по умолчанию, свой цвет / белый), 2: Включено (динамическая индикация статуса REAPER)
  timer_custom_color = { 1.0, 1.0, 1.0, 1.0 }, -- Default white
  timer_overlay_bg_alpha = 0.75,
  timer_overlay_bg_color = { 0.0, 0.0, 0.0, 0.75 },
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
  overlay_hide_progress = false, -- If true, hide speech progress bar / countdown in overlay
  overlay_show_all_actors = true, -- If true, show lines from all actors regardless of filter
  overlay_tint_lines = false, -- Tint subtitle lines in overlay using actor's pastel color
  overlay_tint_only_filtered = false, -- If true, tint only lines belonging to filtered actors
  text_show_cps = false, -- If true, show CPS badge in Tab 1 rows (right of time/actor, left of text)
  text_sync_overlay_hold = true, -- If true, sync replica hold state with overlay (hold bar color & +X.Xs text)
  overlay_hold_mode = 2, -- 1: Off (strict timing), 2: Gaps only (default), 3: Cascading shift with overlap
  overlay_target_cps = 17.0, -- Target reading speed (chars/sec) for hold/shift calculation (default 17.0)
  overlay_max_hold = 0.7, -- Max hold duration per line in gaps (sec, default 0.7)
  overlay_max_drift = 2.5, -- Max cumulative cascade drift (sec, default 2.5)
  overlay_show_drift_badge = true, -- Show overtime/drift badge (+X.Xs) in overlay

  -- Optimization: Dynamic timeline region streaming
  timeline_streaming_enabled = false, -- Default false
  timeline_streaming_radius_min = 5.0, -- Default 5 minutes
  timeline_streaming_min_subs = 3000, -- Default 3000 subtitles threshold

  -- Undo Stack & REAPER native sync
  undo_stack = {},
  undo_history = {},
  current_step_id = nil,
  next_step_id = 1,
  _projects_cache = {},

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
  time_selection_error_msg = nil,
  time_selection_error_until = 0,
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
  state.filter_revision = (state.filter_revision or 0) + 1
  state.need_calc_scroll_target = true
  state.suppress_autoscroll_until = 0
  state.scroll_target_y = nil
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

-- Get filtered subtitles (filters by selected actors and optional search_query)
function state.get_filtered_subtitles()
  local has_actor_filter = (#state.selected_actors > 0)
  local raw_query = state.search_query and state.search_query:match("^%s*(.-)%s*$") or ""
  local query = parser.utf8_lower(raw_query)
  local has_query = (#query > 0)

  if not has_actor_filter and not has_query then
    return state.subtitles
  end

  local filtered = {}
  for _, sub in ipairs(state.subtitles) do
    local actor_match = true
    if has_actor_filter then
      actor_match = false
      if sub.actors and #sub.actors > 0 then
        for _, a in ipairs(sub.actors) do
          if state.selected_actors_set[a] then
            actor_match = true
            break
          end
        end
      else
        if state.selected_actors_set[sub.actor] then
          actor_match = true
        end
      end
    end

    local text_match = true
    if has_query then
      local sub_text = parser.utf8_lower(sub.text or "")
      if not sub_text:find(query, 1, true) then
        text_match = false
      end
    end

    if actor_match and text_match then
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

-- Invisible UTF-8 Zero-Width encoding for NutNotes state marker
-- ZWSP (U+200B) = \xE2\x80\x8B
-- ZWNJ (U+200C) = \xE2\x80\x8C
-- ZWJ  (U+200D) = \xE2\x80\x8D
local ZWSP = "\xE2\x80\x8B"
local ZWNJ = "\xE2\x80\x8C"
local ZWJ  = "\xE2\x80\x8D"
local INVISIBLE_ANCHOR_PREFIX = ZWSP .. ZWSP
local LEGACY_ANCHOR_PREFIX = "\xE2\x80\x8B\xE2\x80\x8C_NN_STATE:"

local function encode_anchor_step(step_id)
  local n = tonumber(step_id) or 1
  local bits = {}
  while n > 0 do
    local b = n % 2
    table.insert(bits, 1, (b == 0 and ZWNJ or ZWJ))
    n = math.floor(n / 2)
  end
  if #bits == 0 then table.insert(bits, ZWNJ) end
  return INVISIBLE_ANCHOR_PREFIX .. table.concat(bits)
end

local function decode_anchor_step(name)
  if not name or type(name) ~= "string" then return nil end
  -- Check plain readable tag format (in hidden NutNotesStateLane)
  local plain_step = name:match("^_NN_STATE:(%d+)$")
  if plain_step then
    return tonumber(plain_step)
  end

  -- Check 100% invisible zero-width format
  if name:sub(1, #INVISIBLE_ANCHOR_PREFIX) == INVISIBLE_ANCHOR_PREFIX then
    local payload = name:sub(#INVISIBLE_ANCHOR_PREFIX + 1)
    local n = 0
    local count = 0
    local i = 1
    while i <= #payload do
      local char = payload:sub(i, i + 2)
      if char == ZWNJ then
        n = n * 2
        count = count + 1
        i = i + 3
      elseif char == ZWJ then
        n = n * 2 + 1
        count = count + 1
        i = i + 3
      else
        break
      end
    end
    if count > 0 then return n end
  end

  -- Fallback to legacy tag format
  if name:sub(1, #LEGACY_ANCHOR_PREFIX) == LEGACY_ANCHOR_PREFIX then
    local step_str = name:sub(#LEGACY_ANCHOR_PREFIX + 1)
    return tonumber(step_str)
  end

  return nil
end

-- Find or create a hidden ruler lane for NutNotes state marker (REAPER 7+)
function state.get_or_create_state_lane()
  if not reaper or not reaper.GetSetProjectInfo or not reaper.GetSetProjectInfo_String then return nil end
  local count = reaper.GetSetProjectInfo(0, "RULER_LANE_COUNT", 0, false)
  if not count or count <= 0 then return nil end

  -- Search for existing NutNotesStateLane
  for i = 0, count - 1 do
    local _, name = reaper.GetSetProjectInfo_String(0, "RULER_LANE_NAME:" .. tostring(i), "", false)
    if name == "NutNotesStateLane" then
      -- Ensure it is hidden
      reaper.GetSetProjectInfo(0, "RULER_LANE_HIDDEN:" .. tostring(i), 1, true)
      return i
    end
  end

  -- Not found: add a new ruler lane at position 'count'
  -- In REAPER 7, GetSetProjectInfo with RULER_LANE_ORDER:<target_pos> and parm_val = -1 inserts a new lane
  reaper.GetSetProjectInfo(0, "RULER_LANE_ORDER:" .. tostring(count), -1, true)
  local new_count = reaper.GetSetProjectInfo(0, "RULER_LANE_COUNT", 0, false)
  if new_count and new_count > count then
    local new_lane = new_count - 1
    reaper.GetSetProjectInfo_String(0, "RULER_LANE_NAME:" .. tostring(new_lane), "NutNotesStateLane", true)
    reaper.GetSetProjectInfo(0, "RULER_LANE_HIDDEN:" .. tostring(new_lane), 1, true)
    return new_lane
  end
  return nil
end

function state.get_default_region_color()
  if state.default_region_color and type(state.default_region_color) == "table" then
    return state.default_region_color[1] or 0.314, state.default_region_color[2] or 0.522, state.default_region_color[3] or 0.522
  end
  if reaper and reaper.GetThemeColor then
    local tc = reaper.GetThemeColor("region", 0)
    if tc and tc >= 0 then
      local r = (tc & 0xFF) / 255
      local g = ((tc >> 8) & 0xFF) / 255
      local b = ((tc >> 16) & 0xFF) / 255
      return r, g, b
    end
  end
  return 80 / 255, 133 / 255, 133 / 255
end

function state.get_default_region_reaper_color()
  if not state.default_region_color then
    return 0 -- 0 tells REAPER to use default theme region color
  end
  local r, g, b = state.get_default_region_color()
  return colors.rgb_to_reaper(r, g, b)
end

local function get_anchor_color()
  if state.default_region_color then
    local r, g, b = state.get_default_region_color()
    return colors.rgb_to_reaper(r, g, b)
  end
  if reaper and reaper.GetThemeColor then
    local tc = reaper.GetThemeColor("region", 0)
    if tc and tc >= 0 then
      return (tc | 0x1000000)
    end
  end
  if reaper and reaper.ColorToNative then
    return (reaper.ColorToNative(80, 133, 133) | 0x1000000)
  end
  return 0
end

local function ensure_marker_in_state_lane(markrgnindexnumber, lane_idx)
  if not lane_idx or not reaper or not reaper.GetRegionOrMarker or not reaper.SetRegionOrMarkerInfo_Value then
    return
  end
  local _, nm, nr = reaper.CountProjectMarkers(0)
  for i = 0, (nm + nr) - 1 do
    local retval, isrgn, pos, rgnend, mname, mid = reaper.EnumProjectMarkers3(0, i)
    if retval > 0 and not isrgn and mid == markrgnindexnumber then
      local pm = reaper.GetRegionOrMarker(0, i, "")
      if pm then
        reaper.SetRegionOrMarkerInfo_Value(0, pm, "I_LANENUMBER", lane_idx)
        reaper.SetRegionOrMarkerInfo_Value(0, pm, "B_HIDDEN", 1)
        if reaper.UpdateTimeline then reaper.UpdateTimeline() end
      end
      return
    end
  end
end

function state.get_or_create_anchor_marker()
  if not reaper or not reaper.CountProjectMarkers or not reaper.EnumProjectMarkers3 then return nil, 1 end
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  for i = 0, (num_markers + num_regions) - 1 do
    local retval, isrgn, pos, rgnend, name, markrgnidx = reaper.EnumProjectMarkers3(0, i)
    if retval > 0 and not isrgn then
      local step = decode_anchor_step(name)
      if step then
        local target_col = get_anchor_color()
        -- Migrate to ID 0 and default region color to blend in seamlessly on older REAPER versions
        if reaper.SetProjectMarkerByIndex2 then
          reaper.SetProjectMarkerByIndex2(0, i, false, 0, 0, 0, name, target_col, 0)
          markrgnidx = 0
        else
          reaper.SetProjectMarker3(0, markrgnidx, false, 0, 0, name, target_col)
        end

        -- Marker exists! Make sure it is tucked into NutNotesStateLane and hidden if REAPER 7.62+
        local lane_idx = state.get_or_create_state_lane()
        if lane_idx then
          ensure_marker_in_state_lane(markrgnidx, lane_idx)
          local wanted_name = "_NN_STATE:" .. tostring(step)
          if name ~= wanted_name then
            reaper.SetProjectMarker3(0, markrgnidx, false, 0, 0, wanted_name, target_col)
          end
        end
        return markrgnidx, step
      end
    end
  end
  -- Marker not found: check if hidden Ruler Lane exists (REAPER 7.62+)
  local initial_step = 1
  local lane_idx = state.get_or_create_state_lane()
  local name = lane_idx and ("_NN_STATE:" .. tostring(initial_step)) or encode_anchor_step(initial_step)
  local col = get_anchor_color()
  -- ID 0 produces the smallest possible marker footprint in older REAPER versions
  local new_idx = reaper.AddProjectMarker2(0, false, 0, 0, name, 0, col)
  if lane_idx and new_idx >= 0 then
    ensure_marker_in_state_lane(new_idx, lane_idx)
  end
  return new_idx, initial_step
end

function state.get_current_anchor_step()
  if not reaper or not reaper.CountProjectMarkers or not reaper.EnumProjectMarkers3 then return nil end
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  for i = 0, (num_markers + num_regions) - 1 do
    local retval, isrgn, pos, rgnend, name = reaper.EnumProjectMarkers3(0, i)
    if retval > 0 and not isrgn then
      local step = decode_anchor_step(name)
      if step then
        return step
      end
    end
  end
  return nil
end

function state.capture_snapshot(action_name)
  local has_rgns = nil
  local has_itms = nil
  local ok_act, actions = pcall(require, 'actions')
  if ok_act and actions then
    if actions.timeline_sync and actions.timeline_sync.last_rgn_count and actions.timeline_sync.last_rgn_count >= 0 then
      has_rgns = (actions.timeline_sync.last_rgn_count > 0)
    elseif actions.has_plugin_regions then
      has_rgns = actions.has_plugin_regions()
    end
  end
  return {
    subtitles = deep_copy_subtitles(state.subtitles),
    actor_palette = deep_copy_table(state.actor_palette),
    selected_actors = deep_copy_table(state.selected_actors),
    default_region_color = state.default_region_color and { state.default_region_color[1], state.default_region_color[2], state.default_region_color[3] },
    regions_displayed = has_rgns,
    filename = state.filename,
    filepath = state.filepath,
    name = action_name or "Действие с субтитрами"
  }
end

function state.init_undo_tracking()
  if not reaper then return end
  local markrgnidx, cur_step = state.get_or_create_anchor_marker()
  state.current_step_id = cur_step or 1
  state.next_step_id = state.current_step_id
  if not state.undo_history then state.undo_history = {} end
  if not state.undo_history[state.current_step_id] then
    state.undo_history[state.current_step_id] = state.capture_snapshot("Исходное состояние")
  end
end

-- Push snapshot or delta to REAPER native undo
function state.push_undo(action_name, old_snapshot, on_commit, delta)
  if not reaper or not reaper.Undo_BeginBlock2 then
    if on_commit then pcall(on_commit) end
    return
  end

  local markrgnidx, cur_step = state.get_or_create_anchor_marker()
  if not markrgnidx then
    if on_commit then pcall(on_commit) end
    return
  end

  cur_step = cur_step or state.current_step_id or 1
  if not state.undo_history then state.undo_history = {} end

  -- Store pre-action snapshot at cur_step if not already stored
  if old_snapshot then
    state.undo_history[cur_step] = old_snapshot
  elseif not state.undo_history[cur_step] then
    state.undo_history[cur_step] = state.capture_snapshot("Предыдущее состояние")
  end

  local next_step = (math.max(state.next_step_id or 1, cur_step)) + 1
  state.next_step_id = next_step

  -- Store post-action snapshot or delta at next_step
  if delta and not old_snapshot then
    state.undo_history[next_step] = { delta = delta, name = action_name }
  else
    state.undo_history[next_step] = state.capture_snapshot(action_name)
  end

  -- Prune old history steps beyond 150 steps from current to keep memory strictly bounded
  local max_history = 150
  for step, _ in pairs(state.undo_history) do
    if step < (next_step - max_history) then
      state.undo_history[step] = nil
    end
  end

  -- Record project modification inside native REAPER undo block (in hidden NutNotesStateLane or invisible zero-width name)
  local lane_idx = state.get_or_create_state_lane()
  local marker_name = lane_idx and ("_NN_STATE:" .. tostring(next_step)) or encode_anchor_step(next_step)
  local marker_col = get_anchor_color()

  reaper.Undo_BeginBlock2(0)

  -- Commit timeline/project changes strictly INSIDE the REAPER undo block
  -- so REAPER bundles them with this action instead of leaking into subsequent time selection or user actions!
  if on_commit then
    local ok, err = pcall(on_commit)
    if not ok and reaper and reaper.ShowConsoleMsg then
      reaper.ShowConsoleMsg("[NutNotes on_commit Error]: " .. tostring(err) .. "\n")
    end
  end

  reaper.SetProjectMarker3(0, markrgnidx, false, 0, 0, marker_name, marker_col)
  if lane_idx then
    ensure_marker_in_state_lane(markrgnidx, lane_idx)
  end
  reaper.Undo_EndBlock2(0, "NutNotes: " .. (action_name or "Действие с субтитрами"), -1)

  state.current_step_id = next_step
end

-- Check if native REAPER Undo / Redo altered project step
function state.check_reaper_undo_sync(actions)
  if not reaper then return false end
  local cur_step = state.get_current_anchor_step()

  -- If anchor marker is missing, REAPER has rolled back before the anchor marker existed (e.g. Initial State)!
  if not cur_step then
    if state.current_step_id and state.current_step_id > 1 then
      cur_step = 1
    else
      return false
    end
  end

  if state.current_step_id == nil then
    state.init_undo_tracking()
    return false
  end

  if cur_step == state.current_step_id then
    return false
  end

  local prev_step = state.current_step_id

  if not state.undo_history then state.undo_history = {} end

  -- Suppress timeline sync false-drag detection while REAPER is rolling back
  if not actions then
    local ok_act, act_mod = pcall(require, 'actions')
    if ok_act then actions = act_mod end
  end
  if actions and actions.timeline_sync then
    actions.timeline_sync.drag_active = false
    actions.timeline_sync.suppress_until = (reaper.time_precise and reaper.time_precise() or os.clock()) + 0.5
  end

  local function apply_snapshot(target)
    if target and target.subtitles then
      state.subtitles = deep_copy_subtitles(target.subtitles)
      if target.actor_palette then state.actor_palette = deep_copy_table(target.actor_palette) end
      if target.selected_actors then state.selected_actors = deep_copy_table(target.selected_actors) end
      state.filename = target.filename
      state.filepath = target.filepath
      if #state.subtitles == 0 and actions and actions.clear_regions then
        actions.clear_regions()
      elseif target.regions_displayed == false and actions and actions.clear_regions then
        actions.clear_regions()
      end
    elseif cur_step <= 1 then
      state.subtitles = {}
      state.filename = nil
      state.filepath = nil
      state.selected_actors = {}
      if actions and actions.clear_regions then
        actions.clear_regions()
      end
    end
  end

  if cur_step < prev_step then
    local target = state.undo_history[cur_step]
    if target and target.subtitles then
      apply_snapshot(target)
    else
      -- UNDO: Roll backwards from prev_step down to cur_step + 1 via deltas
      for s = prev_step, cur_step + 1, -1 do
        local rec = state.undo_history[s]
        if rec and rec.delta then
          local d = rec.delta
          if d.type == "insert" then
            if d.idx and d.idx >= 1 and d.idx <= #state.subtitles then
              table.remove(state.subtitles, d.idx)
            end
            if actions and actions.timeline_sync and actions.timeline_sync.sub_map and d.idx and d.idx >= 1 and d.idx <= #actions.timeline_sync.sub_map then
              table.remove(actions.timeline_sync.sub_map, d.idx)
            end
          elseif d.type == "delete" then
            if d.idx and d.sub then
              table.insert(state.subtitles, math.min(d.idx, #state.subtitles + 1), d.sub)
              state.prepare_sub_props(d.sub)
            end
          end
        elseif rec and rec.subtitles then
          apply_snapshot(rec)
        end
      end
      if cur_step <= 1 and #state.subtitles == 0 and actions and actions.clear_regions then
        actions.clear_regions()
      end
    end
  elseif cur_step > prev_step then
    local target = state.undo_history[cur_step]
    if target and target.subtitles then
      apply_snapshot(target)
    else
      -- REDO: Roll forward from prev_step + 1 up to cur_step via deltas
      for s = prev_step + 1, cur_step do
        local rec = state.undo_history[s]
        if rec and rec.delta then
          local d = rec.delta
          if d.type == "insert" then
            if d.idx and d.sub then
              table.insert(state.subtitles, math.min(d.idx, #state.subtitles + 1), d.sub)
              state.prepare_sub_props(d.sub)
            end
          elseif d.type == "delete" then
            if d.idx and d.idx >= 1 and d.idx <= #state.subtitles then
              table.remove(state.subtitles, d.idx)
            end
            if actions and actions.timeline_sync and actions.timeline_sync.sub_map and d.idx and d.idx >= 1 and d.idx <= #actions.timeline_sync.sub_map then
              table.remove(actions.timeline_sync.sub_map, d.idx)
            end
          end
        elseif rec and rec.subtitles then
          state.subtitles = deep_copy_subtitles(rec.subtitles)
          if rec.actor_palette then state.actor_palette = deep_copy_table(rec.actor_palette) end
          if rec.selected_actors then state.selected_actors = deep_copy_table(rec.selected_actors) end
          state.filename = rec.filename
          state.filepath = rec.filepath
        end
      end
    end
  end

  state.current_step_id = cur_step
  state.row_heights = {}
  state.user_selected_row_idx = nil
  state.selected_real_sub_idx = nil
  state.active_sub_idx = nil
  state.last_centered_idx = -1
  state.refresh_actors_from_subtitles()
  state.refresh_filter_set()

  if not actions then
    local ok_act, act_mod = pcall(require, 'actions')
    if ok_act then actions = act_mod end
  end

  if actions and actions.ensure_regions_synced then
    actions.ensure_regions_synced(state)
  elseif actions and actions.init_timeline_sync then
    actions.init_timeline_sync(state)
  end

  if reaper.UpdateTimeline then reaper.UpdateTimeline() end
  if reaper.UpdateArrange then reaper.UpdateArrange() end

  state.save_to_project(state.last_proj)
  return true
end

-- Perform REAPER Native Undo (Ctrl+Z)
function state.undo(actions)
  if not actions then
    local ok_act, act_mod = pcall(require, 'actions')
    if ok_act then actions = act_mod end
  end
  if actions and actions.timeline_sync then
    actions.timeline_sync.drag_active = false
    actions.timeline_sync.suppress_until = (reaper.time_precise and reaper.time_precise() or os.clock()) + 0.4
  end
  if reaper and reaper.Undo_DoUndo2 then
    local res = reaper.Undo_DoUndo2(0)
    if res ~= 0 then
      state.check_reaper_undo_sync(actions)
      return true
    end
  end
  return false
end

-- Perform REAPER Native Redo (Ctrl+Shift+Z / Ctrl+Y)
function state.redo(actions)
  if not actions then
    local ok_act, act_mod = pcall(require, 'actions')
    if ok_act then actions = act_mod end
  end
  if actions and actions.timeline_sync then
    actions.timeline_sync.drag_active = false
    actions.timeline_sync.suppress_until = (reaper.time_precise and reaper.time_precise() or os.clock()) + 0.4
  end
  if reaper and reaper.Undo_DoRedo2 then
    local res = reaper.Undo_DoRedo2(0)
    if res ~= 0 then
      state.check_reaper_undo_sync(actions)
      return true
    end
  end
  return false
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
  local def_col_tbl = state.default_region_color or { state.get_default_region_color() }
  local full_pal = colors.generate_actor_palette(state.actors, def_col_tbl)
  for _, a in ipairs(state.actors) do
    if not state.actor_palette[a] then
      state.actor_palette[a] = full_pal[a]
    end
  end
end

-- Invalidate cached layout or virtual calculations
function state.invalidate_virtual_cache()
  state.row_heights = {}
  state._virtual_cache = nil
end

-- Update subtitle at index (Undoable - disabled in focus mode)
function state.update_subtitle(idx, new_sub)
  if state.focus_mode then return false end
  if state.subtitles[idx] then
    local old_snap = state.capture_snapshot("Изменить строку #" .. idx)
    if new_sub.text then
      new_sub.text = parser.strip_invisible_unicode(new_sub.text)
    end
    new_sub.single_line = nil
    new_sub.char_cnt = nil
    new_sub.cps = nil
    state.subtitles[idx] = new_sub
    if state.invalidate_virtual_cache then
      state.invalidate_virtual_cache()
    end
    state.row_heights = {}
    state.refresh_actors_from_subtitles()
    state.push_undo("Изменить строку #" .. idx, old_snap)
    state.save_to_project()
  end
end

-- Delete subtitle at index (Undoable with Delta - disabled in focus mode)
-- jump_to_next: if true (Ctrl+Delete), jumps playback timing position to next subtitle
--               if false/nil (regular Delete), leaves playback timing unchanged and naturally centers next subtitle
function state.delete_subtitle(idx, jump_to_next)
  if state.focus_mode then return false end

  local now_p = (reaper and reaper.time_precise and reaper.time_precise()) or os.clock()
  if state._last_delete_call_time and (now_p - state._last_delete_call_time) < 0.20 then
    return false
  end
  state._last_delete_call_time = now_p

  if state.subtitles[idx] then
    local old_snap = state.capture_snapshot and state.capture_snapshot("Удалить строку #" .. idx)
    local sub_to_delete = state.subtitles[idx]
    local del_start = sub_to_delete.start_time
    local del_end = sub_to_delete.end_time
    local delta = { type = "delete", idx = idx, sub = sub_to_delete }

    local filtered_before = state.get_filtered_subtitles()
    local del_filtered_idx = nil
    for fi, fs in ipairs(filtered_before) do
      if fs == sub_to_delete then
        del_filtered_idx = fi
        break
      end
    end

    table.remove(state.subtitles, idx)

    -- Remove row height of deleted subtitle and shift subsequent cached heights down by 1
    if state.row_heights and del_filtered_idx then
      local new_rh = {}
      for k, v in pairs(state.row_heights) do
        if type(k) == "number" then
          if k < del_filtered_idx then
            new_rh[k] = v
          elseif k > del_filtered_idx then
            new_rh[k - 1] = v
          end
        end
      end
      state.row_heights = new_rh
    else
      state.row_heights = {}
    end

    local total_subs = #state.subtitles
    if total_subs > 0 then
      -- Next subtitle now occupies index `idx` (or last index if deleted sub was the final one)
      local target_real_idx = math.min(idx, total_subs)
      local next_sub = state.subtitles[target_real_idx]

      local filtered = state.get_filtered_subtitles()
      local target_filtered_idx = 1
      for fi, fs in ipairs(filtered) do
        if fs == next_sub then
          target_filtered_idx = fi
          break
        end
      end

      if jump_to_next then
        -- Ctrl+Delete: Jump playback timing position in REAPER to next subtitle
        state.user_selected_row_idx = target_real_idx
        state.selected_real_sub_idx = target_real_idx
        state.active_sub_idx = target_filtered_idx
        state.last_centered_idx = -1
        state.need_calc_scroll_target = true
        state.suppress_autoscroll_until = 0
        state.scroll_target_y = nil

        local is_playing = reaper and reaper.GetPlayState and ((reaper.GetPlayState() & 1) ~= 0)
        if not is_playing and next_sub and next_sub.start_time then
          local ok_act, actions = pcall(require, 'actions')
          if ok_act and actions and actions.jump_to_time then
            actions.jump_to_time(next_sub.start_time)
          end
        end
      else
        -- Regular Delete: Do NOT jump playback timing position!
        -- Cursor position remains untouched; clear user selection so next row must be clicked before deleting again
        state.user_selected_row_idx = nil
        state.selected_real_sub_idx = nil
        state.active_sub_idx = target_filtered_idx
        state.last_centered_idx = -1
        state.need_calc_scroll_target = true
        state.suppress_autoscroll_until = 0
        state.scroll_target_y = nil
      end
    else
      state.active_sub_idx = nil
      state.user_selected_row_idx = nil
      state.selected_real_sub_idx = nil
      state.need_calc_scroll_target = false
      state.scroll_target_y = 0.0
    end
    state.last_centered_idx = -1

    if state.actor_counts and sub_to_delete.actor then
      state.actor_counts[sub_to_delete.actor] = math.max(0, (state.actor_counts[sub_to_delete.actor] or 1) - 1)
    else
      state.refresh_actors_from_subtitles()
    end

    local ok_act, actions = pcall(require, 'actions')
    local on_commit = function()
      if ok_act and actions and actions.delete_single_timeline_item then
        actions.delete_single_timeline_item(state, idx)
      end
    end
    state.push_undo("Удалить строку #" .. idx, old_snap, on_commit, delta)
    state.mark_save_to_project_dirty(0.4)
  end
end

function state.delete_subtitle_with_undo(idx, jump_to_next)
  if state.focus_mode then return false end
  state.delete_subtitle(idx, jump_to_next)
end

-- Insert new subtitle into state.subtitles in chronological order (Undoable)
function state.add_subtitle_with_undo(start_time, end_time, raw_actor, text, skip_undo)
  if not start_time or not end_time then return nil end
  if end_time < start_time then
    start_time, end_time = end_time, start_time
  end
  if end_time - start_time < 0.05 then
    end_time = start_time + 1.0
  end

  raw_actor = (raw_actor and #raw_actor > 0) and raw_actor or "NoActor"
  text = text or ""
  local actors, character, display_actor = parser.parse_actor_and_character(raw_actor)

  local new_sub = {
    start_time = start_time,
    end_time = end_time,
    actor = display_actor,
    raw_actor = raw_actor,
    actors = actors,
    character = character,
    text = parser.strip_invisible_unicode(text)
  }

  local old_snap = state.capture_snapshot and state.capture_snapshot("До создания субтитра")

  -- Fast binary search for chronological insertion position O(log N)
  local low = 1
  local high = #state.subtitles
  local insert_idx = #state.subtitles + 1
  while low <= high do
    local mid = (low + high) // 2
    if state.subtitles[mid].start_time > start_time then
      insert_idx = mid
      high = mid - 1
    else
      low = mid + 1
    end
  end

  table.insert(state.subtitles, insert_idx, new_sub)

  -- Shift cached row heights for subsequent rows without wiping measurements
  if state.row_heights then
    local new_rh = {}
    for k, v in pairs(state.row_heights) do
      if type(k) == "number" then
        if k < insert_idx then
          new_rh[k] = v
        else
          new_rh[k + 1] = v
        end
      end
    end
    new_rh[insert_idx] = 32.0
    state.row_heights = new_rh
  end

  -- Keep user selection and active sub pointing to the same sub without jumping scroll
  if state.user_selected_row_idx and state.user_selected_row_idx >= insert_idx then
    state.user_selected_row_idx = state.user_selected_row_idx + 1
  end
  if state.selected_real_sub_idx and state.selected_real_sub_idx >= insert_idx then
    state.selected_real_sub_idx = state.selected_real_sub_idx + 1
  end
  if state.active_sub_idx and state.active_sub_idx >= insert_idx then
    state.active_sub_idx = state.active_sub_idx + 1
  end

  -- Incremental actor registration (avoids full O(N) scan of 3500+ subs)
  if not state.actor_counts or not state.actors then
    state.refresh_actors_from_subtitles()
  else
    local a_name = display_actor or "NoActor"
    state.actor_counts[a_name] = (state.actor_counts[a_name] or 0) + 1
    if not state.actors_set or not state.actors_set[a_name] then
      state.refresh_actors_from_subtitles()
    end
  end

  state.prepare_sub_props(new_sub)
  if not skip_undo then
    local ok_act, actions = pcall(require, 'actions')
    local on_commit = function()
      if ok_act and actions and actions.add_single_timeline_item then
        actions.add_single_timeline_item(state, insert_idx)
      end
    end
    local delta = { type = "insert", idx = insert_idx, sub = new_sub }
    state.push_undo("Создать субтитр #" .. insert_idx, old_snap, on_commit, delta)
  end
  state.mark_save_to_project_dirty(0.4)

  return insert_idx, new_sub
end

-- Change actor for a single subtitle line (Undoable - disabled in focus mode)
function state.change_subtitle_actor_with_undo(idx, new_actor)
  if state.focus_mode then return false end
  local sub = state.subtitles[idx]
  if not sub then return false end

  new_actor = (new_actor and #new_actor > 0) and new_actor or "NoActor"
  local old_actor = sub.raw_actor or sub.actor or "NoActor"
  if old_actor == new_actor then return false end

  local old_snap = state.capture_snapshot("Изменить актера строки #" .. idx)

  local actors, character, display_actor = parser.parse_actor_and_character(new_actor)
  sub.raw_actor = new_actor
  sub.actor = display_actor
  sub.actors = actors
  sub.character = character

  state.row_heights = {}
  state.refresh_actors_from_subtitles()
  state.refresh_filter_set()
  state.push_undo("Изменить актера строки #" .. idx .. " (" .. old_actor .. " -> " .. new_actor .. ")", old_snap)
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

  local old_snap = state.capture_snapshot(string.format("Переименовать актера %s -> %s", old_name, new_name))

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
  state.push_undo(string.format("Переименовать актера %s -> %s", old_name, new_name), old_snap)
  state.save_to_project()
  return true
end

-- Merge source_actor into target_actor across all subtitle occurrences (Undoable)
-- Reassigns all lines of source_actor to target_actor, removes source_actor, preserves target_actor's color
function state.merge_actors_with_undo(source_actor, target_actor)
  if not source_actor or not target_actor or source_actor == "" or target_actor == "" or source_actor == target_actor then
    return false
  end

  local old_snap = state.capture_snapshot(string.format("Объединить актера %s с %s", source_actor, target_actor))

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
  state.push_undo(string.format("Объединить актера %s с %s", source_actor, target_actor), old_snap)
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
    show_actor_in_row = state.show_actor_in_row,
    text_actor_display_mode = state.text_actor_display_mode,
    text_tint_lines = state.text_tint_lines,
    text_custom_color = state.text_custom_color,
    text_tint_actor_names = state.text_tint_actor_names,
    hotkey_create_sub = state.hotkey_create_sub,
    -- Text & Typography settings
    text_font_family = state.text_font_family,
    text_font_size = state.text_font_size,
    scroll_center_ratio = state.scroll_center_ratio,
    text_active_larger = state.text_active_larger,
    text_active_font_scale = state.text_active_font_scale,
    text_active_spacing = state.text_active_spacing,
    text_active_spacing_px = state.text_active_spacing_px,
    text_highlight_brightness = state.text_highlight_brightness,
    text_fixed_lead_in = state.text_fixed_lead_in,
    text_lead_in_time = state.text_lead_in_time,
    smooth_scroll_enabled = state.smooth_scroll_enabled,
    smooth_scroll_speed = state.smooth_scroll_speed,
    row_alternating_bg = state.row_alternating_bg,
    row_alternating_strength = state.row_alternating_strength,
    text_preview_collapsed = state.text_preview_collapsed,
    -- View mode settings
    view_mode = state.view_mode,
    note_auto_wrap = state.note_auto_wrap,
    note_min_font_size = state.note_min_font_size,
    note_max_font_size = state.note_max_font_size,
    note_show_actor = state.note_show_actor,
    note_show_progress = state.note_show_progress,
    note_edit_font_size = state.note_edit_font_size,
    -- General & Accent settings
    accent_color = state.accent_color,
    parse_srt_actors = state.parse_srt_actors,
    intercept_reaper_file_drop = state.intercept_reaper_file_drop,
    default_region_color = state.default_region_color,
    control_box_palette = state.control_box_palette,
    watermark_style = state.watermark_style,
    regions_enabled = (state.regions_enabled ~= false),
    -- Overlay settings
    overlay_enabled = state.overlay_enabled,
    timer_overlay_enabled = state.timer_overlay_enabled,
    timer_overlay_font_family = state.timer_overlay_font_family,
    timer_overlay_format = state.timer_overlay_format,
    timer_overlay_color_mode = state.timer_overlay_color_mode,
    timer_custom_color = state.timer_custom_color,
    timer_overlay_bg_alpha = state.timer_overlay_bg_alpha,
    timer_overlay_bg_color = state.timer_overlay_bg_color,
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
    overlay_hide_progress = state.overlay_hide_progress,
    overlay_show_all_actors = state.overlay_show_all_actors,
    overlay_tint_lines = state.overlay_tint_lines,
    overlay_tint_only_filtered = state.overlay_tint_only_filtered,
    text_show_cps = state.text_show_cps,
    text_sync_overlay_hold = state.text_sync_overlay_hold,
    overlay_hold_mode = state.overlay_hold_mode,
    overlay_target_cps = state.overlay_target_cps,
    overlay_max_hold = state.overlay_max_hold,
    overlay_max_drift = state.overlay_max_drift,
    overlay_show_drift_badge = state.overlay_show_drift_badge,
    -- Optimization settings
    timeline_streaming_enabled = state.timeline_streaming_enabled,
    timeline_streaming_radius_min = state.timeline_streaming_radius_min,
    timeline_streaming_min_subs = state.timeline_streaming_min_subs,
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
  if s.show_actor_in_row ~= nil then state.show_actor_in_row = s.show_actor_in_row end
  if s.text_actor_display_mode ~= nil then state.text_actor_display_mode = s.text_actor_display_mode end
  if s.text_tint_lines ~= nil then state.text_tint_lines = s.text_tint_lines end
  if s.text_custom_color ~= nil then state.text_custom_color = s.text_custom_color end
  if s.text_tint_actor_names ~= nil then state.text_tint_actor_names = s.text_tint_actor_names end
  if s.hotkey_create_sub ~= nil then
    if s.hotkey_create_sub == "Shift+T" or s.hotkey_create_sub == "T" then
      state.hotkey_create_sub = s.hotkey_create_sub
    else
      state.hotkey_create_sub = "Shift+T"
    end
  end

  if s.timeline_streaming_enabled ~= nil then state.timeline_streaming_enabled = s.timeline_streaming_enabled end
  if s.timeline_streaming_radius_min ~= nil then state.timeline_streaming_radius_min = s.timeline_streaming_radius_min end
  if s.timeline_streaming_min_subs ~= nil then state.timeline_streaming_min_subs = s.timeline_streaming_min_subs end

  if s.text_font_family ~= nil then state.text_font_family = s.text_font_family end
  if s.text_font_size ~= nil then state.text_font_size = s.text_font_size end
  if s.scroll_center_ratio ~= nil then state.scroll_center_ratio = s.scroll_center_ratio end
  if s.text_active_larger ~= nil then state.text_active_larger = s.text_active_larger end
  if s.text_active_font_scale ~= nil then state.text_active_font_scale = s.text_active_font_scale end
  if s.text_active_spacing ~= nil then state.text_active_spacing = s.text_active_spacing end
  if s.text_active_spacing_px ~= nil then state.text_active_spacing_px = s.text_active_spacing_px end
  if s.text_highlight_brightness ~= nil then state.text_highlight_brightness = s.text_highlight_brightness end
  if s.text_fixed_lead_in ~= nil then state.text_fixed_lead_in = s.text_fixed_lead_in end
  if s.text_lead_in_time ~= nil then state.text_lead_in_time = s.text_lead_in_time end
  if s.smooth_scroll_enabled ~= nil then state.smooth_scroll_enabled = s.smooth_scroll_enabled end
  if s.smooth_scroll_speed ~= nil then state.smooth_scroll_speed = s.smooth_scroll_speed end
  if s.row_alternating_bg ~= nil then state.row_alternating_bg = s.row_alternating_bg end
  if s.row_alternating_strength ~= nil then state.row_alternating_strength = s.row_alternating_strength end
  if s.text_preview_collapsed ~= nil then state.text_preview_collapsed = s.text_preview_collapsed end
  if s.view_mode ~= nil then state.view_mode = s.view_mode end
  if s.note_auto_wrap ~= nil then state.note_auto_wrap = s.note_auto_wrap end
  if s.note_min_font_size ~= nil then state.note_min_font_size = s.note_min_font_size end
  if s.note_max_font_size ~= nil then state.note_max_font_size = s.note_max_font_size end
  if s.note_show_actor ~= nil then state.note_show_actor = s.note_show_actor end
  if s.note_show_progress ~= nil then state.note_show_progress = s.note_show_progress end
  if s.note_edit_font_size ~= nil then state.note_edit_font_size = s.note_edit_font_size end
  if s.parse_srt_actors ~= nil then
    state.parse_srt_actors = s.parse_srt_actors
  elseif s.smart_srt_actors ~= nil then
    state.parse_srt_actors = s.smart_srt_actors
  else
    state.parse_srt_actors = true
  end
  if s.intercept_reaper_file_drop ~= nil then
    state.intercept_reaper_file_drop = s.intercept_reaper_file_drop
  else
    state.intercept_reaper_file_drop = true
  end
  if s.accent_color then state.accent_color = s.accent_color end
  if s.default_region_color ~= nil then state.default_region_color = s.default_region_color end
  if s.control_box_palette ~= nil then state.control_box_palette = s.control_box_palette end
  if s.watermark_style ~= nil then state.watermark_style = s.watermark_style end
  if s.regions_enabled ~= nil then state.regions_enabled = s.regions_enabled end

  if s.overlay_enabled ~= nil then state.overlay_enabled = s.overlay_enabled end
  if s.timer_overlay_enabled ~= nil then state.timer_overlay_enabled = s.timer_overlay_enabled end
  if s.timer_overlay_font_family then state.timer_overlay_font_family = s.timer_overlay_font_family end
  if s.timer_overlay_format ~= nil then state.timer_overlay_format = s.timer_overlay_format end
  if s.timer_overlay_color_mode ~= nil then state.timer_overlay_color_mode = s.timer_overlay_color_mode end
  if s.timer_custom_color then state.timer_custom_color = s.timer_custom_color end
  if s.timer_overlay_bg_alpha ~= nil then state.timer_overlay_bg_alpha = s.timer_overlay_bg_alpha end
  if s.timer_overlay_bg_color then state.timer_overlay_bg_color = s.timer_overlay_bg_color end
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
  if s.overlay_hide_progress ~= nil then state.overlay_hide_progress = s.overlay_hide_progress end
  if s.overlay_show_all_actors ~= nil then state.overlay_show_all_actors = s.overlay_show_all_actors end
  if s.overlay_tint_lines ~= nil then state.overlay_tint_lines = s.overlay_tint_lines end
  if s.overlay_tint_only_filtered ~= nil then state.overlay_tint_only_filtered = s.overlay_tint_only_filtered end
  if s.text_show_cps ~= nil then state.text_show_cps = s.text_show_cps end
  if s.text_sync_overlay_hold ~= nil then state.text_sync_overlay_hold = s.text_sync_overlay_hold else state.text_sync_overlay_hold = true end
  if s.overlay_hold_mode ~= nil then state.overlay_hold_mode = s.overlay_hold_mode end
  if s.overlay_target_cps ~= nil then state.overlay_target_cps = s.overlay_target_cps end
  if s.overlay_max_hold ~= nil then state.overlay_max_hold = s.overlay_max_hold end
  if s.overlay_max_drift ~= nil then state.overlay_max_drift = s.overlay_max_drift end
  if s.overlay_show_drift_badge ~= nil then state.overlay_show_drift_badge = s.overlay_show_drift_badge end

  if s.ui_font_size ~= nil then state.ui_font_size = s.ui_font_size end
  if s.tooltip_font_size ~= nil then state.tooltip_font_size = s.tooltip_font_size end
  if s.popup_font_size ~= nil then state.popup_font_size = s.popup_font_size end
end

-- Validate if a ReaProject pointer is currently open and alive in REAPER
function state.is_project_valid(target_proj)
  if not reaper or not reaper.EnumProjects or not target_proj or target_proj == 0 then return false end
  local i = 0
  while true do
    local p = reaper.EnumProjects(i)
    if not p then break end
    if p == target_proj then return true end
    i = i + 1
  end
  return false
end

-- Save settings both to reaper-extstate.ini (globally across sessions) and to project
function state.save_settings(target_proj)
  local cur_proj = (reaper and reaper.EnumProjects and reaper.EnumProjects(-1))
  local proj = target_proj or cur_proj
  local settings = state.get_settings_table()
  local encoded = json.encode(settings)
  if reaper then
    if reaper.SetExtState then
      pcall(reaper.SetExtState, EXT_SECTION, "GLOBAL_SETTINGS", encoded, true)
    end
    if reaper.SetProjExtState and proj and state.is_project_valid(proj) then
      pcall(reaper.SetProjExtState, proj, EXT_SECTION, "SETTINGS", encoded)
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
function state.save_to_project(target_proj)
  if not reaper or not reaper.SetProjExtState then return false end
  local cur_proj = (reaper.EnumProjects and reaper.EnumProjects(-1))
  local proj = target_proj or cur_proj
  if not proj or not state.is_project_valid(proj) then return false end

  -- Safety guard: never save if project has no subtitles and no file was ever loaded
  if not state.subtitles and not state.filename and not state.filepath then
    return false
  end

  local meta = {
    filename = state.filename,
    filepath = state.filepath,
    format = state.format,
    count = state.subtitles and #state.subtitles or 0
  }
  pcall(reaper.SetProjExtState, proj, EXT_SECTION, "META", json.encode(meta))

  -- Subtitles
  pcall(reaper.SetProjExtState, proj, EXT_SECTION, "SUBTITLES", json.encode(state.subtitles or {}))

  -- Actors & Palette
  local actors_save = {
    actors = state.actors or {},
    actor_counts = state.actor_counts or {},
    actor_palette = state.actor_palette or {}
  }
  pcall(reaper.SetProjExtState, proj, EXT_SECTION, "ACTORS", json.encode(actors_save))

  -- Persist actor filter for this project
  pcall(reaper.SetProjExtState, proj, EXT_SECTION, "FILTER_ACTORS", json.encode(state.selected_actors or {}))

  -- Persist settings globally and in project
  state.save_settings(proj)

  -- Mark REAPER project dirty so Ctrl+S / save prompt includes plugin state changes
  if reaper.MarkProjectDirty then
    pcall(reaper.MarkProjectDirty, proj)
  end
  return true
end

-- Load state from REAPER active project
function state.load_from_project(target_proj)
  -- Always restore global settings first so user preferences are intact
  state.load_global_settings()

  if not reaper or not reaper.GetProjExtState then return false end
  local cur_proj = (reaper.EnumProjects and reaper.EnumProjects(-1))
  local proj = target_proj or cur_proj
  if not proj or not state.is_project_valid(proj) then return false end

  local meta_str
  local p_ok, _, res = pcall(reaper.GetProjExtState, proj, EXT_SECTION, "META")
  if p_ok then meta_str = res end
  local sec_to_use = EXT_SECTION
  if not meta_str or #meta_str == 0 then
    -- Fallback to legacy project state
    local leg_ok, _, leg_res = pcall(reaper.GetProjExtState, proj, LEGACY_EXT_SECTION, "META")
    if leg_ok and leg_res and #leg_res > 0 then
      meta_str = leg_res
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

  local subs_str
  local s_ok, _, s_res = pcall(reaper.GetProjExtState, proj, sec_to_use, "SUBTITLES")
  if s_ok then subs_str = s_res end
  if subs_str and #subs_str > 0 then
    state.subtitles = json.decode(subs_str) or {}
    if #state.subtitles > 1 and parser and parser.sort_subtitles then
      parser.sort_subtitles(state.subtitles)
    end
    if state.subtitles then
      for _, sub in ipairs(state.subtitles) do
        state.prepare_sub_props(sub)
      end
    end
  else
    state.subtitles = {}
  end

  local actors_str
  local a_ok, _, a_res = pcall(reaper.GetProjExtState, proj, sec_to_use, "ACTORS")
  if a_ok then actors_str = a_res end
  if actors_str and #actors_str > 0 then
    local actors_data = json.decode(actors_str)
    if actors_data then
      state.actors = actors_data.actors or {}
      state.actor_counts = actors_data.actor_counts or {}
      state.actor_palette = actors_data.actor_palette or {}
    end
  end

  -- Load per-project actor filter
  local filter_actors_str
  local f_ok, _, f_res = pcall(reaper.GetProjExtState, proj, sec_to_use, "FILTER_ACTORS")
  if f_ok then filter_actors_str = f_res end
  if filter_actors_str and #filter_actors_str > 0 then
    state.selected_actors = json.decode(filter_actors_str) or {}
  else
    local set_ok, _, set_res = pcall(reaper.GetProjExtState, proj, EXT_SECTION, "SETTINGS")
    if set_ok and set_res and #set_res > 0 then
      local s = json.decode(set_res)
      if s and s.selected_actors then
        state.selected_actors = s.selected_actors
      end
    end
  end

  state.refresh_filter_set()
  state.init_undo_tracking()
  return true
end

-- Load from a file path (Undoable)
-- Helper to lazily prepare a subtitle's single_line, char_cnt, and cps properties
function state.prepare_sub_props(s)
  if not s then return end
  if parser and parser.prepare_sub_props then
    return parser.prepare_sub_props(s)
  end
  s.single_line = (s.text or ""):gsub("[\r\n]+", " ")
  s.char_cnt = (parser and parser.utf8_len and parser.utf8_len(s.single_line)) or (utf8 and utf8.len and utf8.len(s.single_line)) or #s.single_line
  local dur = math.max(0.001, (s.end_time or 0) - (s.start_time or 0))
  s.cps = s.char_cnt / dur
end

-- Debounced project state saver to prevent UI freezes when adding or deleting subtitles
function state.mark_save_to_project_dirty(delay_sec)
  delay_sec = delay_sec or 0.5
  local now_t = (reaper and reaper.time_precise and reaper.time_precise()) or os.clock()
  state._save_project_pending_until = now_t + delay_sec
  state._save_project_target_proj = state.last_proj or 0
end

function state.check_pending_save()
  if state._save_project_pending_until then
    local now_t = (reaper and reaper.time_precise and reaper.time_precise()) or os.clock()
    if now_t >= state._save_project_pending_until then
      local target = state._save_project_target_proj
      state._save_project_pending_until = nil
      state._save_project_target_proj = nil
      if target and state.is_project_valid(target) then
        state.save_to_project(target)
      end
    end
  end
end

function state.load_file(filepath)
  local res = parser.parse_file(filepath, { parse_srt_actors = (state.parse_srt_actors ~= false) })
  if not res or not res.ok then
    return false, res and res.error or "Unknown parse error"
  end

  local old_snap = state.capture_snapshot and state.capture_snapshot("Загрузить файл " .. (res.filename or "субтитров"))

  state.undo_stack = {}
  state.filepath = filepath
  state.filename = res.filename
  state.format = res.format
  state.subtitles = res.subtitles
  if state.subtitles then
    for _, sub in ipairs(state.subtitles) do
      state.prepare_sub_props(sub)
    end
  end
  state.actors = res.actors
  state.actor_counts = res.actor_counts

  -- Generate default pastel palette for actors
  state.actor_palette = colors.generate_actor_palette(state.actors, state.default_region_color or { state.get_default_region_color() })

  -- Reset filter selection and runtime active state
  state.selected_actors = {}
  state.refresh_filter_set()
  state.active_sub_idx = nil
  state.row_heights = {}

  -- Push native undo point for loading the file (timeline sync is committed inside the undo block!)
  if state.push_undo then
    local on_commit = function()
      local ok_act, actions = pcall(require, 'actions')
      if ok_act and actions and actions.sync_filter_to_timeline then
        actions.sync_filter_to_timeline(state)
      end
    end
    state.push_undo("Загрузить файл " .. (res.filename or "субтитров"), old_snap, on_commit)
  end

  -- Save to current project
  state.save_to_project()

  local actions_ok, actions = pcall(require, 'actions')
  if actions_ok and actions and actions.init_timeline_sync then
    actions.init_timeline_sync(state)
  end

  return true
end

-- Detect if active project changed (e.g. project tab switch or Recent/Open project in current tab)
function state.check_project_changed(actions)
  if not reaper or not reaper.EnumProjects then return false end
  local cur_proj, cur_projfn = reaper.EnumProjects(-1)
  if not cur_proj then return false end

  -- First run initialization
  if state.last_proj == nil then
    state.last_proj = cur_proj
    state.last_projfn = cur_projfn
    state.last_proj_key = tostring(cur_proj)
    state._projects_cache = state._projects_cache or {}
    return false
  end

  -- If same project pointer, check if project was replaced in same tab (File -> Open / Recent)
  if cur_proj == state.last_proj then
    if cur_projfn ~= state.last_projfn then
      local was_opened_file = (state.last_projfn and #state.last_projfn > 0)
      state.last_projfn = cur_projfn
      if was_opened_file and cur_projfn and #cur_projfn > 0 then
        -- User opened a different project file in the same tab: reload project subtitles & reset sync
        state.load_from_project(cur_proj)
        state.undo_history = {}
        state.current_step_id = nil
        state.next_step_id = nil
        state.init_undo_tracking()
        if actions and actions.timeline_sync then
          actions.timeline_sync.streaming_center = nil
          if actions.init_timeline_sync then actions.init_timeline_sync(state) end
          if actions.sync_filter_to_timeline then actions.sync_filter_to_timeline(state) end
        end
        return true
      end
    end
    return false
  end

  -- REAL TAB SWITCH DETECTED:
  local prev_proj = state.last_proj
  local prev_key = state.last_proj_key or tostring(prev_proj)
  local prev_is_alive = state.is_project_valid(prev_proj)

  if prev_is_alive then
    -- 1. Flush any pending save for previous project immediately to prev_proj
    if state._save_project_pending_until then
      state._save_project_pending_until = nil
      state._save_project_target_proj = nil
      state.save_to_project(prev_proj)
    elseif state.subtitles and #state.subtitles > 0 then
      state.save_to_project(prev_proj)
    end

    -- 2. Cache in-memory working state of previous project tab
    state._projects_cache = state._projects_cache or {}
    state._projects_cache[prev_key] = {
      _proj_ptr = prev_proj,
      subtitles = state.subtitles,
      filepath = state.filepath,
      filename = state.filename,
      format = state.format,
      actors = state.actors,
      actor_counts = state.actor_counts,
      actor_palette = state.actor_palette,
      selected_actors = state.selected_actors,
      undo_history = state.undo_history,
      current_step_id = state.current_step_id,
      next_step_id = state.next_step_id,
      active_sub_idx = state.active_sub_idx,
    }
  else
    -- Previous project tab was CLOSED (not just switched away from)!
    state._save_project_pending_until = nil
    state._save_project_target_proj = nil

    -- Clean up cache entry for the closed project
    if state._projects_cache then
      state._projects_cache[prev_key] = nil
    end
  end

  -- Prune cache of any dead project pointers
  if state._projects_cache then
    for k, c in pairs(state._projects_cache) do
      if c._proj_ptr and not state.is_project_valid(c._proj_ptr) then
        state._projects_cache[k] = nil
      end
    end
  end

  -- 3. Reset timeline sync states so old project items/regions don't leak
  if not actions then
    local ok_act, act_mod = pcall(require, 'actions')
    if ok_act then actions = act_mod end
  end
  if actions and actions.timeline_sync then
    actions.timeline_sync.is_syncing = false
    actions.timeline_sync.drag_active = false
    actions.timeline_sync.sub_map = nil
    actions.timeline_sync.last_change_count = nil
    actions.timeline_sync.last_rgn_count = nil
    actions.timeline_sync.streaming_center = nil
  end

  -- 4. Switch active project pointers
  state.last_proj = cur_proj
  state.last_projfn = cur_projfn
  state.last_proj_key = tostring(cur_proj)

  -- 5. Restore target project state from memory cache or ProjExtState
  local cur_key = tostring(cur_proj)
  local cached = state._projects_cache[cur_key]
  if cached then
    state.subtitles = cached.subtitles or {}
    state.filepath = cached.filepath
    state.filename = cached.filename
    state.format = cached.format
    state.actors = cached.actors or {}
    state.actor_counts = cached.actor_counts or {}
    state.actor_palette = cached.actor_palette or {}
    state.selected_actors = cached.selected_actors or {}
    state.undo_history = cached.undo_history or {}
    state.current_step_id = cached.current_step_id
    state.next_step_id = cached.next_step_id
    state.active_sub_idx = cached.active_sub_idx
  else
    state.load_from_project(cur_proj)
    state.undo_history = {}
    state.current_step_id = nil
    state.next_step_id = nil
    state.init_undo_tracking()
  end

  -- 6. Reset UI layout caches
  state.row_heights = {}
  state.undo_stack = {}
  state.active_sub_idx = nil
  state.user_selected_row_idx = nil
  state.selected_real_sub_idx = nil
  state.need_calc_scroll_target = true
  state.refresh_actors_from_subtitles()
  state.refresh_filter_set()

  -- 7. Initialize timeline sync for newly activated project
  if actions then
    if actions.init_timeline_sync then
      actions.init_timeline_sync(state)
    end
    if actions.sync_filter_to_timeline then
      actions.sync_filter_to_timeline(state)
    end
  end

  return true
end

-- Initialize global settings on module load
state.load_global_settings()

return state
