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
local is_overlay_frame_active = false

function overlay.attach_font_now(ctx, ImGui, size)
  if not ImGui or not ImGui.CreateFont or not ImGui.Attach or not ctx then return nil end
  size = math.max(9, math.min(96, math.floor(size)))
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

function overlay.init_fonts(ctx, state, ImGui)
  if not ImGui or not ImGui.CreateFont or not ImGui.Attach or not ctx then return end
  local common_sizes = { 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 36, 40, 44, 48, 56, 64, 72, 80, 88, 96 }
  if state and state.overlay_font_size then
    table.insert(common_sizes, math.floor(state.overlay_font_size))
  end
  for _, sz in ipairs(common_sizes) do
    overlay.attach_font_now(ctx, ImGui, sz)
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
end

local function find_closest_overlay_font(size)
  size = math.max(9, math.min(96, math.floor(size)))
  if overlay_font_cache[size] then return overlay_font_cache[size] end
  local best_f = nil
  local best_diff = 999
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

local function get_overlay_font(ctx, ImGui, size)
  if not ImGui or not ImGui.CreateFont or not ImGui.Attach then return nil end
  size = math.max(9, math.min(96, math.floor(size)))
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
  local visible, open = ImGui.Begin(ctx, "NutNotes (Оверлей)###NUTNOTES_OVERLAY_WINDOW", true, flags)
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
      -- 1. Find currently playing sub or upcoming sub and previous sub
      local playing_idx = nil
      local upcoming_idx = nil
      local prev_idx = nil

      for i, sub in ipairs(subs_to_use) do
        if cur_time >= sub.start_time and cur_time <= sub.end_time then
          playing_idx = i
          break
        elseif sub.start_time > cur_time then
          upcoming_idx = i
          if i > 1 then
            prev_idx = i - 1
          end
          break
        else
          prev_idx = i
        end
      end

      local main_sub = nil
      local preview_sub = nil
      local is_gap = false
      local progress = 0.0

      if playing_idx then
        -- Speech in progress: Line is playing
        main_sub = subs_to_use[playing_idx]
        is_gap = false
        local dur = math.max(0.001, main_sub.end_time - main_sub.start_time)
        progress = math.min(1.0, math.max(0.0, (cur_time - main_sub.start_time) / dur))

        if state.overlay_show_next_preview then
          preview_sub = subs_to_use[playing_idx + 1]
        end
      elseif upcoming_idx then
        -- Gap / pause before upcoming line: Upcoming line is main text (dimmed), bar is shrinking countdown
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

overlay.render = overlay.draw

return overlay
