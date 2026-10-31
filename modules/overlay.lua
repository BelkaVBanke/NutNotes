--[[
  Hardsub video overlay floating window module for REAPER Subtitle Plugin.
  Frameless, resizable, transparent black window displaying current active subtitle over video playback.

  Design & Stability:
  - Base font size determines default line height and reserved 2-line slot.
  - Short 1-line text is centered vertically and horizontally inside the 2-line slot.
  - Medium 2-line text fills both lines.
  - Very long text scales font down to fit into the 2 lines without growing slot height.
  - Slots have fixed height so the progress bar and next line preview NEVER jump or shift!
  - Teleprompter countdown bar in pauses is neutral grey; actor nickname is greyer with subtle actor tint.
  - Next subtitle actor is displayed on the left in the SAME line: [Actor] Text.
  - "Show all actors" toggle supported; actor name automatically hidden when single actor is filtered.
  - Uses native ImGui.Dummy() to reserve vertical space, ensuring zero assertion warnings.
]]

local parser = require('parser')
local actions = require('actions')
local watermark = require('watermark')

local overlay = {}
local overlay_font_cache = {}
local overlay_pending_fonts = {}
local timer_font_cache = {}
local is_overlay_frame_active = false
local last_timer_font_family = nil

function overlay.attach_font_now(ctx, ImGui, size)
  if not ImGui or not ImGui.CreateFont or not ImGui.Attach or not ctx then return nil end
  size = math.max(9, math.min(160, math.floor(size)))
  if overlay_font_cache[size] ~= nil then
    return overlay_font_cache[size]
  end

  local ok, f = pcall(ImGui.CreateFont, 'sans-serif', size, 0)
  if not (ok and f) then
    ok, f = pcall(ImGui.CreateFont, 'sans-serif', 0)
  end
  if ok and f then
    local a_ok = pcall(ImGui.Attach, ctx, f)
    if a_ok then
      overlay_font_cache[size] = f
      return f
    end
  end
  overlay_font_cache[size] = false
  return nil
end

local function get_timer_font(ctx, ImGui, family, size)
  family = family or "sans-serif"
  size = math.max(10, math.min(160, math.floor(size)))
  local key = family .. "_" .. tostring(size)
  if timer_font_cache[key] ~= nil then
    return timer_font_cache[key]
  end
  local ok, f = pcall(ImGui.CreateFont, family, size, 0)
  if not (ok and f) then
    ok, f = pcall(ImGui.CreateFont, "sans-serif", size, 0)
  end
  if ok and f then
    local a_ok = pcall(ImGui.Attach, ctx, f)
    if a_ok then
      timer_font_cache[key] = f
      return f
    end
  end
  timer_font_cache[key] = false
  return nil
end

local function find_closest_overlay_font(size)
  size = math.max(9, math.min(160, math.floor(size)))
  if overlay_font_cache[size] then return overlay_font_cache[size] end
  local best_f = nil
  local best_diff = 999
  -- First try font smaller than or equal to requested size
  for sz, f in pairs(overlay_font_cache) do
    if f and type(f) ~= "boolean" then
      local diff = size - sz
      if diff >= 0 and diff < best_diff then
        best_diff = diff
        best_f = f
      end
    end
  end
  if best_f then return best_f end

  for sz, f in pairs(overlay_font_cache) do
    if f and type(f) ~= "boolean" then
      local diff = math.abs(sz - size)
      if diff < best_diff then
        best_diff = diff
        best_f = f
      end
    end
  end
  return best_f
end

local function find_closest_timer_font(family, size)
  family = family or "Segoe UI"
  size = math.max(10, math.min(160, math.floor(size)))
  local key = family .. "_" .. tostring(size)
  if timer_font_cache[key] then return timer_font_cache[key] end

  local best_f = nil
  local best_diff = 999
  for k, f in pairs(timer_font_cache) do
    if f and type(f) ~= "boolean" then
      local fam, sz_str = k:match("^(.-)_(%d+)$")
      if fam == family and sz_str then
        local sz = tonumber(sz_str)
        local diff = size - sz
        if diff >= 0 and diff < best_diff then
          best_diff = diff
          best_f = f
        end
      end
    end
  end
  if best_f then return best_f end

  for k, f in pairs(timer_font_cache) do
    if f and type(f) ~= "boolean" then
      local fam, _ = k:match("^(.-)_(%d+)$")
      if fam == family then return f end
    end
  end

  return find_closest_overlay_font(size)
end

function overlay.init_fonts(ctx, state, ImGui)
  if not ImGui or not ImGui.CreateFont or not ImGui.Attach or not ctx then return end
  local common_sizes = { 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 36, 40, 44, 48, 52, 56, 60, 64, 72, 80, 88, 96, 112, 128, 144, 160 }
  if state and state.overlay_font_size then
    table.insert(common_sizes, math.floor(state.overlay_font_size))
  end
  for _, sz in ipairs(common_sizes) do
    overlay.attach_font_now(ctx, ImGui, sz)
  end

  local timer_fam = (state and state.timer_overlay_font_family) or "Segoe UI"
  last_timer_font_family = timer_fam
  local timer_sizes = { 14, 18, 22, 26, 30, 36, 42, 48, 54, 60, 68, 76, 84, 96, 110, 128, 144, 160 }
  for _, sz in ipairs(timer_sizes) do
    get_timer_font(ctx, ImGui, timer_fam, sz)
    if timer_fam ~= "sans-serif" then
      get_timer_font(ctx, ImGui, "sans-serif", sz)
    end
  end
end

function overlay.check_fonts(ctx, state, ImGui)
  if not ImGui or not ImGui.CreateFont or not ImGui.Attach or not ctx then return end
  for sz, _ in pairs(overlay_pending_fonts) do
    if overlay_font_cache[sz] == nil or overlay_font_cache[sz] == false then
      overlay.attach_font_now(ctx, ImGui, sz)
    end
  end
  overlay_pending_fonts = {}

  local cur_tfam = state and state.timer_overlay_font_family
  if cur_tfam and cur_tfam ~= last_timer_font_family then
    last_timer_font_family = cur_tfam
    local timer_sizes = { 14, 18, 22, 26, 30, 36, 42, 48, 54, 60, 68, 76, 84, 96, 110, 128, 144, 160 }
    for _, sz in ipairs(timer_sizes) do
      get_timer_font(ctx, ImGui, cur_tfam, sz)
    end
  end
end

local function get_overlay_font(ctx, ImGui, size)
  if not ImGui or not ImGui.CreateFont or not ImGui.Attach then return nil end
  size = math.max(9, math.min(160, math.floor(size)))
  if overlay_font_cache[size] then
    return overlay_font_cache[size]
  end

  if not is_overlay_frame_active then
    return overlay.attach_font_now(ctx, ImGui, size)
  end

  overlay_pending_fonts[size] = true
  return find_closest_overlay_font(size)
end

-- Helper to wrap text into lines respecting max_w with active font
local function wrap_text_lines(ctx, ImGui, text, max_w)
  if not text or #text == 0 then return { "" } end
  local clean = parser.strip_invisible_unicode(text)
  local paragraphs = {}
  for p in clean:gmatch("[^\r\n]+") do
    table.insert(paragraphs, p)
  end
  if #paragraphs == 0 then return { "" } end

  local lines = {}
  for _, para in ipairs(paragraphs) do
    local words = {}
    for w in para:gmatch("%S+") do
      table.insert(words, w)
    end
    if #words == 0 then
      table.insert(lines, "")
    else
      local cur_line = words[1]
      for i = 2, #words do
        local test_line = cur_line .. " " .. words[i]
        local tw, _ = ImGui.CalcTextSize(ctx, test_line)
        if tw <= max_w then
          cur_line = test_line
        else
          table.insert(lines, cur_line)
          cur_line = words[i]
        end
      end
      table.insert(lines, cur_line)
    end
  end
  return lines
end

-- Find font size where text wraps into <= max_lines and fits inside max_h
local function find_fitting_font_and_lines(ctx, ImGui, text, base_sz, max_w, max_lines, max_h)
  local chosen_sz = base_sz
  local chosen_lines = {}
  local chosen_line_h = 20.0

  for test_sz = base_sz, 10, -1 do
    local f = get_overlay_font(ctx, ImGui, test_sz)
    if f and ImGui.PushFont then
      ImGui.PushFont(ctx, f)
      local lines = wrap_text_lines(ctx, ImGui, text, max_w)
      local _, lh = ImGui.CalcTextSize(ctx, "Ay")
      local line_step = lh + 2.0
      local text_h = #lines * line_step
      ImGui.PopFont(ctx)

      if (#lines <= max_lines and text_h <= max_h) or (test_sz == 10) then
        chosen_sz = test_sz
        chosen_lines = lines
        chosen_line_h = line_step
        break
      end
      chosen_sz = test_sz
      chosen_lines = lines
      chosen_line_h = line_step
    end
  end

  return chosen_sz, chosen_lines, chosen_line_h
end

-- Live runtime tracking for real-time CPS delay and cascading shift (computed on the fly)
local live_trk = {
  was_playing = false,
  active_idx = nil,
  active_v_start = 0.0,
  active_v_end = 0.0,
  current_drift = 0.0,
  last_play_pos = 0.0,
}

local function bsearch_subs(subs, cur_time)
  local low, high = 1, #subs
  local ans = nil
  while low <= high do
    local mid = (low + high) // 2
    if subs[mid].start_time <= cur_time then
      ans = mid
      low = mid + 1
    else
      high = mid - 1
    end
  end
  return ans
end

-- Subtitle character count & CPS are computed via parser.get_sub_char_cnt / parser.get_sub_cps (Single Source of Truth)

function overlay.eval_active_sub(subs, cur_time, is_playing, hold_mode, target_cps, max_hold, max_drift, trk, lead_in, fixed_lead_in)
  if not subs or #subs == 0 then
    return nil, nil, nil, false, 0.0
  end

  trk = trk or live_trk
  hold_mode = hold_mode or 2
  target_cps = math.max(5.0, target_cps or 17.0)
  max_hold = math.max(0.1, max_hold or 1.5)
  max_drift = math.max(0.2, max_drift or 2.5)
  lead_in = lead_in or 0.0
  local is_fixed = (fixed_lead_in == true)

  -- When NOT playing (stopped / editing cursor positioning):
  -- Past drift has ZERO influence! Subtitle under cursor starts fresh.
  if not is_playing or hold_mode <= 1 then
    trk.was_playing = false
    trk.current_drift = 0.0
    trk.active_idx = nil

    local best = bsearch_subs(subs, cur_time)
    local playing_idx = nil
    local upcoming_idx = nil
    local prev_idx = nil

    if best then
      local sub = subs[best]
      if cur_time <= sub.end_time then
        playing_idx = best
        if best > 1 then prev_idx = best - 1 end
        if is_fixed and lead_in > 0 and best < #subs then
          local next_s = subs[best + 1]
          if cur_time >= (next_s.start_time - lead_in) then
            upcoming_idx = best + 1
          end
        end
      else
        prev_idx = best
        if best < #subs then
          local next_s = subs[best + 1]
          if (not is_fixed) or lead_in <= 0 or cur_time >= (next_s.start_time - lead_in) then
            upcoming_idx = best + 1
          end
        end
      end
    else
      if #subs > 0 then
        local first_s = subs[1]
        if (not is_fixed) or lead_in <= 0 or cur_time >= (first_s.start_time - lead_in) then
          upcoming_idx = 1
        end
      end
    end

    return playing_idx, upcoming_idx, prev_idx, false, 0.0
  end

  -- When PLAYING:
  -- Detect if playback just started or if user seeked (>0.5s jump in play position or backward jump)
  local seeked = false
  if trk.was_playing then
    if math.abs(cur_time - trk.last_play_pos) > 0.5 or (cur_time < trk.last_play_pos - 0.05) then
      seeked = true
    end
  else
    seeked = true
  end
  trk.last_play_pos = cur_time

  if seeked then
    trk.was_playing = true
    trk.current_drift = 0.0
    trk.active_idx = nil

    local best = bsearch_subs(subs, cur_time)
    if best then
      local sub = subs[best]
      -- Activate strictly if playback starts INSIDE physical subtitle boundaries!
      -- If started in a gap after sub.end_time, past subtitle must never be revived into overtime!
      if cur_time >= sub.start_time and cur_time <= sub.end_time then
        local char_cnt = parser.get_sub_char_cnt(sub)
        local dur = math.max(0.1, sub.end_time - sub.start_time)
        local extra = math.min(max_hold, math.max(0.0, (char_cnt / target_cps) - dur))
        if hold_mode == 2 then
          local next_s = subs[best + 1] and subs[best + 1].start_time or (sub.end_time + 10.0)
          extra = math.min(extra, math.max(0.0, next_s - sub.end_time))
        end
        local v_end = sub.end_time + extra
        trk.active_idx = best
        trk.active_v_start = sub.start_time
        trk.active_v_end = v_end
      end
    end
  end

  -- If currently tracking an active subtitle:
  if trk.active_idx and subs[trk.active_idx] then
    local sub = subs[trk.active_idx]
    if cur_time <= trk.active_v_end then
      local is_overtime = (cur_time > sub.end_time)
      local drift_val = is_overtime and (cur_time - sub.end_time) or trk.current_drift
      local up_i = nil
      if is_fixed and lead_in > 0 and trk.active_idx < #subs then
        local next_s = subs[trk.active_idx + 1]
        local next_start = (hold_mode == 3) and math.max(next_s.start_time, trk.active_v_end) or next_s.start_time
        if cur_time >= (next_start - lead_in) then
          up_i = trk.active_idx + 1
        end
      end
      return trk.active_idx, up_i, nil, is_overtime, drift_val
    else
      -- Active sub has finished its hold!
      local next_i = trk.active_idx + 1
      if next_i <= #subs then
        local next_s = subs[next_i]
        if hold_mode == 3 and cur_time >= next_s.start_time then
          -- Cascade into next sub with accumulated drift
          local drift = math.min(max_drift, math.max(0.0, trk.active_v_end - next_s.start_time))
          trk.active_idx = next_i
          trk.active_v_start = next_s.start_time + drift
          local char_cnt = parser.get_sub_char_cnt(next_s)
          local dur = math.max(0.1, next_s.end_time - next_s.start_time)
          local extra = math.min(max_hold, math.max(0.0, (char_cnt / target_cps) - dur))
          trk.active_v_end = trk.active_v_start + dur + extra
          trk.current_drift = drift
          local is_overtime = (cur_time > (next_s.end_time + drift))
          local cur_drift = is_overtime and (cur_time - (next_s.end_time + drift)) or drift
          local up_i = nil
          if is_fixed and lead_in > 0 and next_i < #subs then
            local after_s = subs[next_i + 1]
            local after_start = math.max(after_s.start_time, trk.active_v_end)
            if cur_time >= (after_start - lead_in) then
              up_i = next_i + 1
            end
          end
          return next_i, up_i, nil, is_overtime, cur_drift
        elseif cur_time >= next_s.start_time then
          -- Mode 2 (gaps only) or gap absorbed drift
          trk.active_idx = next_i
          trk.active_v_start = next_s.start_time
          trk.current_drift = 0.0
          local char_cnt = parser.get_sub_char_cnt(next_s)
          local dur = math.max(0.1, next_s.end_time - next_s.start_time)
          local extra = math.min(max_hold, math.max(0.0, (char_cnt / target_cps) - dur))
          if hold_mode == 2 then
            local after_s = subs[next_i + 1] and subs[next_i + 1].start_time or (next_s.end_time + 10.0)
            extra = math.min(extra, math.max(0.0, after_s - next_s.end_time))
          end
          trk.active_v_end = next_s.end_time + extra
          local is_overtime = (cur_time > next_s.end_time)
          local cur_drift = is_overtime and (cur_time - next_s.end_time) or 0.0
          local up_i = nil
          if is_fixed and lead_in > 0 and next_i < #subs then
            local after_s = subs[next_i + 1]
            if cur_time >= (after_s.start_time - lead_in) then
              up_i = next_i + 1
            end
          end
          return next_i, up_i, nil, is_overtime, cur_drift
        end
      end
      trk.active_idx = nil
      trk.current_drift = 0.0
    end
  end

  -- If not in an active sub, look up if currently in a sub or in a gap:
  local best = bsearch_subs(subs, cur_time)
  if best then
    local sub = subs[best]
    if cur_time <= sub.end_time then
      trk.active_idx = best
      trk.active_v_start = sub.start_time
      trk.current_drift = 0.0
      local char_cnt = parser.get_sub_char_cnt(sub)
      local dur = math.max(0.1, sub.end_time - sub.start_time)
      local extra = math.min(max_hold, math.max(0.0, (char_cnt / target_cps) - dur))
      if hold_mode == 2 then
        local next_s = subs[best + 1] and subs[best + 1].start_time or (sub.end_time + 10.0)
        extra = math.min(extra, math.max(0.0, next_s - sub.end_time))
      end
      trk.active_v_end = sub.end_time + extra
      local up_i = nil
      if is_fixed and lead_in > 0 and best < #subs then
        local next_s = subs[best + 1]
        local next_start = (hold_mode == 3) and math.max(next_s.start_time, trk.active_v_end) or next_s.start_time
        if cur_time >= (next_start - lead_in) then
          up_i = best + 1
        end
      end
      return best, up_i, nil, false, 0.0
    else
      local prev_idx = best
      local upcoming_idx = nil
      if best < #subs then
        local next_s = subs[best + 1]
        if (not is_fixed) or lead_in <= 0 or cur_time >= (next_s.start_time - lead_in) then
          upcoming_idx = best + 1
        end
      end
      return nil, upcoming_idx, prev_idx, false, 0.0
    end
  else
    local upcoming_idx = nil
    if #subs > 0 then
      local first_s = subs[1]
      if (not is_fixed) or lead_in <= 0 or cur_time >= (first_s.start_time - lead_in) then
        upcoming_idx = 1
      end
    end
    return nil, upcoming_idx, nil, false, 0.0
  end
end

function overlay.draw(ctx, state, ImGui)
  if not state.overlay_enabled then return end

  local flags = ImGui.WindowFlags_NoTitleBar
              | ImGui.WindowFlags_NoScrollbar
              | ImGui.WindowFlags_NoCollapse

  if ImGui.WindowFlags_NoDocking then
    flags = flags | ImGui.WindowFlags_NoDocking
  end

  if ImGui.WindowFlags_NoNavInputs then
    flags = flags | ImGui.WindowFlags_NoNavInputs
  end
  if ImGui.WindowFlags_NoNavFocus then
    flags = flags | ImGui.WindowFlags_NoNavFocus
  end
  if ImGui.WindowFlags_NoFocusOnAppearing then
    flags = flags | ImGui.WindowFlags_NoFocusOnAppearing
  end

  if state.overlay_always_on_top and ImGui.WindowFlags_TopMost then
    flags = flags | ImGui.WindowFlags_TopMost
  end

  -- Background color with custom alpha
  local bg_u32 = ImGui.ColorConvertDouble4ToU32(
    state.overlay_bg_color[1],
    state.overlay_bg_color[2],
    state.overlay_bg_color[3],
    state.overlay_bg_alpha
  )

  local tr = state.overlay_text_color[1] or 1.0
  local tg = state.overlay_text_color[2] or 1.0
  local tb = state.overlay_text_color[3] or 1.0
  local ta = state.overlay_text_color[4] or 1.0

  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, bg_u32)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowBorderSize, 0.0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 8.0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 14, 10)

  -- Initial default size if first time opened
  ImGui.SetNextWindowSize(ctx, 740, 130, ImGui.Cond_FirstUseEver)

  -- Ensure overlay is strictly a floating window, never docked into dockers or other windows
  if ImGui.SetNextWindowDockID then
    ImGui.SetNextWindowDockID(ctx, 0)
  end

  is_overlay_frame_active = true
  local visible, open = ImGui.Begin(ctx, "NutNotes (Хардсаб)###NUTNOTES_OVERLAY_WINDOW", true, flags)
  if not open then
    state.overlay_enabled = false
    state.save_settings()
  end

  if visible then
    local win_w, win_h = ImGui.GetWindowSize(ctx)
    local avail_w = math.max(120.0, win_w - 28.0)

    -- Get current playback / edit cursor position
    local cur_time = 0
    if reaper then
      cur_time = reaper.GetPlayState() == 0 and reaper.GetCursorPosition() or reaper.GetPlayPosition()
    end

    -- Subtitles source: all actors if overlay_show_all_actors is enabled, otherwise filtered
    local subs_to_use
    if state.overlay_show_all_actors then
      subs_to_use = state.subtitles
    else
      subs_to_use = state.get_filtered_subtitles()
    end

    -- Single-actor rule: If only 1 actor is filtered and "show all" is false, do NOT show actor name
    local is_single_actor_mode = (not state.overlay_show_all_actors and #state.selected_actors == 1)
    local show_actor_badge = state.overlay_show_actor and (not is_single_actor_mode)

    if subs_to_use and #subs_to_use > 0 then
      local is_reaper_playing = reaper and ((reaper.GetPlayState() & 1) ~= 0)
      local fixed_lead_in = (state.text_fixed_lead_in == true)
      local lead_in = fixed_lead_in and (state.text_lead_in_time or 0.35) or 0.0
      local playing_idx, upcoming_idx, prev_idx, is_overtime, current_drift = overlay.eval_active_sub(
        subs_to_use,
        cur_time,
        is_reaper_playing,
        state.overlay_hold_mode or 2,
        state.overlay_target_cps or 17.0,
        state.overlay_max_hold or 0.7,
        state.overlay_max_drift or 2.5,
        nil,
        lead_in,
        fixed_lead_in
      )

      local main_sub = nil
      local preview_sub = nil
      local is_gap = false
      local progress = 0.0

      if playing_idx then
        main_sub = subs_to_use[playing_idx]
        is_gap = false
        local dur = math.max(0.001, main_sub.end_time - main_sub.start_time)
        progress = math.min(1.0, math.max(0.0, (cur_time - main_sub.start_time) / dur))
        if state.overlay_show_next_preview then
          preview_sub = subs_to_use[playing_idx + 1]
        end
      elseif upcoming_idx then
        main_sub = subs_to_use[upcoming_idx]
        is_gap = true
        local prev_sub = prev_idx and subs_to_use[prev_idx]
        local prev_end = prev_sub and prev_sub.end_time or (main_sub.start_time - 5.0)
        local total_gap = math.max(0.2, main_sub.start_time - prev_end)
        local rem_time = math.max(0.0, main_sub.start_time - cur_time)

        if total_gap > 5.0 then
          progress = math.min(1.0, math.max(0.0, rem_time / 5.0))
        else
          progress = math.min(1.0, math.max(0.0, rem_time / total_gap))
        end

        if state.overlay_show_next_preview then
          preview_sub = subs_to_use[upcoming_idx + 1]
        end
      end

      if main_sub then
        local clean_main_text = parser.strip_invisible_unicode(main_sub.text)

        -- BASE FONT SIZE FROM USER SETTINGS
        local base_sz = math.max(12, math.floor(state.overlay_font_size or 24.0))
        local base_font = get_overlay_font(ctx, ImGui, base_sz)

        -- Measure base line height
        local base_line_step = 28.0
        if base_font and ImGui.PushFont then
          ImGui.PushFont(ctx, base_font)
          local _, lh = ImGui.CalcTextSize(ctx, "Ay")
          base_line_step = lh + 2.0
          ImGui.PopFont(ctx)
        end

        -- FIXED RESERVED HEIGHT FOR 2-LINE MAIN TEXT SLOT
        local main_slot_h = base_line_step * 2.0

        -- Calculate main text colors
        local is_main_own = (#state.selected_actors == 0) or state.is_actor_selected(main_sub.actor)
        local should_tint_main = state.overlay_tint_lines and (not state.overlay_tint_only_filtered or is_main_own)
        local cur_tr, cur_tg, cur_tb = tr, tg, tb
        if should_tint_main and main_sub.actor ~= "NoActor" and state.actor_palette[main_sub.actor] then
          local p = state.actor_palette[main_sub.actor]
          cur_tr = 0.35 + p.r * 0.65
          cur_tg = 0.35 + p.g * 0.65
          cur_tb = 0.35 + p.b * 0.65
        end

        local main_alpha = is_gap and (ta * 0.65) or ta
        local main_text_u32 = ImGui.ColorConvertDouble4ToU32(cur_tr, cur_tg, cur_tb, main_alpha)
        local main_shadow_u32 = ImGui.ColorConvertDouble4ToU32(0, 0, 0, main_alpha * 0.9)

        -- OVERTIME / DRIFT BADGE (+X.Xs in top-right corner)
        if state.overlay_show_drift_badge and (is_overtime or current_drift > 0.05) then
          local drift_val = current_drift > 0.05 and current_drift or (cur_time - main_sub.end_time)
          if drift_val > 0.05 then
            local drift_text = string.format("+%.1fs", drift_val)
            local badge_sz = math.max(10, math.floor((state.overlay_actor_font_size or 18.0) * 0.85))
            local badge_font = get_overlay_font(ctx, ImGui, badge_sz)
            local b_f_pushed = false
            if badge_font and ImGui.PushFont then
              ImGui.PushFont(ctx, badge_font)
              b_f_pushed = true
            end

            local bw, bh = ImGui.CalcTextSize(ctx, drift_text)
            local badge_x = win_w - bw - 18.0
            local badge_y = 6.0
            local dl = ImGui.GetWindowDrawList(ctx)
            local wx, wy = ImGui.GetWindowPos(ctx)
            local bx1 = wx + badge_x - 5.0
            local by1 = wy + badge_y - 2.0
            local bx2 = bx1 + bw + 10.0
            local by2 = by1 + bh + 4.0

            ImGui.DrawList_AddRectFilled(dl, bx1, by1, bx2, by2, 0x1A1E24EE, 4.0)
            ImGui.DrawList_AddRect(dl, bx1, by1, bx2, by2, 0xF59E0BAA, 4.0, 0, 1.0)
            ImGui.DrawList_AddText(dl, wx + badge_x, wy + badge_y, 0xF59E0BFF, drift_text)

            if b_f_pushed then
              ImGui.PopFont(ctx)
            end
          end
        end

        -- 1. MAIN ACTOR BADGE (Used when position is "top")
        local is_actor_top = (state.overlay_actor_position ~= "left")
        if is_actor_top and show_actor_badge and main_sub.actor ~= "NoActor" then
          local act_sz = math.max(10, math.floor(state.overlay_actor_font_size or 18.0))
          local act_font = get_overlay_font(ctx, ImGui, act_sz)
          local act_f_pushed = false
          if act_font and ImGui.PushFont then
            ImGui.PushFont(ctx, act_font)
            act_f_pushed = true
          end

          local pal = state.actor_palette[main_sub.actor]
          local actor_col_u32
          if is_gap then
            -- Pause/Countdown: Actor nickname is greyer, less prominent, but with subtle tint of actor color
            if pal then
              local grey_r = 0.52 + pal.r * 0.28
              local grey_g = 0.52 + pal.g * 0.28
              local grey_b = 0.52 + pal.b * 0.28
              actor_col_u32 = ImGui.ColorConvertDouble4ToU32(grey_r, grey_g, grey_b, 0.60)
            else
              actor_col_u32 = ImGui.ColorConvertDouble4ToU32(0.60, 0.60, 0.60, 0.60)
            end
          else
            -- Active speech: Full vibrant actor color
            if pal then
              actor_col_u32 = ImGui.ColorConvertDouble4ToU32(pal.r, pal.g, pal.b, 1.0)
            else
              actor_col_u32 = main_text_u32
            end
          end

          local actor_str = "[" .. main_sub.actor .. "]"
          local act_w, _ = ImGui.CalcTextSize(ctx, actor_str)
          local act_x = 14
          if state.overlay_align == 1 then
            act_x = math.max(12, (win_w - act_w) * 0.5)
          elseif state.overlay_align == 2 then
            act_x = math.max(12, win_w - act_w - 14)
          end

          local cur_y = ImGui.GetCursorPosY(ctx)
          -- Shadow
          ImGui.SetCursorPosX(ctx, act_x + 1.5)
          ImGui.SetCursorPosY(ctx, cur_y + 1.5)
          ImGui.PushStyleColor(ctx, ImGui.Col_Text, main_shadow_u32)
          ImGui.Text(ctx, actor_str)
          ImGui.PopStyleColor(ctx, 1)

          -- Main
          ImGui.SetCursorPosX(ctx, act_x)
          ImGui.SetCursorPosY(ctx, cur_y)
          ImGui.PushStyleColor(ctx, ImGui.Col_Text, actor_col_u32)
          ImGui.Text(ctx, actor_str)
          ImGui.PopStyleColor(ctx, 1)

          if act_f_pushed then
            ImGui.PopFont(ctx)
          end
        end

        -- Determine if Left Grid or Left Line mode applies
        local is_left_actor = (not is_actor_top) and show_actor_badge and main_sub.actor ~= "NoActor"
        local is_left_grid = is_left_actor and (state.overlay_actor_left_layout ~= "line")
        local is_left_line = is_left_actor and (state.overlay_actor_left_layout == "line")
        local actor_gap = math.max(0.0, state.overlay_actor_gap or 12.0)

        -- 2. MAIN DIALOGUE TEXT: FIXED 2-LINE SLOT
        local slot_start_y = ImGui.GetCursorPosY(ctx)

        if is_left_grid then
          -- GRID LAYOUT [Actor] [Text]
          -- A. Measure Actor column
          local main_act_sz = math.max(10, math.floor(state.overlay_actor_font_size or 18.0))
          local main_act_font = get_overlay_font(ctx, ImGui, main_act_sz)
          local main_actor_str = "[" .. main_sub.actor .. "]"
          local main_act_w = 0.0
          local main_act_h = 18.0

          if main_act_font and ImGui.PushFont then
            ImGui.PushFont(ctx, main_act_font)
            local w, h = ImGui.CalcTextSize(ctx, main_actor_str)
            main_act_w = w
            main_act_h = h
            ImGui.PopFont(ctx)
          else
            local w, h = ImGui.CalcTextSize(ctx, main_actor_str)
            main_act_w = w
            main_act_h = h
          end

          -- Limit actor column width if extremely long name
          local max_actor_col_w = math.max(40.0, avail_w * 0.40)
          local act_col_w = math.min(main_act_w, max_actor_col_w)

          -- Anchor actor column to left edge (with comfortable margin 22.0 px)
          local act_x = 22.0
          local text_col_x = act_x + act_col_w + actor_gap
          local text_col_w = math.max(40.0, win_w - 14.0 - text_col_x)

          -- Actor color
          local pal = state.actor_palette[main_sub.actor]
          local main_actor_col_u32
          if is_gap then
            if pal then
              local grey_r = 0.52 + pal.r * 0.28
              local grey_g = 0.52 + pal.g * 0.28
              local grey_b = 0.52 + pal.b * 0.28
              main_actor_col_u32 = ImGui.ColorConvertDouble4ToU32(grey_r, grey_g, grey_b, 0.60)
            else
              main_actor_col_u32 = ImGui.ColorConvertDouble4ToU32(0.60, 0.60, 0.60, 0.60)
            end
          else
            if pal then
              main_actor_col_u32 = ImGui.ColorConvertDouble4ToU32(pal.r, pal.g, pal.b, 1.0)
            else
              main_actor_col_u32 = main_text_u32
            end
          end

          -- B. Wrap & fit dialogue text inside text_col_w
          local chosen_sz, chosen_lines, chosen_lh = find_fitting_font_and_lines(
            ctx, ImGui, clean_main_text, base_sz, text_col_w, 2, main_slot_h
          )

          -- Vertical centering for actor cell inside main_slot_h (always centered across the 2-line slot)
          local act_y = slot_start_y + math.max(0.0, (main_slot_h - main_act_h) * 0.5)

          -- Draw actor badge pinned to left edge
          local act_font_pushed = false
          if main_act_font and ImGui.PushFont then
            ImGui.PushFont(ctx, main_act_font)
            act_font_pushed = true
          end
          -- Shadow
          ImGui.SetCursorPosX(ctx, act_x + 1.5)
          ImGui.SetCursorPosY(ctx, act_y + 1.5)
          ImGui.PushStyleColor(ctx, ImGui.Col_Text, main_shadow_u32)
          ImGui.Text(ctx, main_actor_str)
          ImGui.PopStyleColor(ctx, 1)
          -- Text
          ImGui.SetCursorPosX(ctx, act_x)
          ImGui.SetCursorPosY(ctx, act_y)
          ImGui.PushStyleColor(ctx, ImGui.Col_Text, main_actor_col_u32)
          ImGui.Text(ctx, main_actor_str)
          ImGui.PopStyleColor(ctx, 1)

          if act_font_pushed then
            ImGui.PopFont(ctx)
          end

          -- Vertical centering for text cell inside main_slot_h (1 line in center, 2 lines fill slot)
          local total_main_text_h = #chosen_lines * chosen_lh
          local text_y_start = slot_start_y + math.max(0.0, (main_slot_h - total_main_text_h) * 0.5)

          local main_f = get_overlay_font(ctx, ImGui, chosen_sz)
          local main_f_pushed = false
          if main_f and ImGui.PushFont then
            ImGui.PushFont(ctx, main_f)
            main_f_pushed = true
          end

          for idx, line in ipairs(chosen_lines) do
            if #line > 0 then
              -- Left-aligned within the dialogue text block:
              local line_x = text_col_x
              local line_y = text_y_start + (idx - 1) * chosen_lh

              -- Shadow
              ImGui.SetCursorPosX(ctx, line_x + 1.5)
              ImGui.SetCursorPosY(ctx, line_y + 1.5)
              ImGui.PushStyleColor(ctx, ImGui.Col_Text, main_shadow_u32)
              ImGui.Text(ctx, line)
              ImGui.PopStyleColor(ctx, 1)

              -- Main Text
              ImGui.SetCursorPosX(ctx, line_x)
              ImGui.SetCursorPosY(ctx, line_y)
              ImGui.PushStyleColor(ctx, ImGui.Col_Text, main_text_u32)
              ImGui.Text(ctx, line)
              ImGui.PopStyleColor(ctx, 1)
            end
          end

          if main_f_pushed then
            ImGui.PopFont(ctx)
          end
        else
          -- STANDARD / TOP MODE OR LEFT LINE MODE
          local main_prefix = ""
          local actor_left_col = main_text_u32
          if is_left_line then
            main_prefix = "[" .. main_sub.actor .. "] "
            local pal = state.actor_palette[main_sub.actor]
            if is_gap then
              if pal then
                local grey_r = 0.52 + pal.r * 0.28
                local grey_g = 0.52 + pal.g * 0.28
                local grey_b = 0.52 + pal.b * 0.28
                actor_left_col = ImGui.ColorConvertDouble4ToU32(grey_r, grey_g, grey_b, 0.60)
              else
                actor_left_col = ImGui.ColorConvertDouble4ToU32(0.60, 0.60, 0.60, 0.60)
              end
            else
              if pal then
                actor_left_col = ImGui.ColorConvertDouble4ToU32(pal.r, pal.g, pal.b, 1.0)
              else
                actor_left_col = main_text_u32
              end
            end
          end

          local text_to_fit = main_prefix .. clean_main_text
          local chosen_sz, chosen_lines, chosen_lh = find_fitting_font_and_lines(
            ctx, ImGui, text_to_fit, base_sz, avail_w, 2, main_slot_h
          )

          local total_main_text_h = #chosen_lines * chosen_lh
          -- Center vertically within the reserved 2-line slot:
          local y_offset = math.max(0.0, (main_slot_h - total_main_text_h) * 0.5)
          local text_y_start = slot_start_y + y_offset

          local main_f = get_overlay_font(ctx, ImGui, chosen_sz)
          local main_f_pushed = false
          if main_f and ImGui.PushFont then
            ImGui.PushFont(ctx, main_f)
            main_f_pushed = true
          end

          for idx, line in ipairs(chosen_lines) do
            if #line > 0 then
              local line_w, _ = ImGui.CalcTextSize(ctx, line)
              local x = 14
              if state.overlay_align == 1 then
                x = math.max(12, (win_w - line_w) * 0.5)
              elseif state.overlay_align == 2 then
                x = math.max(12, win_w - line_w - 14)
              end
              local cur_y = text_y_start + (idx - 1) * chosen_lh

              if idx == 1 and #main_prefix > 0 and line:sub(1, #main_prefix) == main_prefix then
                local pref_w, _ = ImGui.CalcTextSize(ctx, main_prefix)
                local remainder = line:sub(#main_prefix + 1)

                -- Prefix shadow
                ImGui.SetCursorPosX(ctx, x + 1.5)
                ImGui.SetCursorPosY(ctx, cur_y + 1.5)
                ImGui.PushStyleColor(ctx, ImGui.Col_Text, main_shadow_u32)
                ImGui.Text(ctx, main_prefix)
                ImGui.PopStyleColor(ctx, 1)

                -- Prefix text
                ImGui.SetCursorPosX(ctx, x)
                ImGui.SetCursorPosY(ctx, cur_y)
                ImGui.PushStyleColor(ctx, ImGui.Col_Text, actor_left_col)
                ImGui.Text(ctx, main_prefix)
                ImGui.PopStyleColor(ctx, 1)

                if #remainder > 0 then
                  -- Remainder shadow
                  ImGui.SetCursorPosX(ctx, x + pref_w + 1.5)
                  ImGui.SetCursorPosY(ctx, cur_y + 1.5)
                  ImGui.PushStyleColor(ctx, ImGui.Col_Text, main_shadow_u32)
                  ImGui.Text(ctx, remainder)
                  ImGui.PopStyleColor(ctx, 1)

                  -- Remainder text
                  ImGui.SetCursorPosX(ctx, x + pref_w)
                  ImGui.SetCursorPosY(ctx, cur_y)
                  ImGui.PushStyleColor(ctx, ImGui.Col_Text, main_text_u32)
                  ImGui.Text(ctx, remainder)
                  ImGui.PopStyleColor(ctx, 1)
                end
              else
                -- Shadow
                ImGui.SetCursorPosX(ctx, x + 1.5)
                ImGui.SetCursorPosY(ctx, cur_y + 1.5)
                ImGui.PushStyleColor(ctx, ImGui.Col_Text, main_shadow_u32)
                ImGui.Text(ctx, line)
                ImGui.PopStyleColor(ctx, 1)

                -- Main Text
                ImGui.SetCursorPosX(ctx, x)
                ImGui.SetCursorPosY(ctx, cur_y)
                ImGui.PushStyleColor(ctx, ImGui.Col_Text, main_text_u32)
                ImGui.Text(ctx, line)
                ImGui.PopStyleColor(ctx, 1)
              end
            end
          end

          if main_f_pushed then
            ImGui.PopFont(ctx)
          end
        end

        -- Ensure slot consumes exactly main_slot_h using SetCursorPosY
        ImGui.SetCursorPosY(ctx, slot_start_y + main_slot_h)

        -- 3. TELEPROMPTER PROGRESS BAR (Positioned at constant Y below main_slot_h)
        if not state.overlay_hide_progress then
          ImGui.Dummy(ctx, 1.0, 3.0)
          local bar_padding = 14.0
          local bar_w = math.max(20.0, win_w - bar_padding * 2)
          local bar_h = 3.5
          local bar_screen_x, bar_screen_y = ImGui.GetCursorScreenPos(ctx)

          local draw_list = ImGui.GetWindowDrawList(ctx)
          -- Background track
          ImGui.DrawList_AddRectFilled(draw_list, bar_screen_x, bar_screen_y, bar_screen_x + bar_w, bar_screen_y + bar_h, 0x00000055, 2.0)

          -- Progress bar fill:
          local filled_w = math.max(0.0, math.min(bar_w, bar_w * progress))
          if filled_w > 0.5 then
            local bar_col
            if is_gap then
              -- Shrinking countdown in gap: NEUTRAL GREY color
              bar_col = ImGui.ColorConvertDouble4ToU32(0.52, 0.52, 0.52, 0.70)
            elseif is_overtime then
              -- Overtime / hold phase: warm amber glow
              bar_col = ImGui.ColorConvertDouble4ToU32(0.96, 0.62, 0.12, 1.0)
            else
              -- Active speech filling bar: Actor color or text color (fully opaque)
              local pal = state.actor_palette[main_sub.actor]
              if pal and main_sub.actor ~= "NoActor" then
                bar_col = ImGui.ColorConvertDouble4ToU32(pal.r, pal.g, pal.b, 1.0)
              else
                bar_col = ImGui.ColorConvertDouble4ToU32(tr, tg, tb, 1.0)
              end
            end
            ImGui.DrawList_AddRectFilled(draw_list, bar_screen_x, bar_screen_y, bar_screen_x + filled_w, bar_screen_y + bar_h, bar_col, 2.0)
          end

          ImGui.Dummy(ctx, 1.0, bar_h + 3.0)
        else
          ImGui.Dummy(ctx, 1.0, 4.0)
        end

        -- 4. PREVIEW OF NEXT SUBTITLE (below progress bar)
        -- Uses grid layout matching main slot when in left position!
        if state.overlay_show_next_preview and preview_sub then
          local is_prev_own = (#state.selected_actors == 0) or state.is_actor_selected(preview_sub.actor)
          local should_tint_prev = state.overlay_tint_lines and (not state.overlay_tint_only_filtered or is_prev_own)
          local p_tr, p_tg, p_tb = tr * 0.9, tg * 0.9, tb * 0.9
          if should_tint_prev and preview_sub.actor ~= "NoActor" and state.actor_palette[preview_sub.actor] then
            local p = state.actor_palette[preview_sub.actor]
            p_tr = (0.35 + p.r * 0.65) * 0.9
            p_tg = (0.35 + p.g * 0.65) * 0.9
            p_tb = (0.35 + p.b * 0.65) * 0.9
          end

          local prev_alpha = is_gap and (ta * 0.42) or (ta * 0.58)
          local prev_text_u32 = ImGui.ColorConvertDouble4ToU32(p_tr, p_tg, p_tb, prev_alpha)
          local prev_shadow_u32 = ImGui.ColorConvertDouble4ToU32(0, 0, 0, prev_alpha * 0.85)

          local prev_base_sz = math.max(10, math.floor(state.overlay_next_font_size or 16.0))
          local prev_base_font = get_overlay_font(ctx, ImGui, prev_base_sz)
          local prev_base_line_step = 20.0
          if prev_base_font and ImGui.PushFont then
            ImGui.PushFont(ctx, prev_base_font)
            local _, plh = ImGui.CalcTextSize(ctx, "Ay")
            prev_base_line_step = plh + 2.0
            ImGui.PopFont(ctx)
          end

          local prev_slot_h = prev_base_line_step * 2.0
          local prev_slot_start_y = ImGui.GetCursorPosY(ctx)
          local clean_prev_text = parser.strip_invisible_unicode(preview_sub.text)

          local is_prev_left_grid = (state.overlay_actor_position == "left") and (state.overlay_actor_left_layout ~= "line") and show_actor_badge and preview_sub.actor ~= "NoActor"

          if is_prev_left_grid then
            -- PREVIEW GRID LAYOUT [Actor] [Text]
            local prev_actor_str = "[" .. preview_sub.actor .. "]"
            local prev_act_w = 0.0
            local prev_act_h = 16.0

            if prev_base_font and ImGui.PushFont then
              ImGui.PushFont(ctx, prev_base_font)
              local w, h = ImGui.CalcTextSize(ctx, prev_actor_str)
              prev_act_w = w
              prev_act_h = h
              ImGui.PopFont(ctx)
            else
              local w, h = ImGui.CalcTextSize(ctx, prev_actor_str)
              prev_act_w = w
              prev_act_h = h
            end

            local max_prev_act_col_w = math.max(40.0, avail_w * 0.40)
            local prev_act_col_w = math.min(prev_act_w, max_prev_act_col_w)

            -- Anchor preview actor to left edge (with comfortable margin 22.0 px)
            local p_act_x = 22.0
            local p_text_col_x = p_act_x + prev_act_col_w + actor_gap
            local prev_text_col_w = math.max(40.0, win_w - 14.0 - p_text_col_x)

            local prev_act_col = prev_text_u32
            local prev_pal = state.actor_palette[preview_sub.actor]
            if prev_pal then
              local p_r = 0.50 + prev_pal.r * 0.35
              local p_g = 0.50 + prev_pal.g * 0.35
              local p_b = 0.50 + prev_pal.b * 0.35
              prev_act_col = ImGui.ColorConvertDouble4ToU32(p_r, p_g, p_b, prev_alpha * 0.85)
            end

            local prev_chosen_sz, prev_chosen_lines, prev_chosen_lh = find_fitting_font_and_lines(
              ctx, ImGui, clean_prev_text, prev_base_sz, prev_text_col_w, 2, prev_slot_h
            )

            -- Vertical centering for actor in preview slot (centered over the 2-line slot)
            local p_act_y = prev_slot_start_y + math.max(0.0, (prev_slot_h - prev_act_h) * 0.5)

            local prev_f = get_overlay_font(ctx, ImGui, prev_chosen_sz)
            local p_f_pushed = false
            if prev_f and ImGui.PushFont then
              ImGui.PushFont(ctx, prev_f)
              p_f_pushed = true
            end

            -- Actor badge
            ImGui.SetCursorPosX(ctx, p_act_x + 1.5)
            ImGui.SetCursorPosY(ctx, p_act_y + 1.5)
            ImGui.PushStyleColor(ctx, ImGui.Col_Text, prev_shadow_u32)
            ImGui.Text(ctx, prev_actor_str)
            ImGui.PopStyleColor(ctx, 1)

            ImGui.SetCursorPosX(ctx, p_act_x)
            ImGui.SetCursorPosY(ctx, p_act_y)
            ImGui.PushStyleColor(ctx, ImGui.Col_Text, prev_act_col)
            ImGui.Text(ctx, prev_actor_str)
            ImGui.PopStyleColor(ctx, 1)

            -- Text lines (1 line centered, 2 lines fill slot)
            local total_p_text_h = #prev_chosen_lines * prev_chosen_lh
            local p_text_y_start = prev_slot_start_y + math.max(0.0, (prev_slot_h - total_p_text_h) * 0.5)

            for idx, line in ipairs(prev_chosen_lines) do
              if #line > 0 then
                -- Left-aligned within preview dialogue text block:
                local line_x = p_text_col_x
                local line_y = p_text_y_start + (idx - 1) * prev_chosen_lh

                -- Shadow
                ImGui.SetCursorPosX(ctx, line_x + 1.5)
                ImGui.SetCursorPosY(ctx, line_y + 1.5)
                ImGui.PushStyleColor(ctx, ImGui.Col_Text, prev_shadow_u32)
                ImGui.Text(ctx, line)
                ImGui.PopStyleColor(ctx, 1)

                -- Text
                ImGui.SetCursorPosX(ctx, line_x)
                ImGui.SetCursorPosY(ctx, line_y)
                ImGui.PushStyleColor(ctx, ImGui.Col_Text, prev_text_u32)
                ImGui.Text(ctx, line)
                ImGui.PopStyleColor(ctx, 1)
              end
            end

            if p_f_pushed then
              ImGui.PopFont(ctx)
            end
          else
            -- PREVIEW INLINE / STANDARD MODE (when actor is top or badge hidden)
            local prefix = ""
            local prev_act_col = prev_text_u32
            if show_actor_badge and preview_sub.actor ~= "NoActor" then
              prefix = "[" .. preview_sub.actor .. "] "
              local prev_pal = state.actor_palette[preview_sub.actor]
              if prev_pal then
                local p_r = 0.50 + prev_pal.r * 0.35
                local p_g = 0.50 + prev_pal.g * 0.35
                local p_b = 0.50 + prev_pal.b * 0.35
                prev_act_col = ImGui.ColorConvertDouble4ToU32(p_r, p_g, p_b, prev_alpha * 0.85)
              end
            end

            local full_prev_text = prefix .. clean_prev_text

            local prev_chosen_sz, prev_chosen_lines, prev_chosen_lh = find_fitting_font_and_lines(
              ctx, ImGui, full_prev_text, prev_base_sz, avail_w, 2, prev_slot_h
            )

            local total_prev_h = #prev_chosen_lines * prev_chosen_lh
            local prev_y_offset = math.max(0.0, (prev_slot_h - total_prev_h) * 0.5)
            local p_text_y_start = prev_slot_start_y + prev_y_offset

            local p_font = get_overlay_font(ctx, ImGui, prev_chosen_sz)
            local p_font_pushed = false
            if p_font and ImGui.PushFont then
              ImGui.PushFont(ctx, p_font)
              p_font_pushed = true
            end

            for idx, line in ipairs(prev_chosen_lines) do
              if #line > 0 then
                local line_w, _ = ImGui.CalcTextSize(ctx, line)
                local x = 14
                if state.overlay_align == 1 then
                  x = math.max(12, (win_w - line_w) * 0.5)
                elseif state.overlay_align == 2 then
                  x = math.max(12, win_w - line_w - 14)
                end
                local cur_y = p_text_y_start + (idx - 1) * prev_chosen_lh

                if idx == 1 and #prefix > 0 and line:sub(1, #prefix) == prefix then
                  local pref_w, _ = ImGui.CalcTextSize(ctx, prefix)
                  local remainder = line:sub(#prefix + 1)

                  -- Prefix shadow
                  ImGui.SetCursorPosX(ctx, x + 1.5)
                  ImGui.SetCursorPosY(ctx, cur_y + 1.5)
                  ImGui.PushStyleColor(ctx, ImGui.Col_Text, prev_shadow_u32)
                  ImGui.Text(ctx, prefix)
                  ImGui.PopStyleColor(ctx, 1)

                  -- Prefix text
                  ImGui.SetCursorPosX(ctx, x)
                  ImGui.SetCursorPosY(ctx, cur_y)
                  ImGui.PushStyleColor(ctx, ImGui.Col_Text, prev_act_col)
                  ImGui.Text(ctx, prefix)
                  ImGui.PopStyleColor(ctx, 1)

                  if #remainder > 0 then
                    -- Remainder shadow
                    ImGui.SetCursorPosX(ctx, x + pref_w + 1.5)
                    ImGui.SetCursorPosY(ctx, cur_y + 1.5)
                    ImGui.PushStyleColor(ctx, ImGui.Col_Text, prev_shadow_u32)
                    ImGui.Text(ctx, remainder)
                    ImGui.PopStyleColor(ctx, 1)

                    -- Remainder text
                    ImGui.SetCursorPosX(ctx, x + pref_w)
                    ImGui.SetCursorPosY(ctx, cur_y)
                    ImGui.PushStyleColor(ctx, ImGui.Col_Text, prev_text_u32)
                    ImGui.Text(ctx, remainder)
                    ImGui.PopStyleColor(ctx, 1)
                  end
                else
                  -- Shadow
                  ImGui.SetCursorPosX(ctx, x + 1.5)
                  ImGui.SetCursorPosY(ctx, cur_y + 1.5)
                  ImGui.PushStyleColor(ctx, ImGui.Col_Text, prev_shadow_u32)
                  ImGui.Text(ctx, line)
                  ImGui.PopStyleColor(ctx, 1)

                  -- Main Text
                  ImGui.SetCursorPosX(ctx, x)
                  ImGui.SetCursorPosY(ctx, cur_y)
                  ImGui.PushStyleColor(ctx, ImGui.Col_Text, prev_text_u32)
                  ImGui.Text(ctx, line)
                  ImGui.PopStyleColor(ctx, 1)
                end
              end
            end

            if p_font_pushed then
              ImGui.PopFont(ctx)
            end
          end

          ImGui.SetCursorPosY(ctx, prev_slot_start_y + prev_slot_h)
        end
      else
        -- Past the last subtitle
        if ImGui.IsWindowHovered(ctx) then
          ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x88888888)
          local hint = "NutNotes Оверлей (реплики закончились)"
          local hw, hh = ImGui.CalcTextSize(ctx, hint)
          ImGui.SetCursorPosX(ctx, math.max(10, (win_w - hw) * 0.5))
          ImGui.SetCursorPosY(ctx, math.max(10, (win_h - hh) * 0.5))
          ImGui.Text(ctx, hint)
          ImGui.PopStyleColor(ctx, 1)
        end
      end
    else
      -- No subtitles loaded: render subtle nuts watermark (without circle)
      local win_pos_x, win_pos_y = ImGui.GetWindowPos(ctx)
      local cx = win_pos_x + win_w * 0.5
      local cy = win_pos_y + win_h * 0.5
      watermark.draw(ctx, ImGui, cx, cy, math.min(win_w, win_h), false, state)

      if ImGui.IsWindowHovered(ctx) then
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x88888888)
        local hint = "NutNotes Оверлей (перетащите окно мышью за фон, тяните за правый нижний край для изменения размера)"
        local hw, hh = ImGui.CalcTextSize(ctx, hint)
        ImGui.SetCursorPosX(ctx, math.max(10, (win_w - hw) * 0.5))
        ImGui.SetCursorPosY(ctx, math.max(10, (win_h - hh) * 0.5))
        ImGui.Text(ctx, hint)
        ImGui.PopStyleColor(ctx, 1)
      end
    end

    -- Context menu on right click
    if ImGui.BeginPopupContextWindow(ctx) then
      if ImGui.MenuItem(ctx, "✕ Закрыть оверлей") then
        state.overlay_enabled = false
        state.save_settings()
      end
      ImGui.Separator(ctx)
      local rv_top, new_top = ImGui.MenuItem(ctx, "Поверх всех окон", nil, state.overlay_always_on_top)
      if rv_top then
        state.overlay_always_on_top = new_top
        state.save_settings()
      end
      local rv_all, new_all = ImGui.MenuItem(ctx, "Показывать все реплики (всех актеров)", nil, state.overlay_show_all_actors)
      if rv_all then
        state.overlay_show_all_actors = new_all
        state.save_settings()
      end
      local rv_prv, new_prv = ImGui.MenuItem(ctx, "Предпоказ следующей реплики", nil, state.overlay_show_next_preview)
      if rv_prv then
        state.overlay_show_next_preview = new_prv
        state.save_settings()
      end
      local rv_hp, new_hp = ImGui.MenuItem(ctx, "Скрыть прогресс реплики", nil, state.overlay_hide_progress)
      if rv_hp then
        state.overlay_hide_progress = new_hp
        state.save_settings()
      end
      local rv_act, new_act = ImGui.MenuItem(ctx, "Отображать имя актера", nil, state.overlay_show_actor)
      if rv_act then
        state.overlay_show_actor = new_act
        state.save_settings()
      end
      if state.overlay_show_actor and ImGui.BeginMenu then
        if ImGui.BeginMenu(ctx, "Положение имени актера") then
          local is_top = (state.overlay_actor_position ~= "left")
          if ImGui.MenuItem(ctx, "Сверху", nil, is_top) then
            state.overlay_actor_position = "top"
            state.save_settings()
          end
          if ImGui.MenuItem(ctx, "Слева", nil, not is_top) then
            state.overlay_actor_position = "left"
            state.save_settings()
          end
          ImGui.EndMenu(ctx)
        end
        if state.overlay_actor_position == "left" and ImGui.BeginMenu(ctx, "Режим отображения слева") then
          local is_line = (state.overlay_actor_left_layout == "line")
          if ImGui.MenuItem(ctx, "Строка ([Актер] Текст)", nil, is_line) then
            state.overlay_actor_left_layout = "line"
            state.save_settings()
          end
          if ImGui.MenuItem(ctx, "Сетка (Колонки)", nil, not is_line) then
            state.overlay_actor_left_layout = "grid"
            state.save_settings()
          end
          ImGui.EndMenu(ctx)
        end
      end
      ImGui.EndPopup(ctx)
    end

    -- Final safety dummy item to ensure window boundaries are naturally closed
    ImGui.Dummy(ctx, 0.0, 0.0)

    -- Drop target for overlay window
    if ImGui.BeginDragDropTarget and ImGui.BeginDragDropTarget(ctx) then
      local rv, count = ImGui.AcceptDragDropPayloadFiles and ImGui.AcceptDragDropPayloadFiles(ctx)
      if rv and count and count > 0 then
        for i = 0, count - 1 do
          local ok, filepath = false, nil
          if ImGui.GetDragDropPayloadFile then
            ok, filepath = ImGui.GetDragDropPayloadFile(ctx, i)
          end
          if ok and filepath and type(filepath) == "string" and #filepath > 0 then
            filepath = filepath:gsub("\\", "/")
            local ext = filepath:match("%.([^%.]+)$")
            if ext then ext = ext:lower() end
            if ext == "ass" or ext == "srt" or ext == "sub" or ext == "vtt" or ext == "txt" then
              state.load_file(filepath)
              actions.sync_filter_to_timeline(state)
              break
            end
          end
        end
      end
      ImGui.EndDragDropTarget(ctx)
    end
    pcall(ImGui.End, ctx)
  end

  is_overlay_frame_active = false

  -- On mouse release (click or drag on overlay finished), return keyboard focus to REAPER
  if (ImGui.IsMouseReleased(ctx, 0) or ImGui.IsMouseReleased(ctx, 1) or ImGui.IsMouseReleased(ctx, 2)) then
    if not actions.is_text_editing_active(ctx, state, ImGui) and not actions.is_popup_open(ctx, ImGui) then
      actions.return_focus_to_reaper()
    end
  end

  ImGui.PopStyleVar(ctx, 3)
  ImGui.PopStyleColor(ctx, 1)
end

function overlay.draw_timer(ctx, state, ImGui)
  if not state.timer_overlay_enabled then return end

  local flags = ImGui.WindowFlags_NoTitleBar
              | ImGui.WindowFlags_NoScrollbar
              | ImGui.WindowFlags_NoCollapse
              | ImGui.WindowFlags_NoDocking

  if ImGui.WindowFlags_NoNavInputs then flags = flags | ImGui.WindowFlags_NoNavInputs end
  if ImGui.WindowFlags_NoNavFocus then flags = flags | ImGui.WindowFlags_NoNavFocus end
  if ImGui.WindowFlags_NoFocusOnAppearing then flags = flags | ImGui.WindowFlags_NoFocusOnAppearing end

  if state.overlay_always_on_top and ImGui.WindowFlags_TopMost then
    flags = flags | ImGui.WindowFlags_TopMost
  end

  local bg_alpha = state.timer_overlay_bg_alpha or 0.75
  local bg_r = (state.timer_overlay_bg_color and state.timer_overlay_bg_color[1]) or 0.0
  local bg_g = (state.timer_overlay_bg_color and state.timer_overlay_bg_color[2]) or 0.0
  local bg_b = (state.timer_overlay_bg_color and state.timer_overlay_bg_color[3]) or 0.0
  local bg_u32 = ImGui.ColorConvertDouble4ToU32(bg_r, bg_g, bg_b, bg_alpha)

  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, bg_u32)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 8.0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 8.0, 4.0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowBorderSize, 1.0)

  ImGui.SetNextWindowSize(ctx, 240, 75, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, "NutNotes Timer Overlay##FloatingTimer", true, flags)
  if not open then
    state.timer_overlay_enabled = false
    state.save_settings()
  end

  if visible then
    local cur_time = 0
    local play_state = (reaper and reaper.GetPlayState and reaper.GetPlayState()) or 0
    local is_playing = (play_state & 1) ~= 0
    local is_paused = (play_state & 2) ~= 0
    local is_recording = (play_state & 4) ~= 0

    if is_playing and reaper.GetPlayPosition then
      cur_time = reaper.GetPlayPosition()
    elseif reaper.GetCursorPosition then
      cur_time = reaper.GetCursorPosition()
    end
    if cur_time < 0 then cur_time = 0 end

    local fmt = state.timer_overlay_format or 1
    local time_str = ""
    local total_sec = math.floor(cur_time)
    local frac_hundredth = math.floor((cur_time - total_sec) * 100)
    if frac_hundredth > 99 then frac_hundredth = 99 end
    if frac_hundredth < 0 then frac_hundredth = 0 end
    local frac_tenth = math.floor(frac_hundredth / 10)

    local h = math.floor(total_sec / 3600)
    local m = math.floor((total_sec % 3600) / 60)
    local s = total_sec % 60

    if fmt == 1 then
      -- MM:SS.dd
      time_str = string.format("%02d:%02d.%02d", m, s, frac_hundredth)
    elseif fmt == 2 then
      -- HH:MM:SS.dd
      time_str = string.format("%02d:%02d:%02d.%02d", h, m, s, frac_hundredth)
    elseif fmt == 3 then
      -- SS.dd
      time_str = string.format("%.2f", cur_time)
    elseif fmt == 4 then
      -- MM:SS.d
      time_str = string.format("%02d:%02d.%d", m, s, frac_tenth)
    elseif fmt == 5 then
      -- HH:MM:SS.d
      time_str = string.format("%02d:%02d:%02d.%d", h, m, s, frac_tenth)
    elseif fmt == 6 then
      -- SS.d
      time_str = string.format("%.1f", cur_time)
    elseif fmt == 7 then
      -- MM:SS
      time_str = string.format("%02d:%02d", m, s)
    elseif fmt == 8 then
      -- HH:MM:SS
      time_str = string.format("%02d:%02d:%02d", h, m, s)
    else
      time_str = string.format("%02d:%02d.%02d", m, s, frac_hundredth)
    end

    local status_badge = "STOP"
    local badge_color = 0x8892B0FF

    if is_recording then
      status_badge = "REC"
      badge_color = 0xFF4444FF
    elseif is_playing then
      status_badge = "PLAY"
      badge_color = 0x44EE77FF
    elseif is_paused then
      status_badge = "PAUSE"
      badge_color = 0xFFAA33FF
    else
      status_badge = "STOP"
      badge_color = 0x8892B0FF
    end

    local color_mode = state.timer_overlay_color_mode or 1
    local text_color = 0xFFFFFFFF
    if color_mode == 2 or color_mode == 3 then
      -- Mode 2: "Включено" (динамическая цветовая реакция на статус REAPER)
      text_color = badge_color
    else
      -- Mode 1: "Нет" (постоянный цвет, выбранный пользователем, по умолчанию белый)
      local col = state.timer_custom_color or { 1.0, 1.0, 1.0, 1.0 }
      text_color = ImGui.ColorConvertDouble4ToU32(col[1] or 1.0, col[2] or 1.0, col[3] or 1.0, col[4] or 1.0)
    end

    local avail_w, avail_h = ImGui.GetContentRegionAvail(ctx)
    local font_family = state.timer_overlay_font_family or "Segoe UI"

    -- Calculate ideal font size based on window width and height to smoothly scale
    local char_len = math.max(4, #time_str)
    local max_sz_w = (avail_w * 0.88) / (char_len * 0.58)
    local max_sz_h = avail_h * 0.72
    local ideal_sz = math.max(10, math.min(160, math.floor(math.min(max_sz_w, max_sz_h))))

    local font = find_closest_timer_font(font_family, ideal_sz)
    if not font then
      font = find_closest_overlay_font(ideal_sz)
    end

    if font then ImGui.PushFont(ctx, font) end

    local text_w, text_h = ImGui.CalcTextSize(ctx, time_str)
    local off_x = math.max(0.0, (avail_w - text_w) * 0.5)
    local off_y = math.max(0.0, (avail_h - text_h) * 0.5)

    ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + off_x)
    ImGui.SetCursorPosY(ctx, ImGui.GetCursorPosY(ctx) + off_y)

    ImGui.PushStyleColor(ctx, ImGui.Col_Text, text_color)
    ImGui.Text(ctx, time_str)
    ImGui.PopStyleColor(ctx, 1)

    if font then ImGui.PopFont(ctx) end

    local draw_list = ImGui.GetWindowDrawList(ctx)
    local win_min_x, win_min_y = ImGui.GetWindowPos(ctx)
    local win_w, win_h = ImGui.GetWindowSize(ctx)
    if win_w >= 100 and win_h >= 45 then
      local b_font = get_overlay_font(ctx, ImGui, 10)
      if b_font then ImGui.PushFont(ctx, b_font) end
      local bw, bh = ImGui.CalcTextSize(ctx, status_badge)
      local bx = win_min_x + win_w - bw - 8.0
      local by = win_min_y + win_h - bh - 4.0
      ImGui.DrawList_AddText(draw_list, bx, by, badge_color, status_badge)
      if b_font then ImGui.PopFont(ctx) end
    end

    -- Drop target for timer overlay window
    if ImGui.BeginDragDropTarget and ImGui.BeginDragDropTarget(ctx) then
      local rv, count = ImGui.AcceptDragDropPayloadFiles and ImGui.AcceptDragDropPayloadFiles(ctx)
      if rv and count and count > 0 then
        for i = 0, count - 1 do
          local ok, filepath = false, nil
          if ImGui.GetDragDropPayloadFile then
            ok, filepath = ImGui.GetDragDropPayloadFile(ctx, i)
          end
          if ok and filepath and type(filepath) == "string" and #filepath > 0 then
            filepath = filepath:gsub("\\", "/")
            local ext = filepath:match("%.([^%.]+)$")
            if ext then ext = ext:lower() end
            if ext == "ass" or ext == "srt" or ext == "sub" or ext == "vtt" or ext == "txt" then
              state.load_file(filepath)
              actions.sync_filter_to_timeline(state)
              break
            end
          end
        end
      end
      ImGui.EndDragDropTarget(ctx)
    end

    pcall(ImGui.End, ctx)
  end

  -- On mouse release on timer overlay, return keyboard focus to REAPER
  if (ImGui.IsMouseReleased(ctx, 0) or ImGui.IsMouseReleased(ctx, 1) or ImGui.IsMouseReleased(ctx, 2)) then
    if not actions.is_text_editing_active(ctx, state, ImGui) and not actions.is_popup_open(ctx, ImGui) then
      actions.return_focus_to_reaper()
    end
  end

  ImGui.PopStyleVar(ctx, 3)
  ImGui.PopStyleColor(ctx, 1)
end

overlay.render = overlay.draw

return overlay
