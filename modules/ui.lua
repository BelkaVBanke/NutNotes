--[[

  Main ReaImGui UI module for REAPER Subtitle Plugin.

  Renders the dockable main window, tabs, filters, modals, and list view.

]]



local parser = require('parser')

local actions = require('actions')

local colors = require('colors')

local watermark = require('watermark')

local overlay = require('overlay')



local ui = {}



local font_cache = {}

local pending_fonts = {}

local is_frame_active = false



function ui.attach_font_now(ctx, ImGui, family, size)

  if not ImGui or not ImGui.CreateFont or not ImGui.Attach or not ctx then return nil end

  family = family or "Segoe UI"

  size = math.max(10, math.floor(size or 14))

  local key = string.format("%s_%d", family, size)

  if font_cache[key] ~= nil then

    return font_cache[key]

  end



  local ok, font = pcall(ImGui.CreateFont, family, size, 0)

  if not (ok and font) then

    ok, font = pcall(ImGui.CreateFont, family, 0)

  end

  if ok and font then

    local a_ok = pcall(ImGui.Attach, ctx, font)

    if a_ok then

      font_cache[key] = font

      return font

    end

  end

  font_cache[key] = false

  return nil

end



function ui.init_fonts(ctx, state, ImGui)

  if not ImGui or not ImGui.CreateFont or not ImGui.Attach or not ctx then return end

  local fam = (state and state.text_font_family) or "Segoe UI"

  local sizes = { 10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 22, 24, 26, 28, 32, 36, 40, 44, 48, 54, 60, 66, 72 }

  if state and state.subtitles_font_size then

    table.insert(sizes, math.floor(state.subtitles_font_size))

    table.insert(sizes, math.floor(state.subtitles_font_size * 1.25))

  end

  for _, sz in ipairs(sizes) do

    ui.attach_font_now(ctx, ImGui, fam, sz)

    if fam ~= "sans-serif" then

      ui.attach_font_now(ctx, ImGui, "sans-serif", sz)

    end

  end

end



function ui.check_fonts(ctx, state, ImGui)

  if not ImGui or not ImGui.CreateFont or not ImGui.Attach or not ctx then return end

  for key, req in pairs(pending_fonts) do

    if font_cache[key] == nil or font_cache[key] == false then

      ui.attach_font_now(ctx, ImGui, req.family, req.size)

    end

  end

  pending_fonts = {}

end



local function find_closest_font(family, size)

  family = family or "Segoe UI"

  size = math.max(10, math.floor(size or 14))

  local key = string.format("%s_%d", family, size)

  if font_cache[key] then return font_cache[key] end



  local best_font = nil

  local best_diff = 999

  for k, f in pairs(font_cache) do

    if f and type(f) ~= "boolean" then

      local k_fam, k_sz = k:match("^(.-)_(%d+)$")

      if k_fam == family and k_sz then

        local diff = math.abs(tonumber(k_sz) - size)

        if diff < best_diff then

          best_diff = diff

          best_font = f

        end

      end

    end

  end

  if best_font then return best_font end



  for _, f in pairs(font_cache) do

    if f and type(f) ~= "boolean" then return f end

  end

  return nil

end



local function get_or_attach_font(ctx, ImGui, family, size)

  if not ImGui or not ImGui.CreateFont or not ImGui.Attach then return nil end

  family = family or "Segoe UI"

  size = math.max(10, math.floor(size or 18))

  local key = string.format("%s_%d", family, size)



  if font_cache[key] then

    return font_cache[key]

  end



  -- If frame is NOT active, we can safely attach now

  if not is_frame_active then

    return ui.attach_font_now(ctx, ImGui, family, size)

  end



  -- Frame IS active: NEVER call ImGui.Attach while a frame is in progress!

  -- Queue for next frame and return closest matching font immediately

  pending_fonts[key] = { family = family, size = size }

  return find_closest_font(family, size)

end



-- Configurable tooltip renderer using custom tooltip font size

local function set_tooltip(ctx, state, ImGui, text)

  if not text or text == "" then return end

  if ImGui.BeginTooltip and ImGui.EndTooltip then

    if ImGui.BeginTooltip(ctx) then

      local font = get_or_attach_font(ctx, ImGui, state and state.text_font_family, state and state.tooltip_font_size or 14.0)

      local font_pushed = false

      if font and ImGui.PushFont then

        ImGui.PushFont(ctx, font)

        font_pushed = true

      end

      ImGui.Text(ctx, text)

      if font_pushed then

        ImGui.PopFont(ctx)

      end

      ImGui.EndTooltip(ctx)

    end

  else

    ImGui.SetTooltip(ctx, text)

  end

end



-- Helper to open URLs in default browser without freezing the REAPER UI

local function open_url_async(url)

  if not url or url == "" then return end

  if reaper and reaper.CF_ShellExecute then

    reaper.CF_ShellExecute(url)

  elseif package.config:sub(1, 1) == "\\" then

    -- Windows: run via rundll32 or explorer in background without blocking

    reaper.ExecProcess(string.format('rundll32.exe url.dll,FileProtocolHandler "%s"', url), 0)

  else

    -- macOS / Linux

    local cmd = string.format('open "%s" 2>/dev/null || xdg-open "%s" 2>/dev/null &', url, url)

    if reaper and reaper.ExecProcess then

      reaper.ExecProcess(cmd, 0)

    elseif os and os.execute then

      os.execute(cmd)

    end

  end

end



-- Resolve accent color into active/hovered/active U32 variants

local function get_accent_colors(state, ImGui)

  local c = (state and state.accent_color) or { 0.16, 0.55, 0.35 }

  local r, g, b = c[1] or 0.16, c[2] or 0.55, c[3] or 0.35

  local base_u32 = ImGui.ColorConvertDouble4ToU32(r, g, b, 0.92)

  local hov_u32  = ImGui.ColorConvertDouble4ToU32(math.min(1.0, r * 1.18 + 0.05), math.min(1.0, g * 1.18 + 0.05), math.min(1.0, b * 1.18 + 0.05), 0.98)

  local act_u32  = ImGui.ColorConvertDouble4ToU32(math.min(1.0, r * 1.30 + 0.10), math.min(1.0, g * 1.30 + 0.10), math.min(1.0, b * 1.30 + 0.10), 1.0)

  local soft_u32 = ImGui.ColorConvertDouble4ToU32(r, g, b, 0.28)

  return base_u32, hov_u32, act_u32, soft_u32

end



-- Render a clean modern section header with divider line

local function render_section_header(ctx, ImGui, title, accent_u32)

  ImGui.Spacing(ctx)

  local p_min_x, p_min_y = ImGui.GetCursorScreenPos(ctx)

  local avail_w, _ = ImGui.GetContentRegionAvail(ctx)

  local txt_w, txt_h = ImGui.CalcTextSize(ctx, title)

  

  local draw_list = ImGui.GetWindowDrawList(ctx)

  -- Left small accent indicator pill

  local bar_w = 3.0

  local text_gap = 8.0

  local bar_col = accent_u32 or 0x4A90E2FF

  ImGui.DrawList_AddRectFilled(draw_list, p_min_x, p_min_y + 1.0, p_min_x + bar_w, p_min_y + txt_h - 1.0, bar_col, 1.5)

  

  -- Title text with clean gap from the vertical accent bar

  local old_x = ImGui.GetCursorPosX(ctx)

  ImGui.SetCursorPosX(ctx, old_x + bar_w + text_gap)

  ImGui.TextColored(ctx, 0xD0D5DDFF, title)



  -- Subtle horizontal divider line across the remaining width

  local line_y = p_min_y + txt_h * 0.5

  local line_start_x = p_min_x + bar_w + text_gap + txt_w + 10.0

  if line_start_x < p_min_x + avail_w then

    ImGui.DrawList_AddLine(draw_list, line_start_x, line_y, p_min_x + avail_w, line_y, 0x333946AA, 1.0)

  end

  ImGui.Spacing(ctx)

end



-- Safely PushStyleColor only if the color constant exists and is non-nil in this ReaImGui version

local function safe_push_style_color(ctx, ImGui, col_idx, col_u32)

  if col_idx and col_u32 and ImGui and ImGui.PushStyleColor then

    ImGui.PushStyleColor(ctx, col_idx, col_u32)

    return 1

  end

  return 0

end



-- Render iOS/mobile style animated toggle switch (Mockup 3)

-- Returns: changed (bool), new_val (bool)

local function render_toggle_switch(ctx, state, ImGui, str_id, label, current_val, accent_u32)

  local font_sz = (state and state.ui_font_size) or 11.0

  local frame_h = (ImGui and ImGui.GetFrameHeight) and ImGui.GetFrameHeight(ctx) or (font_sz * 1.5)

  local height = math.max(16.0, math.floor(frame_h - 2.0))

  local width = math.floor(height * 1.85)

  local radius = height * 0.5



  local pos_x = ImGui.GetCursorPosX(ctx)

  local pos_y = ImGui.GetCursorPosY(ctx)

  local p_min_x, p_min_y = ImGui.GetCursorScreenPos(ctx)



  -- Invisible button covering the switch widget area

  local btn_id = "##switch_" .. str_id

  local clicked = ImGui.InvisibleButton(ctx, btn_id, width, height)

  local hovered = ImGui.IsItemHovered(ctx)



  local new_val = current_val

  if clicked then

    new_val = not current_val

  end



  local draw_list = ImGui.GetWindowDrawList(ctx)



  -- Background track color

  local track_col

  if current_val then

    track_col = accent_u32 or 0x3373BFFF

  else

    track_col = hovered and 0x3E4554FF or 0x2A313EFF

  end



  ImGui.DrawList_AddRectFilled(draw_list, p_min_x, p_min_y, p_min_x + width, p_min_y + height, track_col, radius)



  -- Moving knob (circle)

  local knob_radius = math.max(4.0, radius - 2.0)

  local knob_center_y = p_min_y + radius

  local knob_center_x = current_val and (p_min_x + width - radius) or (p_min_x + radius)



  -- Knob shadow & fill

  ImGui.DrawList_AddCircleFilled(draw_list, knob_center_x, knob_center_y + 0.5, knob_radius, 0x00000044)

  ImGui.DrawList_AddCircleFilled(draw_list, knob_center_x, knob_center_y, knob_radius, 0xFFFFFFFF)



  -- Label text next to the toggle switch

  if label and #label > 0 then

    ImGui.SameLine(ctx, 0, 8.0)

    ImGui.AlignTextToFramePadding(ctx)

    ImGui.Text(ctx, label)

  end



  return (new_val ~= current_val), new_val

end



-- Render modern centered rounded pill button (e.g. "Сбросить") matching Mockup 3

local function render_reset_pill_button(ctx, ImGui, str_id, label, width, height, center_in_avail)

  local font_sz = 11.0

  if ImGui and ImGui.GetFontSize then

    font_sz = ImGui.GetFontSize(ctx)

  end

  local scale = math.max(0.85, font_sz / 11.0)

  width = width and (width * scale) or (140.0 * scale)

  height = height and (height * scale) or math.max(24.0, math.floor(28.0 * scale))

  

  if center_in_avail then

    local avail_w, _ = ImGui.GetContentRegionAvail(ctx)

    if width < avail_w then

      ImGui.SetCursorPosX(ctx, (avail_w - width) * 0.5)

    end

  end



  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, height * 0.5)

  ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x242A35CC)

  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x333C4CAA)

  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x424D60EE)

  ImGui.PushStyleColor(ctx, ImGui.Col_Border, 0x3A445688)

  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, 1.0)

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xB0B7C3FF)



  local clicked = ImGui.Button(ctx, (label or "") .. "###" .. str_id, width, height)



  ImGui.PopStyleColor(ctx, 5)

  ImGui.PopStyleVar(ctx, 2)

  return clicked

end



-- Render small modern collapse/expand pill button (e.g. "Свернуть" / "Развернуть")

local function render_collapse_pill_button(ctx, ImGui, str_id, label, width, height)

  local font_sz = 11.0

  if ImGui and ImGui.GetFontSize then

    font_sz = ImGui.GetFontSize(ctx)

  end

  local scale = math.max(0.85, font_sz / 11.0)

  width = width and (width * scale) or (96.0 * scale)

  height = height and (height * scale) or math.max(20.0, math.floor(22.0 * scale))



  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, height * 0.5)

  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, 1.0)

  ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x242A35CC)

  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x333C4CAA)

  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x424D60EE)

  ImGui.PushStyleColor(ctx, ImGui.Col_Border, 0x3A445688)

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xB0B7C3FF)



  local clicked = ImGui.Button(ctx, (label or "") .. "###" .. str_id, width, height)



  ImGui.PopStyleColor(ctx, 5)

  ImGui.PopStyleVar(ctx, 2)

  return clicked

end



-- Push modern combo styles: dark input background (#2A313E), crisp vivid accent border & drop-down arrow

local function push_modern_combo_styles(ctx, ImGui, state)

  local base_acc, hov_acc, act_acc = get_accent_colors(state, ImGui)

  local p_cols = 0

  -- Dark text background identical to general settings color input (#2A313E)

  p_cols = p_cols + safe_push_style_color(ctx, ImGui, ImGui.Col_FrameBg, 0x2A313EFF)

  p_cols = p_cols + safe_push_style_color(ctx, ImGui, ImGui.Col_FrameBgHovered, 0x333A4AFF)

  p_cols = p_cols + safe_push_style_color(ctx, ImGui, ImGui.Col_FrameBgActive, 0x3E475AFF)

  -- Crisp vivid accent border (bright, not muddy)

  p_cols = p_cols + safe_push_style_color(ctx, ImGui, ImGui.Col_Border, base_acc)

  -- Bright accent drop-down flag/button

  p_cols = p_cols + safe_push_style_color(ctx, ImGui, ImGui.Col_Button, base_acc)

  p_cols = p_cols + safe_push_style_color(ctx, ImGui, ImGui.Col_ButtonHovered, hov_acc)

  p_cols = p_cols + safe_push_style_color(ctx, ImGui, ImGui.Col_ButtonActive, act_acc)

  p_cols = p_cols + safe_push_style_color(ctx, ImGui, ImGui.Col_Text, 0xE2E8F0FF)



  local p_vars = 0

  if ImGui.StyleVar_FrameBorderSize then

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, 1.0)

    p_vars = p_vars + 1

  end

  if ImGui.StyleVar_FrameRounding then

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 5.0)

    p_vars = p_vars + 1

  end

  return p_cols, p_vars

end



local function pop_modern_combo_styles(ctx, ImGui, p_cols, p_vars)

  if p_cols and p_cols > 0 then

    ImGui.PopStyleColor(ctx, p_cols)

  end

  if p_vars and p_vars > 0 then

    ImGui.PopStyleVar(ctx, p_vars)

  end

end



-- Push modern popup context menu & modal styles matching Mockup 2 (Nutnotes Actors Tab)

-- Deep refined dark card background (#181B20 / 0x181B20FA), crisp subtle border (#2E3440 / 0x2E3440EE),

-- soft rounded corners (8.0px), clean padding, and sleek hover state.

local function push_modern_popup_styles(ctx, ImGui, state)

  local base_acc, hov_acc, act_acc = get_accent_colors(state, ImGui)

  local p_cols = 0

  -- Background: sleek dark tone matching mockup 2

  p_cols = p_cols + safe_push_style_color(ctx, ImGui, ImGui.Col_PopupBg, 0x181B20FA)

  -- Border: refined outline matching mockup 2

  p_cols = p_cols + safe_push_style_color(ctx, ImGui, ImGui.Col_Border, 0x2E3440EE)

  -- Menu items / Header hover & active

  p_cols = p_cols + safe_push_style_color(ctx, ImGui, ImGui.Col_Header, 0x242A3499)

  p_cols = p_cols + safe_push_style_color(ctx, ImGui, ImGui.Col_HeaderHovered, 0x2A323FEE)

  p_cols = p_cols + safe_push_style_color(ctx, ImGui, ImGui.Col_HeaderActive, 0x333D4DEE)

  -- Text colors

  p_cols = p_cols + safe_push_style_color(ctx, ImGui, ImGui.Col_Text, 0xE2E8F0FF)

  p_cols = p_cols + safe_push_style_color(ctx, ImGui, ImGui.Col_TextDisabled, 0x7E8B9BFF)

  -- Separator

  p_cols = p_cols + safe_push_style_color(ctx, ImGui, ImGui.Col_Separator, 0x282E3AEE)

  -- FrameBg for inputs inside modal

  p_cols = p_cols + safe_push_style_color(ctx, ImGui, ImGui.Col_FrameBg, 0x1F242CFF)

  p_cols = p_cols + safe_push_style_color(ctx, ImGui, ImGui.Col_FrameBgHovered, 0x282F3AFF)

  p_cols = p_cols + safe_push_style_color(ctx, ImGui, ImGui.Col_FrameBgActive, 0x313A47FF)



  local p_vars = 0

  if ImGui.StyleVar_PopupRounding then

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_PopupRounding, 8.0)

    p_vars = p_vars + 1

  end

  if ImGui.StyleVar_PopupBorderSize then

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_PopupBorderSize, 1.0)

    p_vars = p_vars + 1

  end

  if ImGui.StyleVar_WindowPadding then

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 10.0, 10.0)

    p_vars = p_vars + 1

  end

  if ImGui.StyleVar_ItemSpacing then

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 8.0, 6.0)

    p_vars = p_vars + 1

  end



  return p_cols, p_vars

end



local function pop_modern_popup_styles(ctx, ImGui, p_cols, p_vars)

  if p_cols and p_cols > 0 then

    ImGui.PopStyleColor(ctx, p_cols)

  end

  if p_vars and p_vars > 0 then

    ImGui.PopStyleVar(ctx, p_vars)

  end

end



-- Helper to render a lightened greyish control container card (separating controls from functional content)

-- Dynamically computes background and border based on user's chosen palette variant (1, 2, or 3) and accent color

local control_box_font_stack = {}

local function begin_control_box(ctx, state, ImGui, str_id, height)

  height = height or 0.0

  local flags = 0

  if height == 0.0 then

    if ImGui.ChildFlags_AutoResizeY then

      flags = flags | ImGui.ChildFlags_AutoResizeY

    end

    if ImGui.ChildFlags_AlwaysAutoResize then

      flags = flags | ImGui.ChildFlags_AlwaysAutoResize

    end

  end

  if ImGui.ChildFlags_AlwaysUseWindowPadding then

    flags = flags | ImGui.ChildFlags_AlwaysUseWindowPadding

  end



  local c = (state and state.accent_color) or { 0.16, 0.55, 0.35 }

  local r, g, b = c[1] or 0.16, c[2] or 0.55, c[3] or 0.35

  local pal = (state and state.control_box_palette) or 1



  local bg_u32, border_u32

  if pal == 1 then

    -- 1: «Графит» (Контрастный нейтральный графитовый фон + акцентная рамка)

    bg_u32 = ImGui.ColorConvertDouble4ToU32(0.12, 0.13, 0.16, 1.0)

    local br_r = math.min(1.0, r * 0.45 + 0.05)

    local br_g = math.min(1.0, g * 0.45 + 0.05)

    local br_b = math.min(1.0, b * 0.45 + 0.05)

    border_u32 = ImGui.ColorConvertDouble4ToU32(br_r, br_g, br_b, 0.55)

  elseif pal == 2 then

    -- 2: «Легкая тонировка» (Едва уловимый благородный оттенок, мягкий - 5%)

    local bg_r = math.min(1.0, 0.12 + r * 0.05)

    local bg_g = math.min(1.0, 0.13 + g * 0.05)

    local bg_b = math.min(1.0, 0.16 + b * 0.05)

    bg_u32 = ImGui.ColorConvertDouble4ToU32(bg_r, bg_g, bg_b, 1.0)

    border_u32 = ImGui.ColorConvertDouble4ToU32(bg_r + 0.08, bg_g + 0.08, bg_b + 0.10, 0.70)

  else

    -- 3: «Умеренная тонировка» (Выраженный стильный оттенок в тон акценту - 10%)

    local bg_r = math.min(1.0, 0.10 + r * 0.10)

    local bg_g = math.min(1.0, 0.11 + g * 0.10)

    local bg_b = math.min(1.0, 0.14 + b * 0.10)

    bg_u32 = ImGui.ColorConvertDouble4ToU32(bg_r, bg_g, bg_b, 1.0)

    border_u32 = ImGui.ColorConvertDouble4ToU32(bg_r + 0.10, bg_g + 0.10, bg_b + 0.12, 0.80)

  end



  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ChildRounding, 6.0)

  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ChildBorderSize, 1.0)

  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 10.0, 8.0)

  ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, bg_u32)

  ImGui.PushStyleColor(ctx, ImGui.Col_Border, border_u32)



  local open = ImGui.BeginChild(ctx, "ctrl_box_" .. str_id, 0.0, height, flags)

  if not open then

    -- ReaImGui C++ wrapper already called ImGui::EndChild() when BeginChild returned false!

    -- Pop styles so parent window stack remains balanced:

    ImGui.PopStyleColor(ctx, 2)

    ImGui.PopStyleVar(ctx, 3)

    return false

  end



  local ui_font = get_or_attach_font(ctx, ImGui, state.text_font_family or "Segoe UI", state.ui_font_size or 11.0)

  local font_pushed = false

  if ui_font and ImGui.PushFont then

    ImGui.PushFont(ctx, ui_font)

    font_pushed = true

  end

  table.insert(control_box_font_stack, font_pushed)



  return true

end



local function end_control_box(ctx, ImGui, was_open)

  if was_open == false then

    return

  end

  local font_pushed = table.remove(control_box_font_stack)

  if font_pushed and ImGui.PopFont then

    ImGui.PopFont(ctx)

  end

  ImGui.EndChild(ctx)

  ImGui.PopStyleColor(ctx, 2)

  ImGui.PopStyleVar(ctx, 3)

  ImGui.Spacing(ctx)

end



-- Render modern thin track slider with accent colored progress, knob, and right-aligned value pill (Mockup 3)

-- Returns: changed (bool), new_value (number)

local function render_modern_slider(ctx, state, ImGui, str_id, current_val, min_v, max_v, format_str, accent_u32, slider_w)

  slider_w = slider_w or 220.0

  format_str = format_str or "%.1f"

  local slider_h = 22.0

  local track_h = 4.0

  local knob_r = 6.0



  local val_str = string.format(format_str, current_val)

  local txt_w, txt_h = ImGui.CalcTextSize(ctx, val_str)

  local badge_pad_x = 8.0

  local badge_pad_y = 3.0

  local badge_w = math.max(38.0, txt_w + badge_pad_x * 2)

  local badge_h = math.max(18.0, txt_h + badge_pad_y * 2)

  local total_w = slider_w + 12.0 + badge_w



  local p_min_x, p_min_y = ImGui.GetCursorScreenPos(ctx)



  -- Use InvisibleButton covering full slider + badge width to guarantee proper bounding box

  local btn_id = "##mslider_" .. str_id

  ImGui.InvisibleButton(ctx, btn_id, total_w, slider_h)

  local is_active = ImGui.IsItemActive(ctx)

  local is_hovered = ImGui.IsItemHovered(ctx)



  local new_val = current_val

  local range = max_v - min_v

  if range <= 0 then range = 1 end



  if is_active then

    local mouse_x, _ = ImGui.GetMousePos(ctx)

    local rel_x = math.max(0.0, math.min(slider_w, mouse_x - p_min_x))

    local ratio = rel_x / slider_w

    new_val = min_v + ratio * range

  end



  -- Clamp fraction

  local frac = math.max(0.0, math.min(1.0, (new_val - min_v) / range))



  local draw_list = ImGui.GetWindowDrawList(ctx)

  local track_center_y = p_min_y + slider_h * 0.5

  local track_top_y = track_center_y - track_h * 0.5

  local track_bottom_y = track_center_y + track_h * 0.5



  -- Full dark background track (after knob) - deep dark groove like Mockup 3

  ImGui.DrawList_AddRectFilled(draw_list, p_min_x, track_top_y, p_min_x + slider_w, track_bottom_y, 0x11141BFF, track_h * 0.5)



  -- Accent filled track (up to knob)

  local knob_center_x = p_min_x + frac * slider_w

  if frac > 0 then

    local fill_col = accent_u32 or 0x3373BFFF

    ImGui.DrawList_AddRectFilled(draw_list, p_min_x, track_top_y, knob_center_x, track_bottom_y, fill_col, track_h * 0.5)

  end



  -- Knob (circle) with soft shadow

  local knob_col = (is_active or is_hovered) and 0xFFFFFFFF or 0xD0D5DDFF

  ImGui.DrawList_AddCircleFilled(draw_list, knob_center_x, track_center_y + 0.5, knob_r, 0x00000055)

  ImGui.DrawList_AddCircleFilled(draw_list, knob_center_x, track_center_y, knob_r, knob_col)



  -- Value display badge on the right (Mockup 3 pill style)

  local updated_val_str = string.format(format_str, new_val)

  local u_txt_w, _ = ImGui.CalcTextSize(ctx, updated_val_str)

  local badge_x = p_min_x + slider_w + 12.0

  local badge_y = track_center_y - badge_h * 0.5



  ImGui.DrawList_AddRectFilled(draw_list, badge_x, badge_y, badge_x + badge_w, badge_y + badge_h, 0x181D26EE, 4.0)

  ImGui.DrawList_AddText(draw_list, badge_x + (badge_w - u_txt_w) * 0.5, badge_y + badge_pad_y, 0xC8D0DCFF, updated_val_str)



  local changed = (math.abs(new_val - current_val) > 0.0001)

  return changed, new_val

end



-- Handle Drag & Drop of subtitle files from File Explorer into ReaImGui targets

function ui.handle_file_drop(ctx, state, ImGui)

  if not ImGui or not ImGui.BeginDragDropTarget or not ImGui.AcceptDragDropPayloadFiles then

    return false

  end



  if ImGui.BeginDragDropTarget(ctx) then

    local rv, count = ImGui.AcceptDragDropPayloadFiles(ctx)

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

            if #state.subtitles > 0 then

              state.pending_filepath = filepath

              state.show_replace_modal = true

            else

              state.load_file(filepath)

              actions.sync_filter_to_timeline(state)

              actions.init_timeline_sync(state)

            end

            break

          end

        end

      end

    end

    ImGui.EndDragDropTarget(ctx)

    return true

  end

  return false

end



-- Helper to draw an actor pill/badge (used in Tab 2 and filter chips)

local function draw_actor_badge(ctx, ImGui, actor, palette, show_border)

  local info = palette and palette[actor]

  local badge_col = (info and info.u32) or 0x888888FF

  local text_col = 0x222222FF -- Dark text on pastel background



  -- If NoActor, softer grey

  if actor == "NoActor" then

    badge_col = 0x55555588

    text_col = 0xEEEEEEFF

  end



  local padding_x = 7.0

  local padding_y = 2.0

  local txt_w, txt_h = ImGui.CalcTextSize(ctx, actor)

  local pos_x = ImGui.GetCursorPosX(ctx)

  local pos_y = ImGui.GetCursorPosY(ctx)



  local p_min_x, p_min_y = ImGui.GetCursorScreenPos(ctx)

  local p_max_x = p_min_x + txt_w + padding_x * 2

  local p_max_y = p_min_y + txt_h + padding_y * 2



  local draw_list = ImGui.GetWindowDrawList(ctx)

  ImGui.DrawList_AddRectFilled(draw_list, p_min_x, p_min_y, p_max_x, p_max_y, badge_col, 4.0)



  if show_border then

    ImGui.DrawList_AddRect(draw_list, p_min_x, p_min_y, p_max_x, p_max_y, 0xFFFFFFFF, 4.0, 0, 1.0)

  end



  ImGui.SetCursorPosX(ctx, pos_x + padding_x)

  ImGui.SetCursorPosY(ctx, pos_y + padding_y)

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, text_col)

  ImGui.Text(ctx, actor)

  ImGui.PopStyleColor(ctx, 1)



  ImGui.Dummy(ctx, 0.0, padding_y)

end



-- Helper to format actor tag according to text settings:

-- mode 1: "Актер"

-- mode 2: "Актер - Персонаж"

-- Checks for "Все" and truncates to max 24 chars with ellipsis "..."

local function format_actor_tag(state, sub)

  if not sub then return "" end



  -- Check if sub has multiple actors or if it represents all actors

  local raw_a = sub.raw_actor or sub.actor or "NoActor"

  if raw_a == "NoActor" then return "" end



  -- If raw_a indicates "Все" or matches all project actors

  local is_all = false

  if raw_a == "Все" or raw_a == "All" or raw_a == "[Все]" or raw_a == "[All]" then

    is_all = true

  elseif state and state.actors and #state.actors > 1 and sub.actors and #sub.actors == #state.actors then

    is_all = true

  end



  if is_all then

    return "Все"

  end



  local display_mode = (state and state.text_actor_display_mode) or 1

  local full_text = ""



  if display_mode == 2 then

    -- Mode 2: "Актер - Персонаж"

    local actor_name = sub.actor or raw_a

    local char_name = sub.character or ""

    if char_name and #char_name > 0 then

      full_text = actor_name .. " - " .. char_name

    else

      -- Check if raw_actor contains dash or brackets with character

      local dash_idx = raw_a:find("[%-%—%–]")

      if dash_idx then

        full_text = raw_a:gsub("^%[", ""):gsub("%]$", "")

      else

        full_text = actor_name

      end

    end

  else

    -- Mode 1 (default): "Актер"

    full_text = sub.actor or raw_a

    full_text = full_text:gsub("^%[", ""):gsub("%]$", "")

  end



  -- Truncate to at most 24 characters (including "...")

  -- UTF-8 safe character counting

  local len = utf8 and utf8.len and utf8.len(full_text) or #full_text

  if len > 24 then

    if utf8 and utf8.offset then

      local byte_pos = utf8.offset(full_text, 22) -- 21 chars + "..."

      if byte_pos then

        full_text = full_text:sub(1, byte_pos - 1) .. "..."

      else

        full_text = full_text:sub(1, 21) .. "..."

      end

    else

      full_text = full_text:sub(1, 21) .. "..."

    end

  end



  return full_text

end



-- Commit any active note text edit session (Undo snapshot, project save, timeline sync, release focus)

local function commit_note_edit(ctx, state, ImGui)

  if not state then return end

  state._note_field_active = false

  state._note_is_editing = false

end



-- Render View Mode segmented control: [квадратик с полоской / квадратик с тремя полосками] in a rounded pill frame

-- Soft graphite in standard mode, and very dark, muted & non-distracting in focus mode.

local function render_view_mode_segmented_toggle(ctx, state, ImGui, target_x, is_focus_mode)

  if ImGui.GetCursorPosX(ctx) < target_x then

    ImGui.SameLine(ctx, target_x)

  else

    ImGui.SameLine(ctx, 0, 6.0)

  end



  local total_w = 60.0

  local total_h = 30.0

  local seg_w = total_w * 0.5

  local is_note_active = (state.view_mode == "note")

  local is_table_active = not is_note_active



  local start_x, start_y = ImGui.GetCursorScreenPos(ctx)

  local draw_list = ImGui.GetWindowDrawList(ctx)



  -- Outer container background and rounded frame (subtle in focus mode)

  local frame_bg = is_focus_mode and 0x14161C55 or 0x181C24CC

  local border_col = is_focus_mode and 0x24283244 or 0x36405088

  ImGui.DrawList_AddRectFilled(draw_list, start_x, start_y, start_x + total_w, start_y + total_h, frame_bg, 5.0)



  -- Segment 1 (Left): Note Mode [квадратик с одной полоской]

  ImGui.SetCursorScreenPos(ctx, start_x, start_y)

  local left_clicked = ImGui.InvisibleButton(ctx, "###view_mode_seg_note", seg_w, total_h)

  local left_hovered = ImGui.IsItemHovered(ctx)



  -- Segment 2 (Right): Table Mode [квадратик с тремя полосками]

  ImGui.SetCursorScreenPos(ctx, start_x + seg_w, start_y)

  local right_clicked = ImGui.InvisibleButton(ctx, "###view_mode_seg_table", seg_w, total_h)

  local right_hovered = ImGui.IsItemHovered(ctx)



  -- Draw active highlight on the active segment:

  if is_focus_mode then

    -- FOCUS MODE: Heavily muted, dark, non-distracting

    if is_note_active then

      local hl_col = left_hovered and 0x2D354488 or 0x22273266

      local round_flag = ImGui.DrawFlags_RoundCornersLeft or 0

      ImGui.DrawList_AddRectFilled(draw_list, start_x, start_y, start_x + seg_w, start_y + total_h, hl_col, 5.0, round_flag)

    elseif left_hovered then

      local hl_col = 0xFFFFFF0E

      local round_flag = ImGui.DrawFlags_RoundCornersLeft or 0

      ImGui.DrawList_AddRectFilled(draw_list, start_x, start_y, start_x + seg_w, start_y + total_h, hl_col, 5.0, round_flag)

    end



    if is_table_active then

      local hl_col = right_hovered and 0x2D354488 or 0x22273266

      local round_flag = ImGui.DrawFlags_RoundCornersRight or 0

      ImGui.DrawList_AddRectFilled(draw_list, start_x + seg_w, start_y, start_x + total_w, start_y + total_h, hl_col, 5.0, round_flag)

    elseif right_hovered then

      local hl_col = 0xFFFFFF0E

      local round_flag = ImGui.DrawFlags_RoundCornersRight or 0

      ImGui.DrawList_AddRectFilled(draw_list, start_x + seg_w, start_y, start_x + total_w, start_y + total_h, hl_col, 5.0, round_flag)

    end

  else

    -- STANDARD MODE: Soft graphite / slate

    if is_note_active then

      local hl_col = left_hovered and 0x364052DD or 0x2A3240CC

      local round_flag = ImGui.DrawFlags_RoundCornersLeft or 0

      ImGui.DrawList_AddRectFilled(draw_list, start_x, start_y, start_x + seg_w, start_y + total_h, hl_col, 5.0, round_flag)

    elseif left_hovered then

      local hl_col = 0xFFFFFF14

      local round_flag = ImGui.DrawFlags_RoundCornersLeft or 0

      ImGui.DrawList_AddRectFilled(draw_list, start_x, start_y, start_x + seg_w, start_y + total_h, hl_col, 5.0, round_flag)

    end



    if is_table_active then

      local hl_col = right_hovered and 0x364052DD or 0x2A3240CC

      local round_flag = ImGui.DrawFlags_RoundCornersRight or 0

      ImGui.DrawList_AddRectFilled(draw_list, start_x + seg_w, start_y, start_x + total_w, start_y + total_h, hl_col, 5.0, round_flag)

    elseif right_hovered then

      local hl_col = 0xFFFFFF14

      local round_flag = ImGui.DrawFlags_RoundCornersRight or 0

      ImGui.DrawList_AddRectFilled(draw_list, start_x + seg_w, start_y, start_x + total_w, start_y + total_h, hl_col, 5.0, round_flag)

    end

  end



  -- Center vertical divider between segments

  local div_x = start_x + seg_w

  local div_col = is_focus_mode and 0x2A303A33 or 0x444E5E55

  ImGui.DrawList_AddLine(draw_list, div_x, start_y + 4.0, div_x, start_y + total_h - 4.0, div_col, 1.0)



  -- Outer border

  ImGui.DrawList_AddRect(draw_list, start_x, start_y, start_x + total_w, start_y + total_h, border_col, 5.0, 0, 1.2)



  -- Draw Left Icon: Square with 1 line (Note Mode)

  local note_icon_col = 0x7E8B9ECC

  if is_focus_mode then

    note_icon_col = is_note_active and 0x8FA0B8AA or (left_hovered and 0xB0BCCCAA or 0x444B5888)

  else

    note_icon_col = is_note_active and 0xF0F4F8FF or (left_hovered and 0xDDE4EEFF or 0x7E8B9ECC)

  end



  local l_cx = math.floor(start_x + seg_w * 0.5)

  local l_cy = math.floor(start_y + total_h * 0.5)

  local box_sz = 14.0

  local h_sz = box_sz * 0.5

  local lx1 = l_cx - h_sz

  local ly1 = l_cy - h_sz

  local lx2 = l_cx + h_sz

  local ly2 = l_cy + h_sz

  ImGui.DrawList_AddRect(draw_list, lx1, ly1, lx2, ly2, note_icon_col, 2.0, 0, 1.2)

  local l_line_h = 2.0

  ImGui.DrawList_AddRectFilled(draw_list, lx1 + 2.5, l_cy - l_line_h * 0.5, lx2 - 2.5, l_cy + l_line_h * 0.5, note_icon_col, 0.6)



  -- Draw Right Icon: Square with 3 lines (Table Mode)

  local tbl_icon_col = 0x7E8B9ECC

  if is_focus_mode then

    tbl_icon_col = is_table_active and 0x8FA0B8AA or (right_hovered and 0xB0BCCCAA or 0x444B5888)

  else

    tbl_icon_col = is_table_active and 0xF0F4F8FF or (right_hovered and 0xDDE4EEFF or 0x7E8B9ECC)

  end



  local r_cx = math.floor(start_x + seg_w + seg_w * 0.5)

  local r_cy = math.floor(start_y + total_h * 0.5)

  local rx1 = r_cx - h_sz

  local ry1 = r_cy - h_sz

  local rx2 = r_cx + h_sz

  local ry2 = r_cy + h_sz

  ImGui.DrawList_AddRect(draw_list, rx1, ry1, rx2, ry2, tbl_icon_col, 2.0, 0, 1.2)

  local t_line_h = 1.2

  local y_gap = 3.2

  ImGui.DrawList_AddRectFilled(draw_list, rx1 + 2.5, r_cy - y_gap - t_line_h * 0.5, rx2 - 2.5, r_cy - y_gap + t_line_h * 0.5, tbl_icon_col, 0.5)

  ImGui.DrawList_AddRectFilled(draw_list, rx1 + 2.5, r_cy - t_line_h * 0.5, rx2 - 2.5, r_cy + t_line_h * 0.5, tbl_icon_col, 0.5)

  ImGui.DrawList_AddRectFilled(draw_list, rx1 + 2.5, r_cy + y_gap - t_line_h * 0.5, rx2 - 2.5, r_cy + y_gap + t_line_h * 0.5, tbl_icon_col, 0.5)



  if left_clicked and not is_note_active then

    commit_note_edit(ctx, state, ImGui)

    state.view_mode = "note"

    state.save_settings()

  end

  if right_clicked and not is_table_active then

    commit_note_edit(ctx, state, ImGui)

    state.view_mode = "table"

    state.save_settings()

  end



  if left_hovered then

    set_tooltip(ctx, state, ImGui, "Режим Note (одна строка для озвучки)")

  elseif right_hovered then

    set_tooltip(ctx, state, ImGui, "Режим таблицы (список строк)")

  end

end



-- Word-style font size input with numeric typing & dropdown preset selection

local function render_font_size_selector(ctx, state, ImGui)

  local cur_val = math.floor((state.note_edit_font_size or 20.0) + 0.5)

  local str_val = tostring(cur_val)



  ImGui.AlignTextToFramePadding(ctx)

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x8892B0CC)

  ImGui.Text(ctx, "Размер текста:")

  ImGui.PopStyleColor(ctx, 1)

  ImGui.SameLine(ctx, 0, 6.0)



  -- Input box for typing

  ImGui.SetNextItemWidth(ctx, 36.0)

  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 4.0)

  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0x1A202AEE)

  ImGui.PushStyleColor(ctx, ImGui.Col_Border, 0x445062CC)

  local changed, new_str = ImGui.InputText(ctx, "###note_font_sz_input", state._note_font_sz_input_buf or str_val, ImGui.InputTextFlags_CharsDecimal or 0)

  if ImGui.IsItemActive and ImGui.IsItemActive(ctx) then

    state._note_font_sz_active = true

  end

  if changed then

    state._note_font_sz_input_buf = new_str

    local num = tonumber(new_str)

    if num and num >= 8 and num <= 96 then

      state.note_edit_font_size = num

      state.save_settings()

    end

  end

  if ImGui.IsItemDeactivated and ImGui.IsItemDeactivated(ctx) then

    state._note_font_sz_input_buf = nil

    state._note_font_sz_active = false

  end



  -- Dropdown button

  ImGui.SameLine(ctx, 0, 2.0)

  if ImGui.Button(ctx, "▼###note_font_sz_combo_btn", 22.0, 0.0) then

    ImGui.OpenPopup(ctx, "###note_font_sz_popup")

  end

  if ImGui.IsItemHovered(ctx) then

    set_tooltip(ctx, state, ImGui, "Размер редактируемого текста\nВыберите из списка или введите любое число")

  end



  if ImGui.BeginPopup(ctx, "###note_font_sz_popup") then

    local sizes = { 12, 14, 16, 18, 20, 22, 24, 28, 32, 36, 40, 48, 64 }

    for _, sz in ipairs(sizes) do

      if ImGui.Selectable(ctx, tostring(sz), sz == cur_val) then

        state.note_edit_font_size = sz

        state._note_font_sz_input_buf = nil

        state.save_settings()

      end

    end

    ImGui.EndPopup(ctx)

  end

  ImGui.PopStyleColor(ctx, 2)

  ImGui.PopStyleVar(ctx, 1)

end



-- Helper: wrap text into lines at word boundaries given max pixel width

local function wrap_text_into_lines(ctx, ImGui, text, max_w)

  if not text or #text == 0 then return {} end

  if not max_w or max_w <= 10.0 then return { text } end



  local lines = {}

  for raw_line in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do

    if raw_line == "" then

      table.insert(lines, "")

    else

      local tw, _ = ImGui.CalcTextSize(ctx, raw_line)

      if tw <= max_w then

        table.insert(lines, raw_line)

      else

        local trailing_spaces = raw_line:match("(%s+)$") or ""

        local cur_line = ""

        for word in raw_line:gmatch("%S+") do

          local test_line = (cur_line == "") and word or (cur_line .. " " .. word)

          local w_len, _ = ImGui.CalcTextSize(ctx, test_line)

          if w_len <= max_w or cur_line == "" then

            cur_line = test_line

          else

            table.insert(lines, cur_line)

            cur_line = word

          end

        end

        if cur_line ~= "" then

          table.insert(lines, cur_line .. trailing_spaces)

        end

      end

    end

  end

  if #lines > 0 and lines[#lines] == "" and text:sub(-1) ~= "\n" and text:sub(-1) ~= "\r" then

    table.remove(lines)

  end

  if #lines == 0 then table.insert(lines, text) end

  return lines

end



-- Helper: wrap text by words into a multi-line string joined with newlines

local function wrap_text_by_words(ctx, ImGui, text, max_w)

  if not text or #text == 0 then return "" end

  if not max_w or max_w <= 20.0 then return text end



  local lines = wrap_text_into_lines(ctx, ImGui, text, max_w)

  return table.concat(lines, "\n")

end



-- Helper: find previous and next subtitle index relative to cur_time

local function find_surrounding_sub_indices(subs, cur_time)

  local prev_i = nil

  local next_i = nil

  for i, s in ipairs(subs) do

    if s.start_time and s.start_time > cur_time then

      next_i = i

      break

    end

    prev_i = i

  end

  return prev_i, next_i

end



-- Render Note View (SWS Notes-style single line mode with huge dynamic font,

-- true geometric center alignment, proportional actor header with full-width divider line,

-- SWS-style editable text field in non-focus mode, and disabled field during gaps)

function ui.render_note_view(ctx, state, ImGui, is_focus_mode)

  local child_bg_pushed = 0

  if #state.subtitles > 0 then

    local win_bg_col = 0x14171CFF

    if ImGui.GetStyleColor and ImGui.Col_WindowBg then

      local ok_sc, sc = pcall(ImGui.GetStyleColor, ctx, ImGui.Col_WindowBg)

      if ok_sc and sc and sc ~= 0 then

        win_bg_col = (sc | 0xFF)

      end

    end

    ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, win_bg_col)

    child_bg_pushed = 1

  end



  local child_flags = (ImGui.WindowFlags_NoScrollbar or 0) | (ImGui.WindowFlags_NoScrollWithMouse or 0)

  if ImGui.BeginChild(ctx, "NoteViewScrollArea", 0, 0, 0, child_flags) then

    ui.handle_file_drop(ctx, state, ImGui)



    local filtered_subs = state.get_filtered_subtitles()

    local subs_to_use = (state.sync_with_filter and filtered_subs) or state.subtitles



    local avail_w, avail_h = ImGui.GetContentRegionAvail(ctx)

    local start_x, start_y = ImGui.GetCursorScreenPos(ctx)

    local draw_list = ImGui.GetWindowDrawList(ctx)



    if not subs_to_use or #subs_to_use == 0 then

      if is_focus_mode and state.focus_watermark_geo and watermark and watermark.draw_focus then

        local geo = state.focus_watermark_geo

        watermark.draw_focus(ctx, ImGui, geo.cx, geo.cy, geo.size, draw_list, 0.045)

      else

        local empty_msg = (#state.subtitles == 0)

          and "Субтитры отсутствуют. Перетащите файл .ass / .srt в это окно."

          or "Нет субтитров, подходящих под выбранный фильтр."

        local ew, eh = ImGui.CalcTextSize(ctx, empty_msg)

        ImGui.SetCursorScreenPos(ctx, start_x + math.max(0.0, (avail_w - ew) * 0.5), start_y + math.max(0.0, (avail_h - eh) * 0.5))

        ImGui.TextDisabled(ctx, empty_msg)

      end

    else

      local cur_time = 0

      local is_playing = false

      if reaper then

        local ps = reaper.GetPlayState()

        is_playing = (ps & 1) ~= 0

        cur_time = is_playing and reaper.GetPlayPosition() or reaper.GetCursorPosition()

      end



      local eff_hold_mode = 1

      if state.text_sync_overlay_hold then

        eff_hold_mode = state.overlay_hold_mode or 2

      end



      if not state._note_live_trk then

        state._note_live_trk = {

          was_playing = false,

          last_play_pos = 0.0,

          active_idx = nil,

          active_v_end = 0.0,

          current_drift = 0.0,

        }

      end



      local fixed_lead_in = (state.text_fixed_lead_in == true)

      local lead_in = state.text_lead_in_time or 0.35

      local p_idx, u_idx, pr_idx, is_ot, drift_val = overlay.eval_active_sub(

        subs_to_use,

        cur_time,

        is_playing,

        eff_hold_mode,

        state.overlay_target_cps or 17.0,

        state.overlay_max_hold or 0.7,

        state.overlay_max_drift or 2.5,

        state._note_live_trk,

        lead_in,

        fixed_lead_in

      )



      local active_sub = nil

      local active_idx = nil

      if p_idx and subs_to_use[p_idx] then

        active_sub = subs_to_use[p_idx]

        active_idx = p_idx

        state.active_sub_idx = active_idx

        state.selected_real_sub_idx = state.find_subtitle_index(active_sub) or active_idx

      elseif u_idx and subs_to_use[u_idx] then

        active_sub = subs_to_use[u_idx]

        active_idx = u_idx

        state.active_sub_idx = active_idx

        state.selected_real_sub_idx = state.find_subtitle_index(active_sub) or active_idx

      end



      local active_real_idx = (active_sub and (state.find_subtitle_index(active_sub) or active_idx)) or nil

      state._note_current_active_sub_idx = active_real_idx



      -- Geometry calculation

      local nav_btn_w = 40.0

      local center_x = start_x + nav_btn_w

      local center_w = math.max(100.0, avail_w - (nav_btn_w * 2.0))

      local show_note_prog = (state.note_show_progress ~= false)

      local max_text_w = math.max(60.0, center_w - 32.0)

      local max_text_h = math.max(40.0, avail_h - (show_note_prog and 84.0 or 70.0))



      local raw_text = active_sub and parser.strip_invisible_unicode(active_sub.text) or ""

      local min_sz = state.note_min_font_size or 18.0

      local max_sz = state.note_max_font_size or 72.0

      local auto_wrap = (state.note_auto_wrap ~= false)



      -- Font scaling calculation based on available space

      local chosen_sz = min_sz

      if active_sub and #raw_text > 0 then

        local base_w, base_h = ImGui.CalcTextSize(ctx, raw_text)

        base_w = math.max(1.0, base_w)



        local ideal_single = math.floor(14.0 * (max_text_w / base_w))

        ideal_single = math.min(ideal_single, math.floor(max_text_h * 0.70))



        if not auto_wrap then

          chosen_sz = math.max(min_sz, math.min(max_sz, ideal_single))

        else

          if ideal_single >= 32.0 then

            chosen_sz = math.min(max_sz, ideal_single)

          else

            local ideal_2 = math.floor(14.0 * ((max_text_w * 1.85) / base_w))

            ideal_2 = math.min(ideal_2, math.floor(max_text_h * 0.38))

            if ideal_2 >= 24.0 then

              chosen_sz = math.max(min_sz, math.min(max_sz, ideal_2))

            else

              local ideal_3 = math.floor(14.0 * ((max_text_w * 2.75) / base_w))

              ideal_3 = math.min(ideal_3, math.floor(max_text_h * 0.26))

              chosen_sz = math.max(min_sz, math.min(max_sz, ideal_3))

            end

          end

        end

        chosen_sz = math.max(min_sz, math.min(max_sz, chosen_sz))

      end



      -- Top actor strip with subtle dividing line (hidden when actor is NoActor or empty)

      local raw_actor_name = active_sub and (active_sub.raw_actor or active_sub.actor) or ""

      local clean_actor_name = raw_actor_name:match("^%s*(.-)%s*$") or ""

      local is_no_actor = (clean_actor_name == "" or clean_actor_name:lower() == "noactor" or (active_sub and active_sub.actor and active_sub.actor:lower() == "noactor"))

      local show_actor_header = active_sub and (state.note_show_actor ~= false) and not is_no_actor



      local actor_sz = math.floor(math.min(avail_w * 0.045, avail_h * 0.09))

      actor_sz = math.max(14.0, math.min(32.0, actor_sz))

      local actor_header_h = show_actor_header and math.max(32.0, actor_sz + 12.0) or 0.0

      local body_offset_y = actor_header_h + (show_actor_header and 1.0 or 0.0)

      local div_y = start_y + actor_header_h



      if show_actor_header then

        local badge_actor = (active_sub.raw_actor and #active_sub.raw_actor > 0) and active_sub.raw_actor or active_sub.actor

        local act_pal = state.actor_palette and (state.actor_palette[badge_actor] or (active_sub.actor and state.actor_palette[active_sub.actor]))

        local act_col = (act_pal and act_pal.u32) or 0x8892B0FF



        local actor_text = "[" .. badge_actor .. "]"

        local actor_font = get_or_attach_font(ctx, ImGui, state.text_font_family, actor_sz)

        local a_pushed = false

        if actor_font and ImGui.PushFont then

          ImGui.PushFont(ctx, actor_font)

          a_pushed = true

        end

        local atw, ath = ImGui.CalcTextSize(ctx, actor_text)

        local at_y = math.floor(start_y + (actor_header_h - ath) * 0.5)

        ImGui.DrawList_AddText(draw_list, start_x + 16.0, at_y, act_col, actor_text)

        if a_pushed then

          ImGui.PopFont(ctx)

        end



        -- Thin separating line across full width

        local div_col = 0x3E455466

        ImGui.DrawList_AddLine(draw_list, start_x, div_y, start_x + avail_w, div_y, div_col, 1.0)

      end



      -- Content body area below actor strip

      local body_y = start_y + body_offset_y

      local body_h = math.max(10.0, avail_h - body_offset_y)



      -- Left navigation strip (Previous subtitle)

      ImGui.SetCursorPos(ctx, 0.0, body_offset_y)

      local left_clicked = ImGui.InvisibleButton(ctx, "###note_nav_prev_btn", nav_btn_w, body_h)

      local left_hovered = ImGui.IsItemHovered(ctx)

      local left_active = ImGui.IsItemActive and ImGui.IsItemActive(ctx)



      if left_hovered or left_active then

        local bg_alpha = left_active and 0x28 or 0x14

        local bg_col = (0xFFFFFF00) | bg_alpha

        ImGui.DrawList_AddRectFilled(draw_list, start_x, body_y, start_x + nav_btn_w, body_y + body_h, bg_col, 4.0)

      end



      local l_arrow_col = (left_hovered or left_active) and 0xFFFFFFCC or 0x8892B038

      local l_mid_x = start_x + nav_btn_w * 0.5

      local l_mid_y = body_y + body_h * 0.5

      ImGui.DrawList_AddLine(draw_list, l_mid_x + 4.0, l_mid_y - 10.0, l_mid_x - 3.0, l_mid_y, l_arrow_col, 2.0)

      ImGui.DrawList_AddLine(draw_list, l_mid_x - 3.0, l_mid_y, l_mid_x + 4.0, l_mid_y + 10.0, l_arrow_col, 2.0)



      if left_hovered then

        set_tooltip(ctx, state, ImGui, "Предыдущая строка (Колесо мыши вверх)")

      end



      if left_clicked then

        local prev_target = 1

        if active_idx and active_idx > 1 then

          prev_target = active_idx - 1

        else

          local pi, _ = find_surrounding_sub_indices(subs_to_use, cur_time)

          if pi then prev_target = pi end

        end

        if subs_to_use[prev_target] and subs_to_use[prev_target].start_time and actions and actions.jump_to_time then

          actions.jump_to_time(subs_to_use[prev_target].start_time)

          state.active_sub_idx = prev_target

          state.selected_real_sub_idx = state.find_subtitle_index(subs_to_use[prev_target]) or prev_target

        end

      end



      -- Right navigation strip (Next subtitle)

      ImGui.SetCursorPos(ctx, avail_w - nav_btn_w, body_offset_y)

      local right_clicked = ImGui.InvisibleButton(ctx, "###note_nav_next_btn", nav_btn_w, body_h)

      local right_hovered = ImGui.IsItemHovered(ctx)

      local right_active = ImGui.IsItemActive and ImGui.IsItemActive(ctx)



      if right_hovered or right_active then

        local bg_alpha = right_active and 0x28 or 0x14

        local bg_col = (0xFFFFFF00) | bg_alpha

        ImGui.DrawList_AddRectFilled(draw_list, start_x + avail_w - nav_btn_w, body_y, start_x + avail_w, body_y + body_h, bg_col, 4.0)

      end



      local r_arrow_col = (right_hovered or right_active) and 0xFFFFFFCC or 0x8892B038

      local r_mid_x = start_x + avail_w - nav_btn_w * 0.5

      local r_mid_y = body_y + body_h * 0.5

      ImGui.DrawList_AddLine(draw_list, r_mid_x - 4.0, r_mid_y - 10.0, r_mid_x + 3.0, r_mid_y, r_arrow_col, 2.0)

      ImGui.DrawList_AddLine(draw_list, r_mid_x + 3.0, r_mid_y, r_mid_x - 4.0, r_mid_y + 10.0, r_arrow_col, 2.0)



      if right_hovered then

        set_tooltip(ctx, state, ImGui, "Следующая строка (Колесо мыши вниз)")

      end



      if right_clicked then

        local next_target = #subs_to_use

        if active_idx and active_idx < #subs_to_use then

          next_target = active_idx + 1

        else

          local _, ni = find_surrounding_sub_indices(subs_to_use, cur_time)

          if ni then next_target = ni end

        end

        if subs_to_use[next_target] and subs_to_use[next_target].start_time and actions and actions.jump_to_time then

          actions.jump_to_time(subs_to_use[next_target].start_time)

          state.active_sub_idx = next_target

          state.selected_real_sub_idx = state.find_subtitle_index(subs_to_use[next_target]) or next_target

        end

      end



      -- Mouse wheel navigation over child window

      if ImGui.IsWindowHovered(ctx) then

        local mw = ImGui.GetMouseWheel and ImGui.GetMouseWheel(ctx) or 0

        if mw > 0.05 then

          local prev_target = 1

          if active_idx and active_idx > 1 then

            prev_target = active_idx - 1

          else

            local pi, _ = find_surrounding_sub_indices(subs_to_use, cur_time)

            if pi then prev_target = pi end

          end

          if subs_to_use[prev_target] and subs_to_use[prev_target].start_time and actions and actions.jump_to_time then

            actions.jump_to_time(subs_to_use[prev_target].start_time)

            state.active_sub_idx = prev_target

            state.selected_real_sub_idx = state.find_subtitle_index(subs_to_use[prev_target]) or prev_target

          end

        elseif mw < -0.05 then

          local next_target = #subs_to_use

          if active_idx and active_idx < #subs_to_use then

            next_target = active_idx + 1

          else

            local _, ni = find_surrounding_sub_indices(subs_to_use, cur_time)

            if ni then next_target = ni end

          end

          if subs_to_use[next_target] and subs_to_use[next_target].start_time and actions and actions.jump_to_time then

            actions.jump_to_time(subs_to_use[next_target].start_time)

            state.active_sub_idx = next_target

            state.selected_real_sub_idx = state.find_subtitle_index(subs_to_use[next_target]) or next_target

          end

        end

      end



      -- Bottom subtle timeline metadata: row index & time interval, plus optional progress bar and hold timer

      if active_sub then

        local show_progress = (state.note_show_progress ~= false)

        local bar_h = 3.5

        local bar_y2 = body_y + body_h - 7.0

        local bar_y1 = bar_y2 - bar_h

        local bar_x1 = center_x + 12.0

        local bar_x2 = center_x + center_w - 12.0

        local bar_w = math.max(10.0, bar_x2 - bar_x1)



        local t_start = parser.format_time(active_sub.start_time or 0)

        local t_end = parser.format_time(active_sub.end_time or 0)

        local meta_text = string.format("%d / %d  •  [%s - %s]", active_idx or 1, #subs_to_use, t_start, t_end)

        local meta_font = get_or_attach_font(ctx, ImGui, state.text_font_family, 13.0)

        local m_pushed = false

        if meta_font and ImGui.PushFont then

          ImGui.PushFont(ctx, meta_font)

          m_pushed = true

        end

        local mw, mh = ImGui.CalcTextSize(ctx, meta_text)

        local mx = center_x + (center_w - mw) * 0.5

        local my = show_progress and (bar_y1 - mh - 4.0) or (body_y + body_h - mh - 6.0)

        ImGui.DrawList_AddText(draw_list, mx, my, 0x667788AA, meta_text)



        if show_progress then

          -- Background track

          ImGui.DrawList_AddRectFilled(draw_list, bar_x1, bar_y1, bar_x2, bar_y2, 0x00000055, 2.0)



          local dur = math.max(0.001, (active_sub.end_time or 0) - (active_sub.start_time or 0))

          local progress = math.min(1.0, math.max(0.0, (cur_time - (active_sub.start_time or 0)) / dur))

          local is_holding = (is_ot == true) or (is_playing and (cur_time > (active_sub.end_time or 0)))



          if is_holding then

            -- Full amber bar during hold / overtime

            local hold_col = 0xF59E0BEE

            ImGui.DrawList_AddRectFilled(draw_list, bar_x1, bar_y1, bar_x2, bar_y2, hold_col, 2.0)



            -- Hold timer text (+X.Xs) right-aligned above the bar

            local hold_dur = (drift_val and drift_val > 0.05) and drift_val or math.max(0.0, cur_time - (active_sub.end_time or 0))

            local hold_txt = string.format("+%.1fs", hold_dur)

            local ht_w, ht_h = ImGui.CalcTextSize(ctx, hold_txt)

            local txt_x = bar_x2 - ht_w

            local txt_y = bar_y1 - ht_h - 2.0

            ImGui.DrawList_AddText(draw_list, txt_x, txt_y, 0xF59E0BFF, hold_txt)

          else

            local fill_w = bar_w * progress

            if fill_w > 1.0 then

              local bar_col = 0xFFFFFF99

              local actor_name = active_sub.actor or "NoActor"

              local pal = state.actor_palette and state.actor_palette[actor_name]

              if pal and actor_name ~= "NoActor" then

                bar_col = ImGui.ColorConvertDouble4ToU32(pal.r, pal.g, pal.b, 0.85)

              elseif state.accent_color then

                bar_col = ImGui.ColorConvertDouble4ToU32(state.accent_color[1] or 0.2, state.accent_color[2] or 0.6, state.accent_color[3] or 1.0, 0.85)

              end

              ImGui.DrawList_AddRectFilled(draw_list, bar_x1, bar_y1, bar_x1 + fill_w, bar_y2, bar_col, 2.0)

            end

          end

        end



        if m_pushed then

          ImGui.PopFont(ctx)

        end

      end



      -- Presentation Text: Center aligned horizontally and vertically

      if active_sub and #raw_text > 0 then

        local f = find_closest_font(state.text_font_family, chosen_sz)

        local font_pushed = false

        if f and ImGui.PushFont then

          ImGui.PushFont(ctx, f)

          font_pushed = true

        end



        local lines = auto_wrap and wrap_text_into_lines(ctx, ImGui, raw_text, max_text_w) or { raw_text }

        local line_h = 0

        local line_widths = {}

        for i, line_str in ipairs(lines) do

          local lw, lh = ImGui.CalcTextSize(ctx, line_str)

          line_widths[i] = lw

          if lh > line_h then line_h = lh end

        end

        line_h = math.max(12.0, line_h)

        local line_gap = math.floor(line_h * 0.18)

        local total_text_h = (#lines * line_h) + math.max(0, (#lines - 1) * line_gap)



        local center_cx = center_x + center_w * 0.5

        local center_cy = body_y + (body_h - (show_note_prog and 36.0 or 20.0)) * 0.5

        local start_text_y = math.floor(center_cy - total_text_h * 0.5)



        local txt_col = 0xFFFFFFFF

        if state.text_custom_color then

          local cr = math.floor((state.text_custom_color[1] or 1.0) * 255)

          local cg = math.floor((state.text_custom_color[2] or 1.0) * 255)

          local cb = math.floor((state.text_custom_color[3] or 1.0) * 255)

          txt_col = (cr << 24) | (cg << 16) | (cb << 8) | 0xFF

        end



        for i, line_str in ipairs(lines) do

          local lw = line_widths[i] or 0

          local lx = math.floor(center_cx - lw * 0.5)

          local ly = start_text_y + (i - 1) * (line_h + line_gap)

          ImGui.DrawList_AddText(draw_list, lx, ly, txt_col, line_str)

        end



        if font_pushed then

          ImGui.PopFont(ctx)

        end

      else

        -- No line currently playing / displayed: show semi-transparent acorn outline watermark

        if is_focus_mode and state.focus_watermark_geo and watermark and watermark.draw_focus then

          local geo = state.focus_watermark_geo

          watermark.draw_focus(ctx, ImGui, geo.cx, geo.cy, geo.size, draw_list, 0.045)

        end

      end

    end



    ImGui.EndChild(ctx)

  end



  if child_bg_pushed > 0 then

    ImGui.PopStyleColor(ctx, child_bg_pushed)

  end



  ui.handle_file_drop(ctx, state, ImGui)

end



-- Render Subtitles List (used in both standard tab and full-height focus mode)

function ui.render_subtitles_list(ctx, state, ImGui, is_focus_mode)

  if is_focus_mode and state.view_mode == "note" then

    ui.render_note_view(ctx, state, ImGui, true)

    return

  end



  local filtered_subs = state.get_filtered_subtitles()

  local single_actor_selected = (#state.selected_actors == 1)



  local cur_time = 0

  if reaper then

    cur_time = reaper.GetPlayState() == 0 and reaper.GetCursorPosition() or reaper.GetPlayPosition()

  end



  local lead_in = state.text_lead_in_time or 0.35

  local now_precise = (reaper and reaper.time_precise()) or 0



  -- Delta time calculation for smooth scrolling

  local dt = 0.016

  if state.last_frame_time and state.last_frame_time > 0 then

    dt = math.max(0.001, math.min(0.1, now_precise - state.last_frame_time))

  end

  state.last_frame_time = now_precise



  local font_family = state.text_font_family or "Segoe UI"

  local base_size = math.max(10, math.floor(state.text_font_size or 18))

  local active_size = math.max(10, math.floor(base_size * (state.text_active_font_scale or 1.18)))



  local font_normal = get_or_attach_font(ctx, ImGui, font_family, base_size)

  local font_active = (state.text_active_larger and active_size ~= base_size)

                      and get_or_attach_font(ctx, ImGui, font_family, active_size)

                      or font_normal



  local highlight_b = state.text_highlight_brightness or 0.28



  local filter_changed = false

  if state._applied_filter_revision ~= state.filter_revision then

    state._applied_filter_revision = state.filter_revision

    filter_changed = true

    state._ui_live_trk = nil

    state.last_centered_idx = -1

    state.need_calc_scroll_target = true

    state.suppress_autoscroll_until = 0

  end



  -- 1. Identify current playing and upcoming (lead-in) subtitle using overlay evaluator

  local current_playing_idx = nil

  local upcoming_idx = nil

  local is_holding_current = false

  local hold_time_sec = 0.0

  local best_idx = nil



  local num_f = #filtered_subs

  if num_f > 0 then

    local is_reaper_playing = reaper and ((reaper.GetPlayState() & 1) ~= 0)

    local eff_hold_mode = 1

    if state.text_sync_overlay_hold ~= false and state.overlay_hold_mode and state.overlay_hold_mode > 1 then

      eff_hold_mode = state.overlay_hold_mode

    end



    if not state._ui_live_trk then

      state._ui_live_trk = {

        last_play_pos = 0.0,

        was_playing = false,

        active_idx = nil,

        active_v_start = 0.0,

        active_v_end = 0.0,

        current_drift = 0.0,

      }

    end



    local fixed_lead_in = (state.text_fixed_lead_in == true)

    local p_idx, u_idx, pr_idx, is_ot, drift_val = overlay.eval_active_sub(

      filtered_subs,

      cur_time,

      is_reaper_playing,

      eff_hold_mode,

      state.overlay_target_cps or 17.0,

      state.overlay_max_hold or 0.7,

      state.overlay_max_drift or 2.5,

      state._ui_live_trk,

      lead_in,

      fixed_lead_in

    )



    if p_idx then

      current_playing_idx = p_idx

      best_idx = p_idx

      if is_ot then

        is_holding_current = true

        hold_time_sec = drift_val

      end

    elseif pr_idx then

      best_idx = pr_idx

    end



    if u_idx then

      upcoming_idx = u_idx

    end

  end



  -- 2. Update active_sub_idx:

  if current_playing_idx then

    state.active_sub_idx = current_playing_idx

    state.selected_real_sub_idx = state.find_subtitle_index(filtered_subs[current_playing_idx])

  elseif upcoming_idx then

    state.active_sub_idx = upcoming_idx

    state.selected_real_sub_idx = state.find_subtitle_index(filtered_subs[upcoming_idx])

  else

    local keep_active = false

    if not filter_changed and state.active_sub_idx and filtered_subs[state.active_sub_idx] then

      local cur_sub = filtered_subs[state.active_sub_idx]

      local next_sub = filtered_subs[state.active_sub_idx + 1]

      local is_fixed = (state.text_fixed_lead_in == true)

      local next_threshold = next_sub and (is_fixed and (next_sub.start_time - lead_in) or cur_sub.end_time) or nil

      if cur_time >= cur_sub.start_time and (not next_threshold or cur_time < next_threshold) then

        keep_active = true

      end

    end



    if not keep_active then

      local found_idx = best_idx

      if not found_idx and num_f > 0 then

        found_idx = 1

      end

      state.active_sub_idx = found_idx

      if found_idx then

        state.selected_real_sub_idx = state.find_subtitle_index(filtered_subs[found_idx])

      end

    end

  end



  -- 3. Auto-centering trigger: strictly when active subtitle changes or filter changed

  if state.active_sub_idx then

    if filter_changed then

      state.need_calc_scroll_target = true

      state.last_centered_idx = state.active_sub_idx

      state.suppress_autoscroll_until = 0

    elseif state.auto_scroll and (state.last_centered_idx ~= state.active_sub_idx) then

      -- New subtitle activated (via playback or timeline click): immediately center

      state.need_calc_scroll_target = true

      state.last_centered_idx = state.active_sub_idx

      state.suppress_autoscroll_until = 0

    end

  end



  -- Child scrolling window:

  -- When in focus mode: height 0 (spans 100% full height to the bottom)

  -- When in standard mode: height -56 (leaves room at bottom for action buttons card)

  local child_h_param = is_focus_mode and 0 or -56

  local child_bg_pushed = 0

  if #state.subtitles > 0 then

    -- When subtitles exist, child list is an opaque UI block that completely obscures background watermark

    local win_bg_col = 0x14171CFF

    if ImGui.GetStyleColor and ImGui.Col_WindowBg then

      local ok_sc, sc = pcall(ImGui.GetStyleColor, ctx, ImGui.Col_WindowBg)

      if ok_sc and sc and sc ~= 0 then

        win_bg_col = (sc | 0xFF)

      end

    end

    child_bg_pushed = safe_push_style_color(ctx, ImGui, ImGui.Col_ChildBg, win_bg_col)

  end



  local list_open = ImGui.BeginChild(ctx, "SubtitlesListChild", 0, child_h_param)

  if list_open then

    local window_min_x, window_min_y = ImGui.GetWindowPos(ctx)

    local child_h = ImGui.GetWindowHeight(ctx)

    local cur_scroll_y = ImGui.GetScrollY(ctx)



    -- Detect manual scrolling (scrollbar dragging, mouse wheel, track clicking)

    local scrolled_by_user = false

    if state._is_programmatic_scrolling then

      if state._expected_scroll_y and math.abs(cur_scroll_y - state._expected_scroll_y) > 2.0 then

        scrolled_by_user = true

      end

      state._is_programmatic_scrolling = false

      state._expected_scroll_y = nil

    elseif state._last_frame_scroll_y and math.abs(cur_scroll_y - state._last_frame_scroll_y) > 0.5 then

      scrolled_by_user = true

    end



    if ImGui.IsWindowHovered(ctx) and ImGui.GetMouseWheel then

      local mw = ImGui.GetMouseWheel(ctx)

      if mw and mw ~= 0 then

        scrolled_by_user = true

      end

    end



    if scrolled_by_user then

      state.scroll_target_y = nil

      state.need_calc_scroll_target = false

      state.suppress_autoscroll_until = now_precise + 2.0

      state.last_centered_idx = state.active_sub_idx

    end



    if #filtered_subs == 0 then

      if #state.subtitles == 0 then

        if is_focus_mode and state.focus_watermark_geo and watermark and watermark.draw_focus then

          local geo = state.focus_watermark_geo

          watermark.draw_focus(ctx, ImGui, geo.cx, geo.cy, geo.size, nil, 0.045)

          ui.handle_file_drop(ctx, state, ImGui)

        else

          ImGui.TextDisabled(ctx, "Нет загруженных субтитров. Загрузите файл .ass или .srt через кнопку выше или перетащите его в окно.")



          local geo = state.watermark_geo

          local cx, cy, max_dim

          if geo then

            cx, cy, max_dim = geo.cx, geo.cy, geo.max_dim

          else

            local win_pos_x, win_pos_y = ImGui.GetWindowPos(ctx)

            local win_w, win_h = ImGui.GetWindowSize(ctx)

            cx = win_pos_x + win_w * 0.5

            cy = win_pos_y + math.max(180.0, win_h * 0.55)

            max_dim = math.min(win_w, win_h)

          end

          watermark.draw(ctx, ImGui, cx, cy, max_dim, true, state)



          ui.handle_file_drop(ctx, state, ImGui)

        end

      else

        ImGui.TextDisabled(ctx, "Ни один субтитр не соответствует выбранному фильтру актеров.")

      end

    else

      local avail_w, _ = ImGui.GetContentRegionAvail(ctx)

      local total_subs = #filtered_subs



      -- Invalidate row heights on table width resize

      if not state._last_table_avail_w or math.abs(state._last_table_avail_w - avail_w) > 5.0 then

        state._last_table_avail_w = avail_w

        state.row_heights = {}

      end



      -- Target scroll percentage relative to table viewport height (SubtitlesListChild)

      local ratio = state.scroll_center_ratio or 0.40

      local top_padding = math.floor(ratio * child_h)



      -- Compute prefix offsets for all rows based on cached/estimated heights

      local offsets = { 0.0 }

      for idx = 1, total_subs do

        local sub = filtered_subs[idx]

        local row_h = state.row_heights and state.row_heights[idx]

        if row_h and row_h > 300.0 then

          row_h = nil

          state.row_heights[idx] = nil

        end

        if not row_h or row_h <= 0 then

          local font_sz = (state.active_sub_idx == idx and state.text_active_larger) and active_size or base_size

          local char_cap = math.max(15, math.floor(avail_w / (font_sz * 0.52)))

          local s_text = sub.single_line or (sub.text and sub.text:gsub("[\r\n]+", " ")) or ""

          local total_chars = (sub.char_cnt or #s_text) + 16

          local est_lines = math.max(1, math.ceil(total_chars / char_cap))

          row_h = math.max(26.0, est_lines * (font_sz * 1.35) + 10.0)

        end

        local spacing = 2.0

        if state.active_sub_idx == idx and state.text_active_spacing then

          spacing = spacing + (state.text_active_spacing_px or 8.0)

        end

        offsets[idx + 1] = offsets[idx] + row_h + spacing

      end



      -- Calculate bottom_padding: ensures the last row stops dead at ratio * child_h at max scroll (cannot overscroll)

      local last_row_total_h = (offsets[total_subs + 1] or 0) - (offsets[total_subs] or 0)

      local bottom_padding = math.max(0.0, math.floor((1.0 - ratio) * child_h - last_row_total_h))



      -- Precise target scroll: top edge of active row aligns exactly with top_padding (ratio * child_h)

      if state.need_calc_scroll_target and state.active_sub_idx then

        local act_idx = math.max(1, math.min(total_subs, state.active_sub_idx))

        local target_y = offsets[act_idx]

        state.scroll_target_y = target_y

        state.need_calc_scroll_target = false

      end



      local est_start = 1

      local est_end = total_subs



      if total_subs > 50 then

        local view_min_y = cur_scroll_y - 250.0

        local view_max_y = cur_scroll_y + child_h + 250.0

        local subs_view_min_y = view_min_y - top_padding

        local subs_view_max_y = view_max_y - top_padding



        local low, high = 1, total_subs

        while low <= high do

          local mid = math.floor((low + high) / 2)

          if offsets[mid + 1] >= subs_view_min_y then

            est_start = mid

            high = mid - 1

          else

            low = mid + 1

          end

        end



        low, high = est_start, total_subs

        while low <= high do

          local mid = math.floor((low + high) / 2)

          if offsets[mid] <= subs_view_max_y then

            est_end = mid

            low = mid + 1

          else

            high = mid - 1

          end

        end

        est_start = math.max(1, math.min(total_subs, est_start))

        est_end = math.max(est_start, math.min(total_subs, est_end))

      end



      -- Top interactive spacer (clicking selects first subtitle and scrolls directly to it)

      local top_spacer_h = top_padding + offsets[est_start]

      if top_spacer_h > 0 then

        ImGui.Dummy(ctx, avail_w, top_spacer_h)

        local min_x, min_y = ImGui.GetItemRectMin(ctx)

        local max_x, max_y = ImGui.GetItemRectMax(ctx)

        local mx, my = ImGui.GetMousePos(ctx)

        local is_hovered = (mx >= min_x and mx <= max_x and my >= min_y and my <= max_y and ImGui.IsWindowHovered(ctx))



        if is_hovered and (ImGui.IsMouseClicked(ctx, 0) or (ImGui.IsMouseDoubleClicked and ImGui.IsMouseDoubleClicked(ctx, 0))) then

          local first_sub = filtered_subs[1]

          if first_sub then

            local real_idx = state.find_subtitle_index(first_sub) or 1

            state.active_sub_idx = 1

            state.selected_real_sub_idx = real_idx

            state.user_selected_row_idx = real_idx

            state.last_click_row_time = (reaper and reaper.time_precise and reaper.time_precise()) or os.clock()

            if reaper and reaper.SelectAllMediaItems then

              reaper.SelectAllMediaItems(0, false)

            end

            if first_sub.start_time and actions and actions.jump_to_time then

              actions.jump_to_time(first_sub.start_time)

            end

            state.scroll_target_y = 0.0

            state.need_calc_scroll_target = false

            state.last_centered_idx = 1

            state.suppress_autoscroll_until = 0

            state._is_programmatic_scrolling = true

            state._expected_scroll_y = 0.0

          end

        end

      end



      for i = est_start, est_end do

        local sub = filtered_subs[i]

        local is_playing = (current_playing_idx == i)

        local is_upcoming = (upcoming_idx == i)

        local is_active = (state.active_sub_idx == i)

        local is_persisted = (is_active and not is_playing and not is_upcoming)



        -- Extra spacing before active row if enabled (both while playing, upcoming, and persisted active!)

        if is_active and state.text_active_spacing then

          ImGui.Dummy(ctx, 1.0, state.text_active_spacing_px or 8.0)

        end



        -- Push font for this row (remains enlarged while active so text never jumps!)

        local font_to_push = (is_active and state.text_active_larger) and font_active or font_normal

        local font_pushed = false

        if font_to_push and ImGui.PushFont then

          ImGui.PushFont(ctx, font_to_push)

          font_pushed = true

        end



        -- Row styling:

        if is_playing then

          local b = highlight_b

          local col_hdr = ImGui.ColorConvertDouble4ToU32(b, b, b, 0.58)

          local col_hov = ImGui.ColorConvertDouble4ToU32(math.min(1.0, b + 0.08), math.min(1.0, b + 0.08), math.min(1.0, b + 0.08), 0.72)

          local col_act = ImGui.ColorConvertDouble4ToU32(math.min(1.0, b + 0.14), math.min(1.0, b + 0.14), math.min(1.0, b + 0.14), 0.85)

          ImGui.PushStyleColor(ctx, ImGui.Col_Header, col_hdr)

          ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, col_hov)

          ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive, col_act)

        elseif is_upcoming then

          -- Upcoming replica: enlarged and centered, but no background color highlight

          ImGui.PushStyleColor(ctx, ImGui.Col_Header, 0x00000000)

          ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, 0x2A323E55)

          ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive, 0x33415577)

        elseif is_persisted then

          local col_hdr = ImGui.ColorConvertDouble4ToU32(0.06, 0.06, 0.06, 0.95)

          local col_hov = ImGui.ColorConvertDouble4ToU32(0.12, 0.12, 0.12, 0.95)

          local col_act = ImGui.ColorConvertDouble4ToU32(0.18, 0.18, 0.18, 0.95)

          ImGui.PushStyleColor(ctx, ImGui.Col_Header, col_hdr)

          ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, col_hov)

          ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive, col_act)

        else

          local bg_col = 0x00000000

          if state.row_alternating_bg and (i % 2 == 0) then

            local str = state.row_alternating_strength or 0.025

            bg_col = ImGui.ColorConvertDouble4ToU32(1.0, 1.0, 1.0, str)

          end

          ImGui.PushStyleColor(ctx, ImGui.Col_Header, bg_col)

          ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, 0x2A323E55)

          ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive, 0x33415577)

        end



        local single_line = sub.single_line

        if not single_line then

          single_line = (sub.text or ""):gsub("[\r\n]+", " ")

          sub.single_line = single_line

        end



        local cached_h = state.row_heights and state.row_heights[i]

        if cached_h and cached_h > 300.0 then

          cached_h = nil

          state.row_heights[i] = nil

        end

        local row_h

        if cached_h and cached_h > 0 then

          row_h = cached_h

        else

          local font_sz = (is_active and state.text_active_larger) and active_size or base_size

          local char_capacity = math.max(15, math.floor(avail_w / (font_sz * 0.52)))

          local total_chars = (sub.char_cnt or #single_line) + 16

          local est_lines = math.max(1, math.ceil(total_chars / char_capacity))

          row_h = math.max(26.0, est_lines * (font_sz * 1.35) + 10.0)

        end



        local card_min_x, card_min_y = ImGui.GetCursorScreenPos(ctx)







        local row_id = string.format("##sub_row_%d", i)

        local is_selected_for_imgui = (is_playing or is_upcoming or is_persisted or (state.selected_real_sub_idx == state.find_subtitle_index(sub)))

        local selected_clicked = ImGui.Selectable(ctx, row_id, is_selected_for_imgui, 0, 0, row_h)

        if selected_clicked then

          local real_idx = state.find_subtitle_index(sub) or i

          state.active_sub_idx = i

          state.selected_real_sub_idx = real_idx

          state.user_selected_row_idx = real_idx

        end



        -- Context menu on right-click for editing text, changing actor, and deleting (disabled in focus mode)

        local pop_c, pop_v = push_modern_popup_styles(ctx, ImGui, state)

        if not is_focus_mode and ImGui.BeginPopupContextItem(ctx, string.format("##sub_ctx_%d", i)) then

          local popup_font = get_or_attach_font(ctx, ImGui, state.text_font_family, state.popup_font_size or 16.0)

          local popup_font_pushed = false

          if popup_font and ImGui.PushFont then

            ImGui.PushFont(ctx, popup_font)

            popup_font_pushed = true

          end



          local real_idx = state.find_subtitle_index(sub) or i



          if ImGui.MenuItem(ctx, "✏️ Изменить текст...") then

            state.text_edit_idx = real_idx

            state.text_edit_content = parser.strip_invisible_unicode(sub.text)

            state.open_text_edit_popup = true

          end



          if ImGui.BeginMenu(ctx, "🎭 Изменить актера") then

            local sub_font_pushed = false

            if popup_font and ImGui.PushFont then

              ImGui.PushFont(ctx, popup_font)

              sub_font_pushed = true

            end

            local cur_actor = sub.raw_actor or sub.actor or "NoActor"

            for _, act in ipairs(state.actors) do

              local is_cur = (act == cur_actor)

              if ImGui.MenuItem(ctx, act, nil, is_cur) then

                state.change_subtitle_actor_with_undo(real_idx, act)

                actions.update_subtitle_timeline(state, real_idx)

                actions.sync_filter_to_timeline(state)

              end

            end

            ImGui.Separator(ctx)

            if ImGui.MenuItem(ctx, "➕ Задать новое имя...") then

              state.sub_actor_modal_idx = real_idx

              state.sub_actor_modal_name = (cur_actor ~= "NoActor" and cur_actor or "")

              state.open_sub_actor_modal = true

            end

            if sub_font_pushed then

              ImGui.PopFont(ctx)

            end

            ImGui.EndMenu(ctx)

          end



          ImGui.Separator(ctx)

          if ImGui.MenuItem(ctx, "🗑️ Удалить строку") then

            state.delete_subtitle_with_undo(real_idx)

          end



          if popup_font_pushed then

            ImGui.PopFont(ctx)

          end

          ImGui.EndPopup(ctx)

        end

        pop_modern_popup_styles(ctx, ImGui, pop_c, pop_v)



        if ImGui.IsItemHovered(ctx) then

          -- Double click on row immediately opens text editing modal (disabled in focus mode)

          local is_double_clicked = (ImGui.IsMouseDoubleClicked and ImGui.IsMouseDoubleClicked(ctx, 0))

          if is_double_clicked then

            local real_idx = state.find_subtitle_index(sub) or i

            if not is_focus_mode then

              state.text_edit_idx = real_idx

              state.text_edit_content = parser.strip_invisible_unicode(sub.text)

              state.open_text_edit_popup = true

              state.text_edit_focused = false

            end

            state.active_sub_idx = i

            state.selected_real_sub_idx = real_idx

            state.user_selected_row_idx = real_idx

            state.last_click_row_time = (reaper and reaper.time_precise and reaper.time_precise()) or os.clock()

            if reaper and reaper.SelectAllMediaItems then

              reaper.SelectAllMediaItems(0, false)

            end

          elseif ImGui.IsMouseClicked(ctx, 0) then

            local real_idx = state.find_subtitle_index(sub) or i

            state.active_sub_idx = i

            state.selected_real_sub_idx = real_idx

            state.user_selected_row_idx = real_idx

            state.last_click_row_time = (reaper and reaper.time_precise and reaper.time_precise()) or os.clock()

            if reaper and reaper.SelectAllMediaItems then

              reaper.SelectAllMediaItems(0, false)

            end

            local scroll_mode = state.auto_scroll_mode or 2

            local is_reaper_playing = reaper and ((reaper.GetPlayState() & 1) ~= 0)

            local should_scroll = false



            if scroll_mode == 3 then

              should_scroll = true

            elseif scroll_mode == 2 then

              should_scroll = is_reaper_playing

            else

              should_scroll = false

            end



            if should_scroll then

              state.need_calc_scroll_target = true

              state.last_centered_idx = -1

            else

              state.last_centered_idx = i

              state.scroll_target_y = nil

              state.suppress_autoscroll_until = now_precise + 1.5

            end



            actions.jump_to_time(sub.start_time)

            -- Note: focus stays in NutNotes so Delete/Ctrl+Z hotkeys keep working

          end



          local tip_actor = sub.raw_actor or sub.actor

          if sub.character and #sub.character > 0 then

            set_tooltip(ctx, state, ImGui, string.format("Актер: %s\nПерсонаж: %s\n(Дабл-клик — редактировать текст)", sub.actor, sub.character))

          elseif tip_actor and tip_actor ~= "NoActor" then

            set_tooltip(ctx, state, ImGui, string.format("Актер: %s\n(Дабл-клик — редактировать текст)", tip_actor))

          else

            set_tooltip(ctx, state, ImGui, "Дабл-клик — редактировать текст")

          end

        end



        ImGui.PopStyleColor(ctx, 3)



        -- Calculate subtitle text color:

        local text_u32

        local actor_for_color = nil

        if sub.actors and #sub.actors > 0 then

          for _, a in ipairs(sub.actors) do

            if state.selected_actors_set[a] then

              actor_for_color = a

              break

            end

          end

          if not actor_for_color then

            actor_for_color = sub.actors[1]

          end

        else

          actor_for_color = sub.actor

        end



        local pal = (actor_for_color and state.actor_palette[actor_for_color])

        local tr, tg, tb = 1.0, 1.0, 1.0

        if pal and actor_for_color ~= "NoActor" then

          -- Higher chromatic saturation for clear visual distinction between actors

          tr = 0.18 + pal.r * 0.82

          tg = 0.18 + pal.g * 0.82

          tb = 0.18 + pal.b * 0.82

        end



        if single_actor_selected or not state.text_tint_lines then

          local base_c = state.text_custom_color or { 175 / 255, 175 / 255, 175 / 255 }

          local cr, cg, cb = base_c[1] or 0.68, base_c[2] or 0.68, base_c[3] or 0.68

          if is_playing then

            text_u32 = 0xFFFFFFFF

          elseif is_upcoming then

            local lead_p = math.max(0.0, math.min(1.0, (cur_time - (sub.start_time - lead_in)) / math.max(0.001, lead_in)))

            local factor = 1.0 + (1.25 - 1.0) * lead_p

            text_u32 = ImGui.ColorConvertDouble4ToU32(math.min(1.0, cr * factor), math.min(1.0, cg * factor), math.min(1.0, cb * factor), 1.0)

          elseif is_persisted then

            text_u32 = ImGui.ColorConvertDouble4ToU32(math.min(1.0, cr * 1.15), math.min(1.0, cg * 1.15), math.min(1.0, cb * 1.15), 1.0)

          else

            text_u32 = ImGui.ColorConvertDouble4ToU32(cr, cg, cb, 1.0)

          end

        else

          if pal and actor_for_color ~= "NoActor" then

            if is_playing then

              text_u32 = ImGui.ColorConvertDouble4ToU32(math.min(1.0, tr * 1.15), math.min(1.0, tg * 1.15), math.min(1.0, tb * 1.15), 1.0)

            elseif is_upcoming then

              local lead_p = math.max(0.0, math.min(1.0, (cur_time - (sub.start_time - lead_in)) / math.max(0.001, lead_in)))

              local factor = 0.95 + (1.15 - 0.95) * lead_p

              text_u32 = ImGui.ColorConvertDouble4ToU32(math.min(1.0, tr * factor), math.min(1.0, tg * factor), math.min(1.0, tb * factor), 1.0)

            elseif is_persisted then

              text_u32 = ImGui.ColorConvertDouble4ToU32(tr * 0.96, tg * 0.96, tb * 0.96, 1.0)

            else

              -- Bright and clear actor color distinguishing characters at a glance (fully opaque)

              text_u32 = ImGui.ColorConvertDouble4ToU32(tr * 0.92, tg * 0.92, tb * 0.92, 1.0)

            end

          else

            if is_playing then

              text_u32 = 0xFFFFFFFF

            elseif is_upcoming then

              local lead_p = math.max(0.0, math.min(1.0, (cur_time - (sub.start_time - lead_in)) / math.max(0.001, lead_in)))

              local val = 0xD4 + (0xFF - 0xD4) * lead_p

              text_u32 = ImGui.ColorConvertDouble4ToU32(val / 255.0, val / 255.0, val / 255.0, 1.0)

            elseif is_persisted then

              text_u32 = 0xD4D4D4FF

            else

              text_u32 = 0xB5B5B5FF

            end

          end

        end



        local pad_x = 8.0

        local pad_y = 5.0

        ImGui.SetCursorScreenPos(ctx, card_min_x + pad_x, card_min_y + pad_y)



        local time_str = string.format("[%s]", parser.format_time(sub.start_time))

        if is_playing then

          ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFFFFFFFF)

        elseif is_upcoming then

          ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xDCDCDCFF)

        elseif is_persisted then

          ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xA8A8A8FF)

        else

          ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x888888FF)

        end

        ImGui.Text(ctx, time_str)

        ImGui.PopStyleColor(ctx, 1)



        -- Optional Actor Badge in Row between time and text

        if state.show_actor_in_row then

          local formatted_tag = format_actor_tag(state, sub)

          if formatted_tag and #formatted_tag > 0 then

            ImGui.SameLine(ctx, 0, 8.0)

            local badge_actor = sub.raw_actor or sub.actor or "NoActor"

            local act_pal = state.actor_palette and (state.actor_palette[badge_actor] or (sub.actor and state.actor_palette[sub.actor]))

            local badge_col = 0xCCCCCCFF

            if state.text_tint_actor_names then

              badge_col = (act_pal and act_pal.u32) or 0x888888FF

            end

            ImGui.PushStyleColor(ctx, ImGui.Col_Text, badge_col)

            ImGui.Text(ctx, "[" .. formatted_tag .. "]")

            ImGui.PopStyleColor(ctx, 1)

          end

        end



        -- Optional CPS Badge between timing/actor and text (uses pre-cached cps value)

        if state.text_show_cps then

          local cps_val = (parser and parser.get_sub_cps and parser.get_sub_cps(sub)) or sub.cps or 0.0

          local char_cnt = (parser and parser.get_sub_char_cnt and parser.get_sub_char_cnt(sub)) or sub.char_cnt or 0

          local dur = math.max(0.001, (sub.end_time or 0) - (sub.start_time or 0))



          ImGui.SameLine(ctx, 0, 8.0)

          local cps_col

          if cps_val >= 20.0 then

            cps_col = 0xEF4444FF -- Alert red for extreme CPS

          elseif cps_val >= 16.0 then

            cps_col = 0xF59E0BFF -- Amber/yellow for fast CPS

          else

            cps_col = 0x8892B0FF -- Soft slate/grey for normal CPS

          end

          ImGui.PushStyleColor(ctx, ImGui.Col_Text, cps_col)

          ImGui.Text(ctx, string.format("[%.1f cps]", cps_val))

          ImGui.PopStyleColor(ctx, 1)

          if ImGui.IsItemHovered(ctx) then

            set_tooltip(ctx, state, ImGui, string.format("Темп: %.1f симв/сек\nДлина: %d симв.\nДлительность: %.2f сек", cps_val, char_cnt, dur))

          end

        end



        ImGui.SameLine(ctx, 0, 10.0)



        ImGui.PushStyleColor(ctx, ImGui.Col_Text, text_u32)

        ImGui.TextWrapped(ctx, single_line)

        ImGui.PopStyleColor(ctx, 1)



        local _, cur_end_y = ImGui.GetCursorScreenPos(ctx)

        local actual_h = math.max(26.0, math.min(300.0, (cur_end_y - card_min_y) + pad_y))

        if state.row_heights == nil then state.row_heights = {} end

        if not cached_h or math.abs(cached_h - actual_h) > 1.0 then

          state.row_heights[i] = actual_h

        end



        local card_effective_h = actual_h



        if is_playing then

          local dur = math.max(0.001, sub.end_time - sub.start_time)

          local progress = math.min(1.0, math.max(0.0, (cur_time - sub.start_time) / dur))

          local bar_h = 3.0

          local bar_y1 = card_min_y + card_effective_h - bar_h

          local bar_y2 = card_min_y + card_effective_h



          local draw_list = ImGui.GetWindowDrawList(ctx)

          ImGui.DrawList_AddRectFilled(draw_list, card_min_x, bar_y1, card_min_x + avail_w, bar_y2, 0x00000044, 1.0)



          local filled_w = avail_w * progress

          if is_holding_current and (current_playing_idx == i) then

            -- Hold mode: progress bar is full and changes to amber/gold

            local hold_col = 0xF59E0BEE

            ImGui.DrawList_AddRectFilled(draw_list, card_min_x, bar_y1, card_min_x + avail_w, bar_y2, hold_col, 1.0)



            -- Draw hold duration text right under the replica / at bottom right of card

            local hold_txt = string.format("+%.1fs", hold_time_sec)

            local ht_w, ht_h = ImGui.CalcTextSize(ctx, hold_txt)

            local txt_x = card_min_x + avail_w - ht_w - 6.0

            local txt_y = bar_y1 - ht_h - 2.0

            ImGui.DrawList_AddText(draw_list, txt_x, txt_y, 0xF59E0BFF, hold_txt)

          elseif filled_w > 1.0 then

            local bar_col = 0xFFFFFF88

            if pal and actor_for_color ~= "NoActor" then

              bar_col = ImGui.ColorConvertDouble4ToU32(tr, tg, tb, 0.70)

            end

            ImGui.DrawList_AddRectFilled(draw_list, card_min_x, bar_y1, card_min_x + filled_w, bar_y2, bar_col, 1.0)

          end

        end



        -- Draw alternating zebra background directly on the window draw list:

        if not is_playing and not is_upcoming and not is_persisted then

          if state.row_alternating_bg and (i % 2 == 0) then

            local str = state.row_alternating_strength or 0.05

            local zebra_col = ImGui.ColorConvertDouble4ToU32(1.0, 1.0, 1.0, str)

            local draw_list = ImGui.GetWindowDrawList(ctx)

            ImGui.DrawList_AddRectFilled(draw_list, card_min_x, card_min_y, card_min_x + avail_w, card_min_y + card_effective_h, zebra_col, 2.0)

          end

        end



        if is_persisted then

          local draw_list = ImGui.GetWindowDrawList(ctx)

          ImGui.DrawList_AddRect(draw_list, card_min_x, card_min_y, card_min_x + avail_w, card_min_y + card_effective_h, 0x383838AA, 2.0, 0, 1.0)

        end



        -- Subtle neutral white/gray top and bottom border (2px) for upcoming subtitle during pre-roll lead-in (no background color, no progress bar)

        if is_upcoming and not is_playing then

          local draw_list = ImGui.GetWindowDrawList(ctx)

          local border_col = 0xE2E8F077 -- Neutral white/gray (RGB 226, 232, 240 with ~45% alpha)

          local line_y1 = card_min_y

          local line_y2 = card_min_y + card_effective_h

          ImGui.DrawList_AddLine(draw_list, card_min_x, line_y1, card_min_x + avail_w, line_y1, border_col, 2.0)

          ImGui.DrawList_AddLine(draw_list, card_min_x, line_y2, card_min_x + avail_w, line_y2, border_col, 2.0)

        end



        if font_pushed then

          ImGui.PopFont(ctx)

        end



        local rem_h = (card_min_y + card_effective_h) - cur_end_y

        if rem_h > 0 then

          ImGui.Dummy(ctx, 1.0, rem_h)

        else

          ImGui.Dummy(ctx, 1.0, 2.0)

        end



        if is_active and state.text_active_spacing then

          ImGui.Dummy(ctx, 1.0, state.text_active_spacing_px or 8.0)

        end



      end



      -- Bottom interactive spacer (clicking selects last subtitle and scrolls directly to it)

      local skipped_bot_h = offsets[total_subs + 1] - offsets[est_end + 1]

      local bot_spacer_h = skipped_bot_h + bottom_padding

      if bot_spacer_h > 0 then

        ImGui.Dummy(ctx, avail_w, bot_spacer_h)

        local min_x, min_y = ImGui.GetItemRectMin(ctx)

        local max_x, max_y = ImGui.GetItemRectMax(ctx)

        local mx, my = ImGui.GetMousePos(ctx)

        local is_hovered = (mx >= min_x and mx <= max_x and my >= min_y and my <= max_y and ImGui.IsWindowHovered(ctx))



        if is_hovered and (ImGui.IsMouseClicked(ctx, 0) or (ImGui.IsMouseDoubleClicked and ImGui.IsMouseDoubleClicked(ctx, 0))) then

          local last_sub = filtered_subs[total_subs]

          if last_sub then

            local real_idx = state.find_subtitle_index(last_sub) or total_subs

            state.active_sub_idx = total_subs

            state.selected_real_sub_idx = real_idx

            state.user_selected_row_idx = real_idx

            state.last_click_row_time = (reaper and reaper.time_precise and reaper.time_precise()) or os.clock()

            if reaper and reaper.SelectAllMediaItems then

              reaper.SelectAllMediaItems(0, false)

            end

            if last_sub.start_time and actions and actions.jump_to_time then

              actions.jump_to_time(last_sub.start_time)

            end

            local target_y = offsets[total_subs] or 0.0

            state.scroll_target_y = target_y

            state.need_calc_scroll_target = false

            state.last_centered_idx = total_subs

            state.suppress_autoscroll_until = 0

            state._is_programmatic_scrolling = true

            state._expected_scroll_y = target_y

          end

        end

      end

    end



    -- Smooth scrolling interpolation

    if state.scroll_target_y then

      local cur_scroll = ImGui.GetScrollY(ctx)

      local diff = state.scroll_target_y - cur_scroll

      local next_scroll = nil

      if not state.smooth_scroll_enabled or filter_changed or math.abs(diff) < 0.8 then

        next_scroll = state.scroll_target_y

        state.scroll_target_y = nil

      else

        local speed = state.smooth_scroll_speed or 14.0

        local factor = 1.0 - math.exp(-speed * dt)

        local step = diff * factor

        if math.abs(step) < 0.25 then

          step = (diff > 0 and 0.25 or -0.25)

        end

        if math.abs(diff) <= math.abs(step) then

          next_scroll = state.scroll_target_y

          state.scroll_target_y = nil

        else

          next_scroll = cur_scroll + step

        end

      end

      if next_scroll then

        ImGui.SetScrollY(ctx, next_scroll)

        state._is_programmatic_scrolling = true

        state._expected_scroll_y = next_scroll

      end

    end

    state._last_frame_scroll_y = ImGui.GetScrollY(ctx)

    ImGui.EndChild(ctx)

  end

  if child_bg_pushed > 0 then

    ImGui.PopStyleColor(ctx, child_bg_pushed)

  end

  ui.handle_file_drop(ctx, state, ImGui)

end



-- Render Tab 1: Subtitles

function ui.render_tab_subtitles(ctx, state, ImGui)

  local base_acc, hov_acc, act_acc, soft_acc = get_accent_colors(state, ImGui)



  -- 1. TOP ACTOR FILTER & OPTIONS CONTROL BLOCK (Greyish container card)

  local open_filter = begin_control_box(ctx, state, ImGui, "sub_top_filter")

  if open_filter then

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 6.0)

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 6.0, 4.0)



    -- Get unselected actors list for dropdown

    local unselected = {}

    for _, actor in ipairs(state.actors) do

      if not state.is_actor_selected(actor) then

        table.insert(unselected, actor)

      end

    end



    ImGui.AlignTextToFramePadding(ctx)

    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xB0B7C3FF)

    ImGui.Text(ctx, "Фильтр актеров:")

    ImGui.PopStyleColor(ctx, 1)

    ImGui.SameLine(ctx, 0, 8.0)



    ImGui.SetNextItemWidth(ctx, 200)

    local combo_preview = #state.selected_actors > 0 and "(добавить актера...)" or "Все актеры (без фильтра)"



    local p_cols, p_vars = push_modern_combo_styles(ctx, ImGui, state)

    if ImGui.BeginCombo(ctx, "##actor_filter_combo", combo_preview) then

      if #unselected == 0 then

        ImGui.TextDisabled(ctx, "Все актеры уже добавлены в фильтр")

      else

        for _, actor in ipairs(unselected) do

          local count = state.actor_counts[actor] or 0

          local label = string.format("%s (%d)", actor, count)

          if ImGui.Selectable(ctx, label) then

            state.add_actor_filter(actor)

            actions.sync_filter_to_timeline(state)

          end

        end

      end

      ImGui.EndCombo(ctx)

    end

    pop_modern_combo_styles(ctx, ImGui, p_cols, p_vars)



    -- Text Search Field on the same row or right side

    ImGui.SameLine(ctx, 0, 16.0)

    ImGui.AlignTextToFramePadding(ctx)

    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xB0B7C3FF)

    ImGui.Text(ctx, "🔍 Поиск:")

    ImGui.PopStyleColor(ctx, 1)

    ImGui.SameLine(ctx, 0, 6.0)



    ImGui.SetNextItemWidth(ctx, 180)

    local search_changed, new_query

    if ImGui.InputTextWithHint then

      search_changed, new_query = ImGui.InputTextWithHint(ctx, "##sub_text_search", "текст саба...", state.search_query or "", 256)

    else

      search_changed, new_query = ImGui.InputText(ctx, "##sub_text_search", state.search_query or "", 256)

    end

    if ImGui.IsItemActive and ImGui.IsItemActive(ctx) then

      state.search_input_active = true

    else

      state.search_input_active = false

    end

    if search_changed then

      state.search_query = new_query

      state.filter_revision = (state.filter_revision or 0) + 1

      state.last_centered_idx = -1

      state.need_calc_scroll_target = true

      state.suppress_autoscroll_until = 0

      state.scroll_target_y = nil

      actions.sync_filter_to_timeline(state)

    end



    if state.search_query and #state.search_query > 0 then

      ImGui.SameLine(ctx, 0, 4.0)

      if ImGui.Button(ctx, "✕##clear_search") then

        state.search_query = ""

        state.filter_revision = (state.filter_revision or 0) + 1

        state.last_centered_idx = -1

        state.need_calc_scroll_target = true

        state.suppress_autoscroll_until = 0

        state.scroll_target_y = nil

        actions.sync_filter_to_timeline(state)

      end

      if ImGui.IsItemHovered(ctx) then

        set_tooltip(ctx, state, ImGui, "Очистить строку поиска")

      end

    end



    -- Filter tags panel below dropdown

    if #state.selected_actors > 0 then

      ImGui.Spacing(ctx)

      ImGui.AlignTextToFramePadding(ctx)

      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x8892B0FF)

      ImGui.Text(ctx, "Выбрано:")

      ImGui.PopStyleColor(ctx, 1)

      ImGui.SameLine(ctx, 0, 8.0)



      local to_remove = nil

      for _, actor in ipairs(state.selected_actors) do

        local palette_info = state.actor_palette[actor]

        local btn_col = palette_info and palette_info.u32 or 0x777777FF



        -- Render tag button with cross

        ImGui.PushStyleColor(ctx, ImGui.Col_Button, btn_col)

        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, btn_col)

        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, btn_col)

        ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x1A1A1AFF) -- dark text on pastel



        local tag_label = string.format(" %s  ✕ ##tag_%s", actor, actor)

        if ImGui.Button(ctx, tag_label) then

          to_remove = actor

        end



        ImGui.PopStyleColor(ctx, 4)

        ImGui.SameLine(ctx, 0, 6.0)

      end



      if to_remove then

        state.remove_actor_filter(to_remove)

        actions.sync_filter_to_timeline(state)

      end



      -- Clear all filter button (styled as subtle dark pill)

      ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x33394666)

      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x475569AA)

      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x64748BCC)

      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xCBD5E1FF)

      if ImGui.Button(ctx, "Сбросить все ✕") then

        state.clear_actor_filter()

        actions.sync_filter_to_timeline(state)

      end

      ImGui.PopStyleColor(ctx, 4)

    end



    ImGui.PopStyleVar(ctx, 2)

    ImGui.Spacing(ctx)



    -- Options row with modern toggle switches

    local rv_auto, new_auto = render_toggle_switch(ctx, state, ImGui, "opt_auto", "Авто-прокрутка к текущему", state.auto_scroll, act_acc)

    if rv_auto then

      state.auto_scroll = new_auto

      state.save_settings()

    end



    ImGui.SameLine(ctx, 0, 24)

    local rv_sync, new_sync = render_toggle_switch(ctx, state, ImGui, "opt_sync", "Синхронизировать разметку с фильтром", state.sync_with_filter, act_acc)

    if rv_sync then

      state.sync_with_filter = new_sync

      state.save_settings()

      if new_sync then

        actions.sync_filter_to_timeline(state)

      end

    end

  end

  end_control_box(ctx, ImGui, open_filter)



  -- 2. MAIN SUBTITLES LIST (Render standard list leaving room at bottom)

  ui.render_subtitles_list(ctx, state, ImGui, false)



  local filtered_subs = state.get_filtered_subtitles()



  -- 3. BOTTOM CONTROL BUTTONS (Greyish container card separating timeline actions)

  local open_bottom = begin_control_box(ctx, state, ImGui, "sub_bottom_actions", 46.0)

  if open_bottom then

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 6.0)

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 10.0, 5.0)



    -- Checkbox: Toggle Регионы (Флажок без Undo/Redo)

    ImGui.AlignTextToFramePadding(ctx)

    local rv_rgn, new_rgn = ImGui.Checkbox(ctx, "Регионы###chk_regions_sync", state.regions_enabled ~= false)

    if rv_rgn then

      state.regions_enabled = new_rgn

      if actions and actions.ensure_regions_synced then

        actions.ensure_regions_synced(state)

      elseif new_rgn then

        local subs_to_use = state.sync_with_filter and filtered_subs or state.subtitles

        if #subs_to_use > 0 then

          actions.set_regions(subs_to_use, state.actor_palette, state)

        end

      else

        actions.clear_regions()

      end

      state.save_settings()

    end

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Синхронизация регионов в REAPER.\nКогда флажок включен, строки субтитров отображаются регионами на таймлайне.\nФлажок можно включать даже при пустом проекте — при добавлении строк регионы сразу появятся.")

    end



    ImGui.SameLine(ctx, 0, 8)



    -- Button 2: Создать строку (По Time Selection)

    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x2A3E5Cee)

    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x38537Aee)

    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x48699Aee)

    if ImGui.Button(ctx, "➕ Создать строку") then

      actions.create_subtitle_from_time_selection(state)

    end

    ImGui.PopStyleColor(ctx, 3)



    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Создает субтитр (noActor) по текущему Time Selection в REAPER.\nХоткей: " .. (state.hotkey_create_sub or "Shift+T"))

    end



    ImGui.SameLine(ctx, 0, 8.0)



    -- Button 3: Удалить строку (текущий в Note mode / выделенный в Table mode)

    local can_del = false

    local del_idx = nil

    if not state.focus_mode then

      del_idx = state.user_selected_row_idx

      can_del = (del_idx ~= nil and state.subtitles and state.subtitles[del_idx] ~= nil)

    end



    if not can_del then

      ImGui.BeginDisabled(ctx, true)

    end

    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x5C2A2Aee)

    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x7A3838ee)

    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x9A4848ee)

    if ImGui.Button(ctx, "✕ Удалить строку") then

      if del_idx and state.subtitles[del_idx] then

        if state.view_mode == "note" then

          commit_note_edit(ctx, state, ImGui)

        end

        local ctrl_down = (ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl) or ImGui.IsKeyDown(ctx, ImGui.Key_LeftCtrl) or ImGui.IsKeyDown(ctx, ImGui.Key_RightCtrl) or (ImGui.Mod_Super and ImGui.IsKeyDown(ctx, ImGui.Mod_Super)))

        state.delete_subtitle(del_idx, ctrl_down)

        state.save_to_project()

      end

    end

    ImGui.PopStyleColor(ctx, 3)

    if not can_del then

      ImGui.EndDisabled(ctx)

    end

    if ImGui.IsItemHovered(ctx) then

      if state.view_mode == "note" then

        set_tooltip(ctx, state, ImGui, "Удалить текущий субтитр (Delete).\nCtrl+Клик: удалить и сразу перескочить таймингом курсора к следующему субтитру.")

      else

        set_tooltip(ctx, state, ImGui, "Удалить выделенный субтитр (Delete).\nCtrl+Клик / Ctrl+Delete: удалить и сразу перескочить таймингом курсора к следующему субтитру.")

      end

    end



    -- Optional red error toast indicator if time selection was missing

    local now_p = (reaper and reaper.time_precise and reaper.time_precise()) or os.clock()

    if state.time_selection_error_msg and now_p < (state.time_selection_error_until or 0) then

      ImGui.SameLine(ctx, 0, 10.0)

      ImGui.AlignTextToFramePadding(ctx)

      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF4D4DFF) -- Bright Red warning text

      ImGui.Text(ctx, "⚠️ " .. state.time_selection_error_msg)

      ImGui.PopStyleColor(ctx, 1)

    end



    ImGui.PopStyleVar(ctx, 2)



    ImGui.SameLine(ctx, 0, 16)

    ImGui.AlignTextToFramePadding(ctx)

    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x8892B0FF)

    ImGui.Text(ctx, string.format("Строк: %d / %d", #filtered_subs, #state.subtitles))

    ImGui.PopStyleColor(ctx, 1)

  end

  end_control_box(ctx, ImGui, open_bottom)



  ui.handle_file_drop(ctx, state, ImGui)

end



-- Render Tab 2: Actors Database

function ui.render_tab_actors(ctx, state, ImGui)

  local open_top = begin_control_box(ctx, state, ImGui, "actors_top_bar")

  if open_top then

    ImGui.AlignTextToFramePadding(ctx)

    ImGui.Text(ctx, string.format("База актеров (всего: %d)", #state.actors))

    ImGui.SameLine(ctx, 0, 16)



    if render_reset_pill_button(ctx, ImGui, "reset_palette", "Сбросить цвета по умолчанию (пастель 360°)", 310) then

      state.actor_palette = colors.generate_actor_palette(state.actors, state.default_region_color or { state.get_default_region_color() })

      state.save_to_project()

      actions.sync_filter_to_timeline(state)

      if actions.sync_palette_to_timeline then actions.sync_palette_to_timeline(state) end

    end

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Сбросить палитру цветов актеров на стандартную пастельную (или цвет по умолчанию, если актер только один)")

    end



    ImGui.Spacing(ctx)



    ImGui.AlignTextToFramePadding(ctx)

    ImGui.Text(ctx, "Цвет региона по умолчанию:")

    ImGui.SameLine(ctx, 0, 8)



    local def_r, def_g, def_b = state.get_default_region_color()

    local cur_rgb = (math.floor(def_r * 255 + 0.5) << 16) | (math.floor(def_g * 255 + 0.5) << 8) | math.floor(def_b * 255 + 0.5)

    local col_flags = (ImGui.ColorEditFlags_NoInputs or 0) | (ImGui.ColorEditFlags_NoAlpha or 0)

    local col_changed, new_rgb = ImGui.ColorEdit4(ctx, "##default_region_color", cur_rgb, col_flags)

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Цвет региона по умолчанию (для NoActor или когда все реплики в проекте присвоены одному актеру).")

    end



    if col_changed then

      local dr = ((new_rgb >> 16) & 0xFF) / 255

      local dg = ((new_rgb >> 8) & 0xFF) / 255

      local db = (new_rgb & 0xFF) / 255

      state.default_region_color = { dr, dg, db }

      state.save_settings()



      if not state.actor_palette then state.actor_palette = {} end

      local u32_pure = ((new_rgb & 0xFFFFFF) << 8) | 0xFF

      local reaper_col = colors.rgb_to_reaper(dr, dg, db)

      state.actor_palette["NoActor"] = {

        r = dr, g = dg, b = db, a = 1.0,

        u32 = u32_pure,

        reaper_color = reaper_col,

        hue = 0

      }



      local named_actors = {}

      for _, name in ipairs(state.actors or {}) do

        if name ~= "NoActor" then

          table.insert(named_actors, name)

        end

      end

      if #named_actors == 1 then

        state.actor_palette[named_actors[1]] = {

          r = dr, g = dg, b = db, a = 1.0,

          u32 = u32_pure,

          reaper_color = reaper_col,

          hue = 0

        }

      end



      state.save_to_project()

      actions.sync_filter_to_timeline(state)

      if actions.sync_palette_to_timeline then actions.sync_palette_to_timeline(state) end

    end



    ImGui.SameLine(ctx, 0, 6)

    if ImGui.Button(ctx, "↺##reset_default_rgn_col") then

      state.default_region_color = nil

      state.save_settings()



      local def_r, def_g, def_b = state.get_default_region_color()

      local u32_pure = (math.floor(def_r * 255 + 0.5) << 24) | (math.floor(def_g * 255 + 0.5) << 16) | (math.floor(def_b * 255 + 0.5) << 8) | 0xFF

      if not state.actor_palette then state.actor_palette = {} end

      state.actor_palette["NoActor"] = {

        r = def_r, g = def_g, b = def_b, a = 1.0,

        u32 = u32_pure,

        reaper_color = 0,

        hue = 0

      }



      local named_actors = {}

      for _, name in ipairs(state.actors or {}) do

        if name ~= "NoActor" then

          table.insert(named_actors, name)

        end

      end

      if #named_actors == 1 then

        state.actor_palette[named_actors[1]] = {

          r = def_r, g = def_g, b = def_b, a = 1.0,

          u32 = u32_pure,

          reaper_color = 0,

          hue = 0

        }

      end



      state.save_to_project()

      actions.sync_filter_to_timeline(state)

      if actions.sync_palette_to_timeline then actions.sync_palette_to_timeline(state) end

    end

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Сбросить цвет региона по умолчанию на стандартный цвет темы REAPER")

    end

  end

  end_control_box(ctx, ImGui, open_top)



  local real_actors_count = 0

  for _, actor in ipairs(state.actors) do

    if actor ~= "NoActor" then

      real_actors_count = real_actors_count + 1

    end

  end



  if real_actors_count == 0 then

    if #state.actors == 0 then

      ImGui.TextDisabled(ctx, "Актеры пока не обнаружены. Загрузите файл субтитров с поддержкой актеров (ASS или SRT с префиксами).")

    else

      ImGui.TextDisabled(ctx, "Актеры в файле не обнаружены (все реплики без указания актера). Загрузите файл с поддержкой актеров.")

    end



    local geo = state.watermark_geo

    local cx, cy, max_dim

    if geo then

      cx, cy, max_dim = geo.cx, geo.cy, geo.max_dim

    else

      local win_pos_x, win_pos_y = ImGui.GetWindowPos(ctx)

      local win_w, win_h = ImGui.GetWindowSize(ctx)

      cx = win_pos_x + win_w * 0.5

      cy = win_pos_y + math.max(180.0, win_h * 0.55)

      max_dim = math.min(win_w, win_h)

    end

    watermark.draw(ctx, ImGui, cx, cy, max_dim, true, state)



    ui.handle_file_drop(ctx, state, ImGui)

    return

  end



  -- Table of actors (opaque row backgrounds completely covering background watermark)

  ImGui.PushStyleColor(ctx, ImGui.Col_TableRowBg, 0x1A1E24FF)

  ImGui.PushStyleColor(ctx, ImGui.Col_TableRowBgAlt, 0x1F242BFF)

  ImGui.PushStyleColor(ctx, ImGui.Col_TableHeaderBg, 0x242A34FF)



  local table_font = get_or_attach_font(ctx, ImGui, state.text_font_family or "Segoe UI", state.ui_font_size or 11.0)

  local table_font_pushed = false

  if table_font and ImGui.PushFont then

    ImGui.PushFont(ctx, table_font)

    table_font_pushed = true

  end



  if ImGui.BeginTable(ctx, "ActorsTable", 5, ImGui.TableFlags_Borders | ImGui.TableFlags_RowBg | ImGui.TableFlags_SizingFixedFit) then

    ImGui.TableSetupColumn(ctx, "В фильтре", ImGui.TableColumnFlags_WidthFixed, 75)

    ImGui.TableSetupColumn(ctx, "Имя актера", ImGui.TableColumnFlags_WidthStretch)

    ImGui.TableSetupColumn(ctx, "Реплик", ImGui.TableColumnFlags_WidthFixed, 80)

    ImGui.TableSetupColumn(ctx, "Доля (%)", ImGui.TableColumnFlags_WidthFixed, 140)

    ImGui.TableSetupColumn(ctx, "Цвет", ImGui.TableColumnFlags_WidthFixed, 80)

    ImGui.TableHeadersRow(ctx)



    local total_subs = math.max(1, #state.subtitles)

    local base_acc, hov_acc, act_acc, soft_acc = get_accent_colors(state, ImGui)



    for _, actor in ipairs(state.actors) do

      ImGui.TableNextRow(ctx)



      -- Column 1: Checkbox for active filter (centered in cell)

      ImGui.TableSetColumnIndex(ctx, 0)

      local is_sel = state.is_actor_selected(actor)

      local cell_avail_w, _ = ImGui.GetContentRegionAvail(ctx)

      local chk_sz = ImGui.GetFrameHeight(ctx)

      if cell_avail_w > chk_sz then

        ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + (cell_avail_w - chk_sz) * 0.5)

      end

      ImGui.PushStyleColor(ctx, ImGui.Col_CheckMark, act_acc)

      local rv_chk, new_sel = ImGui.Checkbox(ctx, "##act_chk_" .. actor, is_sel)

      ImGui.PopStyleColor(ctx, 1)

      if rv_chk then

        state.toggle_actor_filter(actor)

        actions.sync_filter_to_timeline(state)

      end



      -- Column 2: Actor name with badge

      ImGui.TableSetColumnIndex(ctx, 1)



      local screen_x, screen_y = ImGui.GetCursorScreenPos(ctx)

      local cell_h = math.max(24.0, math.floor((state.ui_font_size or 11.0) * 1.5 + 4.5))



      -- Selectable covering the entire column cell so right-click works anywhere on the badge or cell

      ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, 0x3388CC22)

      ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive, 0x3388CC44)

      ImGui.PushStyleColor(ctx, ImGui.Col_Header, 0x00000000)

      ImGui.Selectable(ctx, "##act_cell_" .. actor, false, 0, 0, cell_h)

      ImGui.PopStyleColor(ctx, 3)



      local is_cell_hovered = ImGui.IsItemHovered(ctx)



      local pop_c, pop_v = push_modern_popup_styles(ctx, ImGui, state)

      if ImGui.BeginPopupContextItem(ctx, "##act_ctx_" .. actor) then

        local popup_font = get_or_attach_font(ctx, ImGui, state.text_font_family, state.popup_font_size or 16.0)

        local popup_font_pushed = false

        if popup_font and ImGui.PushFont then

          ImGui.PushFont(ctx, popup_font)

          popup_font_pushed = true

        end



        if ImGui.MenuItem(ctx, "✏️ Переименовать актера...") then

          state.rename_actor_orig = actor

          state.rename_actor_input = actor

          state.open_rename_actor_modal = true

        end



        local other_count = 0

        for _, act in ipairs(state.actors) do

          if act ~= actor then

            other_count = other_count + 1

          end

        end



        if ImGui.BeginMenu(ctx, "🔀 Объединить с другим актером", other_count > 0) then

          local sub_font_pushed = false

          if popup_font and ImGui.PushFont then

            ImGui.PushFont(ctx, popup_font)

            sub_font_pushed = true

          end

          for _, other in ipairs(state.actors) do

            if other ~= actor then

              local target_count = state.actor_counts[other] or 0

              local item_label = string.format("%s (%d репл.)", other, target_count)

              if ImGui.MenuItem(ctx, item_label) then

                state.merge_actors_with_undo(actor, other)

                actions.update_all_timeline_actors(state)

                actions.sync_filter_to_timeline(state)

                actions.init_timeline_sync(state)

              end

            end

          end

          if sub_font_pushed then

            ImGui.PopFont(ctx)

          end

          ImGui.EndMenu(ctx)

        end



        if popup_font_pushed then

          ImGui.PopFont(ctx)

        end

        ImGui.EndPopup(ctx)

      end

      pop_modern_popup_styles(ctx, ImGui, pop_c, pop_v)



      if is_cell_hovered then

        set_tooltip(ctx, state, ImGui, string.format("Актер: %s\nПКМ — переименовать или объединить с другим актером", actor))

      end



      -- Draw modern pill badge matching mockup 2

      local draw_list = ImGui.GetWindowDrawList(ctx)

      local info = state.actor_palette and state.actor_palette[actor]

      local badge_col = (info and info.u32) or 0x888888FF

      local text_col = 0x1E2024FF

      if actor == "NoActor" then

        badge_col = 0x475569AA

        text_col = 0xE2E8F0FF

      end



      local txt_w, txt_h = ImGui.CalcTextSize(ctx, actor)

      local pad_x = 9.0

      local pad_y = 3.0

      local b_min_x = screen_x + 4.0

      local b_min_y = screen_y + (cell_h - (txt_h + pad_y * 2)) * 0.5

      local b_max_x = b_min_x + txt_w + pad_x * 2

      local b_max_y = b_min_y + txt_h + pad_y * 2



      ImGui.DrawList_AddRectFilled(draw_list, b_min_x, b_min_y, b_max_x, b_max_y, badge_col, 5.0)

      ImGui.DrawList_AddText(draw_list, b_min_x + pad_x, b_min_y + pad_y, text_col, actor)



      -- Column 3: Lines count

      ImGui.TableSetColumnIndex(ctx, 2)

      local count = state.actor_counts[actor] or 0

      ImGui.AlignTextToFramePadding(ctx)

      ImGui.Text(ctx, tostring(count))



      -- Column 4: Percentage + visual progress bar (Mockup 2 style)

      ImGui.TableSetColumnIndex(ctx, 3)

      local pct = (count / total_subs) * 100

      local pct_str = string.format("%5.1f%%", pct)

      ImGui.AlignTextToFramePadding(ctx)

      ImGui.Text(ctx, pct_str)

      ImGui.SameLine(ctx, 0, 8.0)



      -- Draw sleek horizontal bar directly in cell

      local bar_pos_x, bar_pos_y = ImGui.GetCursorScreenPos(ctx)

      local bar_w = 64.0

      local bar_h = 5.0

      local bar_center_y = bar_pos_y + math.floor((cell_h - bar_h) * 0.5)

      -- Background groove

      ImGui.DrawList_AddRectFilled(draw_list, bar_pos_x, bar_center_y, bar_pos_x + bar_w, bar_center_y + bar_h, 0x2A313E88, 2.5)

      -- Filled progress bar using actor's color

      local fill_w = math.max(2.0, bar_w * (pct / 100.0))

      local bar_col = (info and info.u32) or base_acc

      ImGui.DrawList_AddRectFilled(draw_list, bar_pos_x, bar_center_y, bar_pos_x + fill_w, bar_center_y + bar_h, bar_col, 2.5)

      ImGui.Dummy(ctx, bar_w, bar_h)



      -- Column 5: Color picker button (centered in cell)

      ImGui.TableSetColumnIndex(ctx, 4)

      local pal = state.actor_palette[actor] or { r = 0.7, g = 0.7, b = 0.7, a = 1.0 }

      local cur_u32 = pal.u32 or colors.rgb_to_u32(pal.r, pal.g, pal.b, 1.0)



      -- Center color picker button in cell

      local cell_avail_w, _ = ImGui.GetContentRegionAvail(ctx)

      local btn_sz = ImGui.GetFrameHeight(ctx)

      if cell_avail_w > btn_sz then

        ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + (cell_avail_w - btn_sz) * 0.5)

      end



      -- With ColorEditFlags_NoAlpha, ReaImGui expects 0xXXRRGGBB:

      local cur_rgb = (cur_u32 >> 8) & 0xFFFFFF

      local col_flags = (ImGui.ColorEditFlags_NoInputs or 0) | (ImGui.ColorEditFlags_NoAlpha or 0)

      local col_changed, new_rgb = ImGui.ColorEdit4(ctx, "##col_" .. actor, cur_rgb, col_flags)

      if col_changed then

        local r = ((new_rgb >> 16) & 0xFF) / 255

        local g = ((new_rgb >> 8) & 0xFF) / 255

        local b = (new_rgb & 0xFF) / 255

        local u32_pure = ((new_rgb & 0xFFFFFF) << 8) | 0xFF

        state.actor_palette[actor] = {

          r = r,

          g = g,

          b = b,

          a = 1.0,

          u32 = u32_pure,

          reaper_color = colors.rgb_to_reaper(r, g, b),

          hue = (pal.hue or 0)

        }

        state.save_to_project()

        actions.sync_filter_to_timeline(state)

        if actions.sync_palette_to_timeline then actions.sync_palette_to_timeline(state) end

      end

    end



    ImGui.EndTable(ctx)

  end

  if table_font_pushed and ImGui.PopFont then

    ImGui.PopFont(ctx)

  end

  ImGui.PopStyleColor(ctx, 3)

  ui.handle_file_drop(ctx, state, ImGui)

end



-- Render fixed live preview of 3 subtitle lines (previous, current, next) showing text typography & active line settings

local function render_text_preview_card(ctx, state, ImGui, act_acc)

  local is_collapsed = (state.text_preview_collapsed == true)

  local open_pv = begin_control_box(ctx, state, ImGui, "txt_preview_fixed")

  if open_pv then

    local avail_w, _ = ImGui.GetContentRegionAvail(ctx)

    local title = "ПРЕДПРОСМОТР ТЕКСТА"

    local btn_label = is_collapsed and "Развернуть" or "Свернуть"

    local font_sz = (state and state.ui_font_size) or 11.0

    local scale = math.max(0.85, font_sz / 11.0)

    local btn_w = math.floor(96.0 * scale)

    local btn_h = math.max(22.0, math.floor(22.0 * scale))



    -- Header row: Title on the left with accent indicator bar, Collapse button on the right

    local p_min_x, p_min_y = ImGui.GetCursorScreenPos(ctx)

    local cur_x = ImGui.GetCursorPosX(ctx)

    local cur_y = ImGui.GetCursorPosY(ctx)

    local txt_w, txt_h = ImGui.CalcTextSize(ctx, title)



    local draw_list = ImGui.GetWindowDrawList(ctx)

    local bar_w = 3.0

    local text_gap = 8.0

    local bar_col = act_acc or 0x4A90E2FF

    local mid_y = p_min_y + btn_h * 0.5

    ImGui.DrawList_AddRectFilled(draw_list, p_min_x, mid_y - txt_h * 0.5, p_min_x + bar_w, mid_y + txt_h * 0.5, bar_col, 1.5)



    -- Draw title text vertically centered with button

    ImGui.SetCursorPosX(ctx, cur_x + bar_w + text_gap)

    ImGui.SetCursorPosY(ctx, cur_y + (btn_h - txt_h) * 0.5)

    ImGui.TextColored(ctx, 0xD0D5DDFF, title)



    -- Right-aligned collapse/expand button

    ImGui.SameLine(ctx, 0, 0)

    local btn_x = math.max(cur_x + bar_w + text_gap + txt_w + 12.0, cur_x + avail_w - btn_w)

    ImGui.SetCursorPosX(ctx, btn_x)

    ImGui.SetCursorPosY(ctx, cur_y)

    if render_collapse_pill_button(ctx, ImGui, "btn_toggle_txt_preview", btn_label, btn_w, btn_h) then

      state.text_preview_collapsed = not is_collapsed

      state.save_settings()

    end

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, is_collapsed and "Развернуть блок предпросмотра" or "Свернуть блок предпросмотра")

    end



    if not is_collapsed then

      ImGui.Spacing(ctx)

      local sep_y = p_min_y + btn_h + 4.0

      ImGui.DrawList_AddLine(draw_list, p_min_x, sep_y, p_min_x + avail_w, sep_y, 0x33394666, 1.0)

      ImGui.Dummy(ctx, 1.0, 4.0)



      local family = state.text_font_family or "Segoe UI"

      local base_size = state.text_font_size or 18.0

      local active_size = base_size

      if state.text_active_larger then

        active_size = math.floor(base_size * (state.text_active_font_scale or 1.18) + 0.5)

      end



      local font_base = get_or_attach_font(ctx, ImGui, family, base_size)

      local font_active = get_or_attach_font(ctx, ImGui, family, active_size)



      local highlight_b = state.text_highlight_brightness or 0.28



      local sample_lines = {

        { time = "[00:01:14.200]", text = "Это предыдущая реплика", actor = "ActorA", raw_actor = "ActorA - CharacterA", character = "CharacterA", is_act = false, col = 0x88C0D0FF, row_idx = 1, dur = 2.00, char_cnt = 23, cps = 11.5 },

        { time = "[00:01:18.500]", text = "Это средней длины текущая реплика", actor = "ActorB", raw_actor = "ActorB - CharacterB", character = "CharacterB", is_act = true, col = 0xFFFFFFFF, row_idx = 2, dur = 2.00, char_cnt = 33, cps = 16.5 },

        { time = "[00:01:23.000]", text = "Это очень длинная следующая реплика, тайминг которой может быть увеличен", actor = "ActorC", raw_actor = "ActorC - CharacterC", character = "CharacterC", is_act = false, col = 0xE5C07BFF, row_idx = 3, dur = 3.30, char_cnt = 71, cps = 21.5 },

      }



      local pad_x = 8.0

      local pad_y = 5.0



      for idx, item in ipairs(sample_lines) do

        local is_cur = item.is_act



        -- Extra spacing before active row if enabled (matching main list)

        if is_cur and state.text_active_spacing then

          ImGui.Dummy(ctx, 1.0, state.text_active_spacing_px or 8.0)

        end



        -- Push font before calculating heights and creating Selectable (matching main list)

        local font_to_push = is_cur and font_active or font_base

        local font_pushed = false

        if font_to_push and ImGui.PushFont then

          ImGui.PushFont(ctx, font_to_push)

          font_pushed = true

        end



        -- Row styling via Col_Header:

        if is_cur then

          local b = highlight_b

          local col_hdr = ImGui.ColorConvertDouble4ToU32(b, b, b, 0.58)

          local col_hov = ImGui.ColorConvertDouble4ToU32(math.min(1.0, b + 0.08), math.min(1.0, b + 0.08), math.min(1.0, b + 0.08), 0.72)

          local col_act = ImGui.ColorConvertDouble4ToU32(math.min(1.0, b + 0.14), math.min(1.0, b + 0.14), math.min(1.0, b + 0.14), 0.85)

          ImGui.PushStyleColor(ctx, ImGui.Col_Header, col_hdr)

          ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, col_hov)

          ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive, col_act)

        else

          local bg_col = 0x00000000

          if state.row_alternating_bg and (item.row_idx % 2 == 0) then

            local str = state.row_alternating_strength or 0.025

            bg_col = ImGui.ColorConvertDouble4ToU32(1.0, 1.0, 1.0, str)

          end

          ImGui.PushStyleColor(ctx, ImGui.Col_Header, bg_col)

          ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, 0x2A323E55)

          ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive, 0x33415577)

        end



        local font_sz = is_cur and active_size or base_size

        local char_capacity = math.max(15, math.floor(avail_w / (font_sz * 0.52)))

        local char_count = (parser and parser.get_sub_char_cnt and parser.get_sub_char_cnt(item)) or item.char_cnt or 0

        local total_chars = char_count + 16 + (state.text_show_cps and 10 or 0)

        local est_lines = math.max(1, math.ceil(total_chars / char_capacity))

        local row_h = math.max(26.0, est_lines * (font_sz * 1.35) + 10.0)



        local card_min_x, card_min_y = ImGui.GetCursorScreenPos(ctx)



        -- Selectable item covering the row (with is_cur selected)

        local row_id = string.format("##preview_sub_row_%d", idx)

        ImGui.Selectable(ctx, row_id, is_cur, 0, 0, row_h)

        ImGui.PopStyleColor(ctx, 3)



        if ImGui.IsItemHovered(ctx) then

          set_tooltip(ctx, state, ImGui, "Пример отображения строк (превью)")

        end



        ImGui.SetCursorScreenPos(ctx, card_min_x + pad_x, card_min_y + pad_y)



        -- Time string

        local time_col = is_cur and 0xFFFFFFFF or 0x888888FF

        ImGui.PushStyleColor(ctx, ImGui.Col_Text, time_col)

        ImGui.Text(ctx, item.time)

        ImGui.PopStyleColor(ctx, 1)



        -- Optional Actor Badge in preview

        if state.show_actor_in_row then

          local formatted_tag = format_actor_tag(state, item)

          if formatted_tag and #formatted_tag > 0 then

            ImGui.SameLine(ctx, 0, 8.0)

            local badge_col = 0xCCCCCCFF

            if state.text_tint_actor_names then

              badge_col = item.col

            end

            ImGui.PushStyleColor(ctx, ImGui.Col_Text, badge_col)

            ImGui.Text(ctx, "[" .. formatted_tag .. "]")

            ImGui.PopStyleColor(ctx, 1)

          end

        end



        -- Optional CPS Badge in preview (matching main subtitle table)

        if state.text_show_cps then

          local cps_val = (parser and parser.get_sub_cps and parser.get_sub_cps(item)) or item.cps or 0.0

          local char_cnt = (parser and parser.get_sub_char_cnt and parser.get_sub_char_cnt(item)) or item.char_cnt or 0

          local dur = item.dur or math.max(0.001, (item.end_time or 0) - (item.start_time or 0))



          ImGui.SameLine(ctx, 0, 8.0)

          local cps_col

          if cps_val >= 20.0 then

            cps_col = 0xEF4444FF -- Alert red for extreme CPS

          elseif cps_val >= 16.0 then

            cps_col = 0xF59E0BFF -- Amber/yellow for fast CPS

          else

            cps_col = 0x8892B0FF -- Soft slate/grey for normal CPS

          end

          ImGui.PushStyleColor(ctx, ImGui.Col_Text, cps_col)

          ImGui.Text(ctx, string.format("[%.1f cps]", cps_val))

          ImGui.PopStyleColor(ctx, 1)

          if ImGui.IsItemHovered(ctx) then

            set_tooltip(ctx, state, ImGui, string.format("Темп: %.1f симв/сек\nДлина: %d симв.\nДлительность: %.2f сек", cps_val, char_cnt, dur))

          end

        end



        ImGui.SameLine(ctx, 0, 10.0)



        -- Subtitle text with optional tinting

        local txt_col = 0xFFFFFFFF

        if not is_cur then

          if state.text_tint_lines then

            txt_col = item.col

          else

            local tc = state.text_custom_color or { 175 / 255, 175 / 255, 175 / 255 }

            txt_col = ImGui.ColorConvertDouble4ToU32(tc[1] or 0.68, tc[2] or 0.68, tc[3] or 0.68, 1.0)

          end

        end

        ImGui.PushStyleColor(ctx, ImGui.Col_Text, txt_col)

        ImGui.TextWrapped(ctx, item.text)

        ImGui.PopStyleColor(ctx, 1)



        local _, cur_end_y = ImGui.GetCursorScreenPos(ctx)

        local actual_h = math.max(26.0, (cur_end_y - card_min_y) + pad_y)

        local card_effective_h = math.max(row_h, actual_h)



        -- Progress bar for current playing line (matching main list)

        if is_cur then

          local progress = 0.55 -- representative 55% playback progress in preview

          local bar_h = 3.0

          local bar_y1 = card_min_y + card_effective_h - bar_h

          local bar_y2 = card_min_y + card_effective_h



          local draw_list_pb = ImGui.GetWindowDrawList(ctx)

          ImGui.DrawList_AddRectFilled(draw_list_pb, card_min_x, bar_y1, card_min_x + avail_w, bar_y2, 0x00000044, 1.0)



          local filled_w = avail_w * progress

          if filled_w > 1.0 then

            local bar_col = act_acc or 0xFFFFFF88

            ImGui.DrawList_AddRectFilled(draw_list_pb, card_min_x, bar_y1, card_min_x + filled_w, bar_y2, bar_col, 1.0)

          end

        else

          -- Draw alternating zebra background directly on window draw list:

          if state.row_alternating_bg and (item.row_idx % 2 == 0) then

            local str = state.row_alternating_strength or 0.05

            local zebra_col = ImGui.ColorConvertDouble4ToU32(1.0, 1.0, 1.0, str)

            local draw_list_z = ImGui.GetWindowDrawList(ctx)

            ImGui.DrawList_AddRectFilled(draw_list_z, card_min_x, card_min_y, card_min_x + avail_w, card_min_y + card_effective_h, zebra_col, 2.0)

          end

        end



        if font_pushed then

          ImGui.PopFont(ctx)

        end



        local rem_h = (card_min_y + card_effective_h) - cur_end_y

        if rem_h > 0 then

          ImGui.Dummy(ctx, 1.0, rem_h)

        else

          ImGui.Dummy(ctx, 1.0, 2.0)

        end



        -- Extra spacing after active row if enabled (matching main list)

        if is_cur and state.text_active_spacing then

          ImGui.Dummy(ctx, 1.0, state.text_active_spacing_px or 8.0)

        end

      end

      if ImGui.IsWindowHovered(ctx) and not ImGui.IsAnyItemHovered(ctx) then

        set_tooltip(ctx, state, ImGui, "Пример отображения строк (превью)")

      end

    end

  end

  end_control_box(ctx, ImGui, open_pv)

  ImGui.Spacing(ctx)

end



-- Render Tab 3: Text & Typography Settings

function ui.render_tab_text_settings(ctx, state, ImGui)

  local base_acc, hov_acc, act_acc, soft_acc = get_accent_colors(state, ImGui)



  -- 1. FIXED LIVE PREVIEW CARD (Sticky at top of tab)

  render_text_preview_card(ctx, state, ImGui, act_acc)



  -- 2. SCROLLABLE SETTINGS CARDS

  if ImGui.BeginChild(ctx, "TextSettingsScrollArea", 0, 0, 0) then

    -- FONT & AUTOSCROLL CARD

    local open_c1 = begin_control_box(ctx, state, ImGui, "txt_font_card")

    if open_c1 then

    render_section_header(ctx, ImGui, "ШРИФТ И ТИПОГРАФИКА", act_acc)



    local fonts_available = {

      "Segoe UI",

      "Arial",

      "Calibri",

      "Tahoma",

      "Trebuchet MS",

      "Verdana",

      "Consolas",

      "sans-serif"

    }



    local cur_font = state.text_font_family or "Segoe UI"

    ImGui.SetNextItemWidth(ctx, 220)

    local p_cols, p_vars = push_modern_combo_styles(ctx, ImGui, state)

    if ImGui.BeginCombo(ctx, "Тип шрифта", cur_font) then

      for _, f_name in ipairs(fonts_available) do

        local is_sel = (cur_font == f_name)

        if ImGui.Selectable(ctx, f_name, is_sel) then

          state.text_font_family = f_name

          state.row_heights = {}

          state.save_settings()

        end

      end

      ImGui.EndCombo(ctx)

    end

    pop_modern_combo_styles(ctx, ImGui, p_cols, p_vars)



    -- BASE FONT SIZE

    ImGui.Text(ctx, "Базовый размер шрифта (px):")

    local rv_size, new_size = render_modern_slider(ctx, state, ImGui, "font_sz", state.text_font_size or 18.0, 12.0, 36.0, "%.0f", act_acc, 260)

    if rv_size then

      state.text_font_size = new_size

      state.row_heights = {}

      state.save_settings()

    end



    -- AUTOSCROLL SECTION

    render_section_header(ctx, ImGui, "АВТОПРОКРУТКА И ПОЗИЦИЯ", act_acc)



    local pct = math.floor((state.scroll_center_ratio or 0.40) * 100)

    ImGui.Text(ctx, string.format("Позиция по высоте окна (%d%%):", pct))

    local rv_ratio, new_ratio = render_modern_slider(ctx, state, ImGui, "scroll_ratio", (state.scroll_center_ratio or 0.40) * 100, 5, 95, "%.0f%%", act_acc, 260)

    if rv_ratio then

      state.scroll_center_ratio = new_ratio / 100.0

      state.save_settings()

      state.need_calc_scroll_target = true

      state.last_centered_idx = -1

    end



    ImGui.Spacing(ctx)

    ImGui.Text(ctx, "Авто-скролл при ручном выборе (ЛКМ):")

    local scroll_modes = {

      { id = 1, name = "нет" },

      { id = 2, name = "при воспроизведении" },

      { id = 3, name = "всегда" },

    }

    local cur_scroll_mode = state.auto_scroll_mode or 2

    local cur_mode_label = "при воспроизведении"

    for _, sm in ipairs(scroll_modes) do

      if sm.id == cur_scroll_mode then

        cur_mode_label = sm.name

        break

      end

    end



    ImGui.SetNextItemWidth(ctx, 220)

    local p_cols_sm, p_vars_sm = push_modern_combo_styles(ctx, ImGui, state)

    if ImGui.BeginCombo(ctx, "##auto_scroll_mode_combo", cur_mode_label) then

      for _, sm in ipairs(scroll_modes) do

        local is_sel = (cur_scroll_mode == sm.id)

        if ImGui.Selectable(ctx, sm.name, is_sel) then

          state.auto_scroll_mode = sm.id

          state.save_settings()

        end

        if is_sel then

          ImGui.SetItemDefaultFocus(ctx)

        end

      end

      ImGui.EndCombo(ctx)

    end

    pop_modern_combo_styles(ctx, ImGui, p_cols_sm, p_vars_sm)

  end

  end_control_box(ctx, ImGui, open_c1)



  -- 2. ACTORS DISPLAY & COLORING CARD

  local open_c_act = begin_control_box(ctx, state, ImGui, "txt_actors_display_card")

  if open_c_act then

    render_section_header(ctx, ImGui, "ОТОБРАЖЕНИЕ И ЦВЕТА АКТЕРОВ В СТРОКЕ", act_acc)



    -- Toggle 1: Отображать актера в строке

    local rv_act_row, new_act_row = render_toggle_switch(ctx, state, ImGui, "txt_act_row", "Отображать актера в строке", state.show_actor_in_row, act_acc)

    if rv_act_row then

      state.show_actor_in_row = new_act_row

      state.row_heights = {}

      state.save_settings()

    end

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Показывает тег актера в начале каждой строки субтитра между таймингом и текстом реплики.")

    end



    -- Sub-options for Actor Tag Display (shown when toggle is active)

    if state.show_actor_in_row then

      ImGui.Indent(ctx, 24)



      ImGui.AlignTextToFramePadding(ctx)

      ImGui.Text(ctx, "Показывать:")

      ImGui.SameLine(ctx, 0, 10.0)



      local actor_display_options = {

        { id = 1, name = "Актер" },

        { id = 2, name = "Актер - Персонаж" },

      }

      local cur_mode = state.text_actor_display_mode or 1

      local cur_mode_str = (cur_mode == 2) and "Актер - Персонаж" or "Актер"



      ImGui.SetNextItemWidth(ctx, 190)

      local p_cols_dm, p_vars_dm = push_modern_combo_styles(ctx, ImGui, state)

      if ImGui.BeginCombo(ctx, "##actor_display_mode_combo", cur_mode_str) then

        for _, opt in ipairs(actor_display_options) do

          local is_sel = (cur_mode == opt.id)

          if ImGui.Selectable(ctx, opt.name, is_sel) then

            state.text_actor_display_mode = opt.id

            state.row_heights = {}

            state.save_settings()

          end

          if is_sel then

            ImGui.SetItemDefaultFocus(ctx)

          end

        end

        ImGui.EndCombo(ctx)

      end

      pop_modern_combo_styles(ctx, ImGui, p_cols_dm, p_vars_dm)



      if ImGui.IsItemHovered(ctx) then

        set_tooltip(ctx, state, ImGui, "Актер: выводит только имя актера.\nАктер - Персонаж: выводит имя актера и имя персонажа (при наличии).\nЕсли реплика общая для всех актеров, отображается 'Все'. Длинные имена сокращаются до 24 символов.")

      end



      -- Toggle: Подкрашивать имена актеров

      local rv_tint_act, new_tint_act = render_toggle_switch(ctx, state, ImGui, "txt_tint_act", "Подкрашивать имена актеров", state.text_tint_actor_names, act_acc)

      if rv_tint_act then

        state.text_tint_actor_names = new_tint_act

        state.save_settings()

      end

      if ImGui.IsItemHovered(ctx) then

        set_tooltip(ctx, state, ImGui, "Окрашивает тег [Имя] в строке персональным цветом актера из палитры.")

      end



      ImGui.Unindent(ctx, 24)

    end



    ImGui.Spacing(ctx)



    -- Toggle: Показывать CPS (символов в секунду)

    local rv_cps, new_cps = render_toggle_switch(ctx, state, ImGui, "txt_show_cps", "Показывать CPS (символов в секунду)", state.text_show_cps, act_acc)

    if rv_cps then

      state.text_show_cps = new_cps

      state.row_heights = {}

      state.save_settings()

    end

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Отображает темп речи (CPS — символов в секунду) в таблице строк субтитров между таймингом/актером и текстом.")

    end



    ImGui.Spacing(ctx)



    ImGui.Spacing(ctx)



    -- Toggle: Подкрашивать строки цветом актера

    local rv_tint_ln, new_tint_ln = render_toggle_switch(ctx, state, ImGui, "txt_tint_lines", "Подкрашивать строки цветом актера", state.text_tint_lines, act_acc)

    if rv_tint_ln then

      state.text_tint_lines = new_tint_ln

      state.save_settings()

    end

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Подкрашивает весь текст реплики цветом актера из палитры. Если выключено — строки отображаются выбранным цветом.")

    end



    if not state.text_tint_lines then

      ImGui.Indent(ctx, 24)

      ImGui.AlignTextToFramePadding(ctx)

      ImGui.Text(ctx, "Цвет текста строк:")

      ImGui.SameLine(ctx, 0, 10.0)



      local cur_tc = state.text_custom_color or { 175 / 255, 175 / 255, 175 / 255 }

      local tir = math.floor((cur_tc[1] or 0.68) * 255 + 0.5)

      local tig = math.floor((cur_tc[2] or 0.68) * 255 + 0.5)

      local tib = math.floor((cur_tc[3] or 0.68) * 255 + 0.5)

      local cur_t_rgb = ((tir & 0xFF) << 16) | ((tig & 0xFF) << 8) | (tib & 0xFF)



      ImGui.SetNextItemWidth(ctx, 160)

      local rv_tcol, new_t_rgb = ImGui.ColorEdit3(ctx, "##txt_custom_col", cur_t_rgb)

      if rv_tcol then

        local tr = ((new_t_rgb >> 16) & 0xFF) / 255

        local tg = ((new_t_rgb >> 8) & 0xFF) / 255

        local tb = (new_t_rgb & 0xFF) / 255

        state.text_custom_color = { tr, tg, tb }

        state.save_settings()

      end

      if ImGui.IsItemHovered(ctx) then

        set_tooltip(ctx, state, ImGui, "Выбор основного монохромного цвета текста строк субтитров, когда отключено подкрашивание цветом актера.")

      end



      ImGui.SameLine(ctx, 0, 8.0)

      if render_reset_pill_button(ctx, ImGui, "reset_txt_col", "Сбросить", 90.0) then

        state.text_custom_color = { 175 / 255, 175 / 255, 175 / 255 }

        state.save_settings()

      end

      if ImGui.IsItemHovered(ctx) then

        set_tooltip(ctx, state, ImGui, "Вернуть дефолтный нейтральный серый цвет (#AFAFAF)")

      end



      ImGui.Unindent(ctx, 24)

    end

  end

  end_control_box(ctx, ImGui, open_c_act)



  -- 3. ROW EMPHASIS & SMOOTHNESS CARD

  local open_c2 = begin_control_box(ctx, state, ImGui, "txt_emphasis_card")

  if open_c2 then

    render_section_header(ctx, ImGui, "ВЫДЕЛЕНИЕ ТЕКУЩЕЙ СТРОКИ", act_acc)



    local rv_larger, new_larger = render_toggle_switch(ctx, state, ImGui, "act_larger", "Увеличивать шрифт текущей строки", state.text_active_larger, act_acc)

    if rv_larger then

      state.text_active_larger = new_larger

      state.row_heights = {}

      state.save_settings()

    end



    if state.text_active_larger then

      ImGui.Indent(ctx, 24)

      ImGui.Text(ctx, "Масштаб шрифта:")

      local rv_scale, new_scale = render_modern_slider(ctx, state, ImGui, "act_scale", state.text_active_font_scale or 1.18, 1.05, 1.50, "%.2fx", act_acc, 236)

      if rv_scale then

        state.text_active_font_scale = new_scale

        state.row_heights = {}

        state.save_settings()

      end

      ImGui.Unindent(ctx, 24)

    end



    local rv_spacing, new_spacing = render_toggle_switch(ctx, state, ImGui, "act_spacing", "Увеличенные интервалы до и после текущей строки", state.text_active_spacing, act_acc)

    if rv_spacing then

      state.text_active_spacing = new_spacing

      state.save_settings()

    end



    if state.text_active_spacing then

      ImGui.Indent(ctx, 24)

      ImGui.Text(ctx, "Интервал строки (px):")

      local rv_spx, new_spx = render_modern_slider(ctx, state, ImGui, "act_spx", state.text_active_spacing_px or 8.0, 2.0, 24.0, "%.0f px", act_acc, 236)

      if rv_spx then

        state.text_active_spacing_px = new_spx

        state.save_settings()

      end

      ImGui.Unindent(ctx, 24)

    end



    ImGui.Text(ctx, "Яркость подсветки текущей строки:")

    local cur_br_pct = (state.text_highlight_brightness or 0.28) * 100

    local rv_br, new_br = render_modern_slider(ctx, state, ImGui, "hi_br", cur_br_pct, 12, 60, "%.0f%%", act_acc, 260)

    if rv_br then

      state.text_highlight_brightness = new_br / 100.0

      state.save_settings()

    end





    -- ALTERNATING ROWS SECTION (ЗЕБРА)

    render_section_header(ctx, ImGui, "ЧЕРЕДОВАНИЕ СТРОК В СПИСКЕ (ЗЕБРА)", act_acc)



    local rv_alt, new_alt = render_toggle_switch(ctx, state, ImGui, "alt_rows", "Чередование фона неактивных строк (зебра)", state.row_alternating_bg, act_acc)

    if rv_alt then

      state.row_alternating_bg = new_alt

      state.save_settings()

    end



    if state.row_alternating_bg then

      ImGui.Indent(ctx, 24)

      local cur_str_pct = (state.row_alternating_strength or 0.05) * 100

      ImGui.Text(ctx, string.format("Контраст зебры (%.0f%%):", cur_str_pct))

      local rv_astr, new_astr = render_modern_slider(ctx, state, ImGui, "alt_str", cur_str_pct, 1, 20, "%.0f%%", act_acc, 236)

      if rv_astr then

        state.row_alternating_strength = new_astr / 100.0

        state.save_settings()

      end

      ImGui.Unindent(ctx, 24)

    end



    -- SMOOTHNESS & TRANSITIONS SECTION

    render_section_header(ctx, ImGui, "ПЛАВНОСТЬ И УПРЕЖДЕНИЕ", act_acc)



    -- Toggle: Фиксированное упреждение

    local rv_fixed_lead, new_fixed_lead = render_toggle_switch(ctx, state, ImGui, "txt_fixed_lead_in", "Фиксированное упреждение", state.text_fixed_lead_in == true, act_acc)

    if rv_fixed_lead then

      state.text_fixed_lead_in = new_fixed_lead

      state.save_settings()

    end

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Если ВКЛЮЧЕНО — упреждение (подготовка следующей строки) срабатывает строго за указанное фиксированное время (сек).\nЕсли ВЫКЛЮЧЕНО — как только заканчивается текущая реплика, сразу же срабатывает упреждение для следующей реплики.")

    end



    ImGui.TextDisabled(ctx, "*Рекомендуется (ВЫКЛЮЧЕНО) при включенной синхронизации Удержания реплик.")



    if state.text_fixed_lead_in then

      ImGui.Indent(ctx, 24)

      ImGui.Text(ctx, "Упреждение перед репликой (сек):")

      local rv_lead, new_lead = render_modern_slider(ctx, state, ImGui, "lead_in", state.text_lead_in_time or 0.35, 0.0, 1.5, "%.2f с", act_acc, 236)

      if rv_lead then

        state.text_lead_in_time = new_lead

        state.save_settings()

      end

      ImGui.Unindent(ctx, 24)

    end



    ImGui.Spacing(ctx)



    -- Toggle: Синхронизировать удержание реплик с оверлеем

    local rv_sync_hold, new_sync_hold = render_toggle_switch(ctx, state, ImGui, "txt_sync_overlay_hold", "Синхронизировать удержание реплик с оверлеем", state.text_sync_overlay_hold ~= false, act_acc)

    if rv_sync_hold then

      state.text_sync_overlay_hold = new_sync_hold

      state.save_settings()

    end

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Если включены режимы удержания в оверлее (Только в паузах или Каскад), строка в списке остается активной на время удержания: прогресс-бар меняет цвет и отображается время удержания (+X.Xs).\nПри этом предпрокрутка к следующей реплике работает в соответствии с настройкой упреждения.")

    end



    ImGui.Spacing(ctx)



    local rv_sm, new_sm = render_toggle_switch(ctx, state, ImGui, "sm_scroll", "Плавная доводка прокрутки (Smooth Scroll)", state.smooth_scroll_enabled, act_acc)

    if rv_sm then

      state.smooth_scroll_enabled = new_sm

      state.save_settings()

    end



    if state.smooth_scroll_enabled then

      ImGui.Indent(ctx, 24)

      ImGui.Text(ctx, "Скорость доводки:")

      local rv_spd, new_spd = render_modern_slider(ctx, state, ImGui, "scroll_speed", state.smooth_scroll_speed or 14.0, 4.0, 30.0, "%.0f", act_acc, 236)

      if rv_spd then

        state.smooth_scroll_speed = new_spd

        state.save_settings()

      end

      ImGui.Unindent(ctx, 24)

    end

  end

  end_control_box(ctx, ImGui, open_c2)



  -- NOTE VIEW MODE CARD

  local open_c_note = begin_control_box(ctx, state, ImGui, "txt_note_view_card")

  if open_c_note then

    render_section_header(ctx, ImGui, "РЕЖИМ ФОКУСА: ОДНА СТРОКА (NOTE VIEW)", act_acc)



    local rv_wrap, new_wrap = render_toggle_switch(ctx, state, ImGui, "note_wrap", "Автоматический перенос строк", state.note_auto_wrap ~= false, act_acc)

    if rv_wrap then

      state.note_auto_wrap = new_wrap

      state.save_settings()

    end

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Разрешить перенос длинных фраз на 2-3 строки, если шрифт становится слишком мелким для одной строки.")

    end



    ImGui.Spacing(ctx)

    ImGui.Text(ctx, "Минимальный размер шрифта:")

    local rv_min_sz, new_min_sz = render_modern_slider(ctx, state, ImGui, "note_min_sz", state.note_min_font_size or 18.0, 12.0, 36.0, "%.0f px", act_acc, 260)

    if rv_min_sz then

      state.note_min_font_size = new_min_sz

      if (state.note_max_font_size or 72.0) < new_min_sz then

        state.note_max_font_size = new_min_sz

      end

      state.save_settings()

    end

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Минимальный размер шрифта при автомасштабировании текста под окно.")

    end



    ImGui.Spacing(ctx)

    ImGui.Text(ctx, "Максимальный размер шрифта:")

    local rv_max_sz, new_max_sz = render_modern_slider(ctx, state, ImGui, "note_max_sz", state.note_max_font_size or 72.0, 24.0, 96.0, "%.0f px", act_acc, 260)

    if rv_max_sz then

      state.note_max_font_size = new_max_sz

      if (state.note_min_font_size or 18.0) > new_max_sz then

        state.note_min_font_size = new_max_sz

      end

      state.save_settings()

    end

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Максимальный предел масштабирования для коротких реплик.")

    end



    ImGui.Spacing(ctx)

    local rv_act, new_act = render_toggle_switch(ctx, state, ImGui, "note_actor", "Отображать имя актера", state.note_show_actor ~= false, act_acc)

    if rv_act then

      state.note_show_actor = new_act

      state.save_settings()

    end

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Показывать цветной бейдж [Имя актера] в верхнем левом углу блока.")

    end



    ImGui.Spacing(ctx)

    local rv_prog, new_prog = render_toggle_switch(ctx, state, ImGui, "note_prog", "Отображать прогрессбар и удержание", state.note_show_progress ~= false, act_acc)

    if rv_prog then

      state.note_show_progress = new_prog

      state.save_settings()

    end

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Показывать полоску прогресса воспроизведения текущей строки и индикатор удержания с таймером (+X.Xs).")

    end

  end

  end_control_box(ctx, ImGui, open_c_note)



  -- 3. RESET BUTTON CARD

  local open_c3 = begin_control_box(ctx, state, ImGui, "txt_reset_card", 44.0)

  if open_c3 then

    local btn_w = 260.0

    if render_reset_pill_button(ctx, ImGui, "reset_text_settings", "Сбросить настройки текста", btn_w, nil, true) then

      state.text_font_family = "Segoe UI"

      state.text_font_size = 18.0

      state.scroll_center_ratio = 0.40

      state.text_active_larger = true

      state.text_active_font_scale = 1.18

      state.text_active_spacing = true

      state.text_active_spacing_px = 8.0

      state.text_highlight_brightness = 0.28

      state.text_fixed_lead_in = false

      state.text_lead_in_time = 0.35

      state.smooth_scroll_enabled = true

      state.smooth_scroll_speed = 14.0

      state.row_alternating_bg = false

      state.row_alternating_strength = 0.07

      state.focus_mode = false

      state.auto_scroll_mode = 3

      state.show_actor_in_row = false

      state.text_show_cps = false

      state.text_sync_overlay_hold = true

      state.text_actor_display_mode = 1

      state.text_tint_lines = true

      state.text_custom_color = { 175 / 255, 175 / 255, 175 / 255 }

      state.text_tint_actor_names = true

      state.note_auto_wrap = true

      state.note_min_font_size = 18.0

      state.note_max_font_size = 72.0

      state.note_show_actor = true

      state.note_show_progress = true

      state.row_heights = {}

      state.save_settings()

    end

  end

  end_control_box(ctx, ImGui, open_c3)

  ImGui.Spacing(ctx)

  ui.handle_file_drop(ctx, state, ImGui)

    ImGui.EndChild(ctx)

  end

end



-- Render Tab 4: Overlay Settings

function ui.render_tab_overlay(ctx, state, ImGui)

  local base_acc, hov_acc, act_acc, soft_acc = get_accent_colors(state, ImGui)



  -- 0. MASTER CONTROL CARD: Quick Launch & Topmost setting

  local open_ov_master = begin_control_box(ctx, state, ImGui, "ov_card_master")

  if open_ov_master then

    render_section_header(ctx, ImGui, "УПРАВЛЕНИЕ ОВЕРЛЕЯМИ", act_acc)



    local btn_scale = math.max(0.85, ((state and state.ui_font_size) or 11.0) / 11.0)

    local ov_btn_w = math.floor(220 * btn_scale)

    local ov_btn_h = math.floor(34 * btn_scale)



    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 6.0)

    if state.overlay_enabled then

      ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x8A2C2CEE)

      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0xA83838EE)

      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0xC04040EE)

      if ImGui.Button(ctx, "✕ Выключить Хардсаб###master_btn_hardsub", ov_btn_w, ov_btn_h) then

        state.overlay_enabled = false

        state.save_settings()

      end

      ImGui.PopStyleColor(ctx, 3)

    else

      ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x1E5E3AEE)

      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x2A7C4DEE)

      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x36965DEE)

      if ImGui.Button(ctx, "▶ Включить Хардсаб###master_btn_hardsub", ov_btn_w, ov_btn_h) then

        state.overlay_enabled = true

        state.save_settings()

      end

      ImGui.PopStyleColor(ctx, 3)

    end



    ImGui.SameLine(ctx, 0, 16.0)

    if state.timer_overlay_enabled then

      ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x8A2C2CEE)

      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0xA83838EE)

      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0xC04040EE)

      if ImGui.Button(ctx, "✕ Выключить таймер###master_btn_timer", ov_btn_w, ov_btn_h) then

        state.timer_overlay_enabled = false

        state.save_settings()

      end

      ImGui.PopStyleColor(ctx, 3)

    else

      ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x1E5E3AEE)

      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x2A7C4DEE)

      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x36965DEE)

      if ImGui.Button(ctx, "▶ Включить таймер###master_btn_timer", ov_btn_w, ov_btn_h) then

        state.timer_overlay_enabled = true

        state.save_settings()

      end

      ImGui.PopStyleColor(ctx, 3)

    end

    ImGui.PopStyleVar(ctx, 1)



    ImGui.Spacing(ctx)

    local rv_top, new_top = ImGui.Checkbox(ctx, "Поверх всех окон (Always on top)###ov_master_top", state.overlay_always_on_top or false)

    if rv_top then

      state.overlay_always_on_top = new_top

      state.save_settings()

    end

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Отображать окна оверлеев (Хардсаб и Таймер) поверх всех окон Windows и REAPER.")

    end

  end

  end_control_box(ctx, ImGui, open_ov_master)



  -- 1. OVERLAY RULES CARD

  local open_ov1 = begin_control_box(ctx, state, ImGui, "ov_card_rules")

  if open_ov1 then

    render_section_header(ctx, ImGui, "ПРАВИЛА ОТОБРАЖЕНИЯ РЕПЛИК ХАРДСАБА", act_acc)



    local rv_all, new_all = render_toggle_switch(ctx, state, ImGui, "ov_all", "Показывать все реплики (игнорировать фильтр)", state.overlay_show_all_actors, act_acc)

    if rv_all then

      state.overlay_show_all_actors = new_all

      state.save_settings()

    end

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Включено: в оверлее выводятся реплики всех персонажей.\nВыключено: только реплики выбранных актеров.")

    end



    local rv_prev, new_prev = render_toggle_switch(ctx, state, ImGui, "ov_prev", "Предпоказ следующей реплики (режим телесуфлера)", state.overlay_show_next_preview, act_acc)

    if rv_prev then

      state.overlay_show_next_preview = new_prev

      state.save_settings()

    end

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Отображает под прогресс-баром следующую реплику меньшим шрифтом.\nВ паузах плавно подготавливает грядущую строку и ведет обратный отсчет.")

    end



    local rv_hide_prog, new_hide_prog = render_toggle_switch(ctx, state, ImGui, "ov_hide_prog", "Скрыть прогресс реплики", state.overlay_hide_progress, act_acc)

    if rv_hide_prog then

      state.overlay_hide_progress = new_hide_prog

      state.save_settings()

    end

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Убирает полосу прогресса текущей реплики и обратного отсчета из окна оверлея.")

    end



    local single_actor_filtered = (not state.overlay_show_all_actors and #state.selected_actors == 1)

    local rv_showact, new_showact = render_toggle_switch(ctx, state, ImGui, "ov_act", "Отображать имя актера в оверлее", state.overlay_show_actor, act_acc)

    if rv_showact then

      state.overlay_show_actor = new_showact

      state.save_settings()

    end

    if single_actor_filtered then

      ImGui.SameLine(ctx)

      ImGui.TextDisabled(ctx, "(скрыто, т.к. выбран только один актер)")

    end



    if state.overlay_show_actor then

      ImGui.Indent(ctx, 24)

      local actor_positions = { "Сверху", "Слева" }

      local cur_pos_idx = (state.overlay_actor_position == "left" or state.overlay_actor_position == 2) and 2 or 1

      ImGui.SetNextItemWidth(ctx, 160)

      local p_cols, p_vars = push_modern_combo_styles(ctx, ImGui, state)

      if ImGui.BeginCombo(ctx, "Положение имени актера", actor_positions[cur_pos_idx]) then

        for idx, pos_name in ipairs(actor_positions) do

          local is_sel = (cur_pos_idx == idx)

          if ImGui.Selectable(ctx, pos_name, is_sel) then

            state.overlay_actor_position = (idx == 2) and "left" or "top"

            state.save_settings()

          end

        end

        ImGui.EndCombo(ctx)

      end

      pop_modern_combo_styles(ctx, ImGui, p_cols, p_vars)

      if ImGui.IsItemHovered(ctx) then

        set_tooltip(ctx, state, ImGui, "Сверху: имя актера выводится отдельной строкой над репликой.\nСлева: имя актера выводится слева от реплики (в строку или сеткой).")

      end



      if state.overlay_actor_position == "left" then

        local left_layouts = { "Строка", "Сетка" }

        local cur_layout_idx = (state.overlay_actor_left_layout == "line") and 1 or 2

        ImGui.SetNextItemWidth(ctx, 160)

        local l_cols, l_vars = push_modern_combo_styles(ctx, ImGui, state)

        if ImGui.BeginCombo(ctx, "Режим отображения слева", left_layouts[cur_layout_idx]) then

          for idx, l_name in ipairs(left_layouts) do

            local is_sel = (cur_layout_idx == idx)

            if ImGui.Selectable(ctx, l_name, is_sel) then

              state.overlay_actor_left_layout = (idx == 1) and "line" or "grid"

              state.save_settings()

            end

          end

          ImGui.EndCombo(ctx)

        end

        pop_modern_combo_styles(ctx, ImGui, l_cols, l_vars)

        if ImGui.IsItemHovered(ctx) then

          set_tooltip(ctx, state, ImGui, "Строка: имя актера пишется прямо перед репликой ([Актер] Текст).\nСетка: имя актера выравнивается в отдельной левой колонке по центру двух строк, а текст центрируется в оставшейся области.")

        end



        if state.overlay_actor_left_layout ~= "line" then

          ImGui.Text(ctx, "Отступ от имени актера до текста (px):")

          local rv_gap, new_gap = render_modern_slider(ctx, state, ImGui, "ov_act_gap", state.overlay_actor_gap or 12.0, 0.0, 60.0, "%.0f px", act_acc, 260)

          if rv_gap then

            state.overlay_actor_gap = new_gap

            state.save_settings()

          end

          if ImGui.IsItemHovered(ctx) then

            set_tooltip(ctx, state, ImGui, "Ширина зазора между колонкой с именем актера и колонкой с текстом реплики.")

          end

        end

      end

      ImGui.Unindent(ctx, 24)

    end



    local rv_tint, new_tint = render_toggle_switch(ctx, state, ImGui, "ov_tint", "Подкрашивать реплики цветом актера", state.overlay_tint_lines, act_acc)

    if rv_tint then

      state.overlay_tint_lines = new_tint

      state.save_settings()

    end

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Текст реплики подкрашивается цветом соответствующего актера (пастельный оттенок).")

    end



    if state.overlay_tint_lines then

      ImGui.Indent(ctx, 24)

      local rv_own, new_own = render_toggle_switch(ctx, state, ImGui, "ov_own", "Подкрашивать только свои реплики", state.overlay_tint_only_filtered, act_acc)

      if rv_own then

        state.overlay_tint_only_filtered = new_own

        state.save_settings()

      end

      if ImGui.IsItemHovered(ctx) then

        set_tooltip(ctx, state, ImGui, "Цветом выделяются только реплики актеров, выбранных в фильтре.\nОстальные реплики отображаются стандартным белым цветом.")

      end

      ImGui.Unindent(ctx, 24)

    end



    render_section_header(ctx, ImGui, "УДЕРЖАНИЕ И ТЕМП РЕПЛИК (CPS)", act_acc)



    -- Combo: Режим удержания реплик

    ImGui.AlignTextToFramePadding(ctx)

    ImGui.Text(ctx, "Режим удержания реплик:")

    ImGui.SameLine(ctx, 0, 10.0)



    local hold_modes = {

      { id = 1, name = "Выключен (строгий тайминг)" },

      { id = 2, name = "Только в паузах (без сдвига)" },

      { id = 3, name = "Каскадный сдвиг с наложением" },

    }

    local cur_hm = state.overlay_hold_mode or 2

    local cur_hm_label = "Только в паузах (без сдвига)"

    for _, hm in ipairs(hold_modes) do

      if hm.id == cur_hm then

        cur_hm_label = hm.name

        break

      end

    end



    ImGui.SetNextItemWidth(ctx, 280)

    local p_cols_hm, p_vars_hm = push_modern_combo_styles(ctx, ImGui, state)

    if ImGui.BeginCombo(ctx, "##overlay_hold_mode_combo", cur_hm_label) then

      for _, hm in ipairs(hold_modes) do

        local is_sel = (cur_hm == hm.id)

        if ImGui.Selectable(ctx, hm.name, is_sel) then

          state.overlay_hold_mode = hm.id

          if state.invalidate_virtual_cache then

            state.invalidate_virtual_cache()

          end

          state.save_settings()

        end

        if is_sel then

          ImGui.SetItemDefaultFocus(ctx)

        end

      end

      ImGui.EndCombo(ctx)

    end

    pop_modern_combo_styles(ctx, ImGui, p_cols_hm, p_vars_hm)

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Выключен: реплика исчезает строго по таймингу региона.\nТолько в паузах: длинная реплика (высокий CPS) задерживается на экране во время паузы перед следующей.\nКаскадный сдвиг с наложением: реплика может накладываться на следующую, а следующая каскадно сдвигается вперед до ближайшей паузы.")

    end



    if state.overlay_hold_mode and state.overlay_hold_mode > 1 then

      ImGui.Indent(ctx, 24)



      ImGui.Text(ctx, "Целевой темп речи (CPS):")

      local rv_tcps, new_tcps = render_modern_slider(ctx, state, ImGui, "ov_target_cps", state.overlay_target_cps or 17.0, 8.0, 24.0, "%.1f симв/сек", act_acc, 260)

      if rv_tcps then

        state.overlay_target_cps = new_tcps

        if state.invalidate_virtual_cache then

          state.invalidate_virtual_cache()

        end

        state.save_settings()

      end

      if ImGui.IsItemHovered(ctx) then

        set_tooltip(ctx, state, ImGui, "Комфортная скорость чтения диктора. Если темп реплики быстрее этого значения, оверлей продлевает показ для удобного прочтения.\nБазовое значение: 17.0 симв/сек.")

      end



      ImGui.Text(ctx, "Макс. удержание на реплику:")

      local rv_mh, new_mh = render_modern_slider(ctx, state, ImGui, "ov_max_hold", state.overlay_max_hold or 0.7, 0.3, 4.0, "%.1f сек", act_acc, 260)

      if rv_mh then

        state.overlay_max_hold = new_mh

        if state.invalidate_virtual_cache then

          state.invalidate_virtual_cache()

        end

        state.save_settings()

      end

      if ImGui.IsItemHovered(ctx) then

        set_tooltip(ctx, state, ImGui, "Максимальное дополнительное время, которое может быть добавлено к показу одной реплики.")

      end



      if state.overlay_hold_mode == 3 then

        ImGui.Text(ctx, "Предел накопления сдвига (каскад):")

        local rv_md, new_md = render_modern_slider(ctx, state, ImGui, "ov_max_drift", state.overlay_max_drift or 2.5, 0.5, 5.0, "%.1f сек", act_acc, 260)

        if rv_md then

          state.overlay_max_drift = new_md

          if state.invalidate_virtual_cache then

            state.invalidate_virtual_cache()

          end

          state.save_settings()

        end

        if ImGui.IsItemHovered(ctx) then

          set_tooltip(ctx, state, ImGui, "Ограничивает суммарное отставание оверлея от таймлайна при непрерывной череде длинных фраз без пауз.")

        end

      end



      local rv_sdb, new_sdb = render_toggle_switch(ctx, state, ImGui, "ov_drift_badge", "Показывать бейдж отставания (+X.Xs)", state.overlay_show_drift_badge, act_acc)

      if rv_sdb then

        state.overlay_show_drift_badge = new_sdb

        state.save_settings()

      end

      if ImGui.IsItemHovered(ctx) then

        set_tooltip(ctx, state, ImGui, "Отображает в верхнем правом углу оверлея янтарный бейдж со временем отставания, когда реплика находится в фазе овертайма.")

      end



      ImGui.Unindent(ctx, 24)

    end

  end

  end_control_box(ctx, ImGui, open_ov1)



  -- 2. FLOATING TIMER OVERLAY CARD

  local open_ov_timer = begin_control_box(ctx, state, ImGui, "ov_card_timer")

  if open_ov_timer then

    render_section_header(ctx, ImGui, "НАСТРОЙКИ ОКНА ТАЙМЕРА", act_acc)



    ImGui.Text(ctx, "Формат отображения таймкода:")

    local fmt_options = {

      { id = 2, name = "ЧЧ:ММ:СС.дд" },

      { id = 5, name = "ЧЧ:ММ:СС.д" },

      { id = 8, name = "ЧЧ:ММ:СС" },

      { id = 1, name = "ММ:СС.дд" },

      { id = 4, name = "ММ:СС.д" },

      { id = 7, name = "ММ:СС" },

      { id = 3, name = "СС.дд" },

      { id = 6, name = "СС.д" },

    }

    local cur_fmt = state.timer_overlay_format or 1

    local cur_fmt_name = "ММ:СС.дд"

    for _, opt in ipairs(fmt_options) do

      if opt.id == cur_fmt then

        cur_fmt_name = opt.name

        break

      end

    end



    ImGui.SetNextItemWidth(ctx, 200)

    if ImGui.BeginCombo(ctx, "##timer_format_combo", cur_fmt_name) then

      for _, opt in ipairs(fmt_options) do

        local is_sel = (cur_fmt == opt.id)

        if ImGui.Selectable(ctx, opt.name, is_sel) then

          state.timer_overlay_format = opt.id

          state.save_settings()

        end

        if is_sel then ImGui.SetItemDefaultFocus(ctx) end

      end

      ImGui.EndCombo(ctx)

    end



    ImGui.Spacing(ctx)

    ImGui.Text(ctx, "Гарнитура шрифта таймера:")

    local fonts_list = { "Segoe UI", "Roboto", "Arial", "Impact", "Consolas", "Calibri", "Trebuchet MS", "Verdana" }

    local cur_font = state.timer_overlay_font_family or "Segoe UI"

    ImGui.SetNextItemWidth(ctx, 220)

    if ImGui.BeginCombo(ctx, "##timer_font_combo", cur_font) then

      for _, f_name in ipairs(fonts_list) do

        local is_sel = (cur_font == f_name)

        if ImGui.Selectable(ctx, f_name, is_sel) then

          state.timer_overlay_font_family = f_name

          state.save_settings()

        end

        if is_sel then ImGui.SetItemDefaultFocus(ctx) end

      end

      ImGui.EndCombo(ctx)

    end



    ImGui.Spacing(ctx)

    ImGui.Text(ctx, "Цветовая индикация таймера:")

    local cm_options = {

      { id = 1, name = "Нет" },

      { id = 2, name = "Включено" },

    }

    local cur_mode = (state.timer_overlay_color_mode == 2 or state.timer_overlay_color_mode == 3) and 2 or 1

    local cur_mode_label = (cur_mode == 2) and "Включено" or "Нет"



    ImGui.SetNextItemWidth(ctx, 200)

    if ImGui.BeginCombo(ctx, "##timer_color_mode_combo", cur_mode_label) then

      for _, opt in ipairs(cm_options) do

        local is_sel = (cur_mode == opt.id)

        if ImGui.Selectable(ctx, opt.name, is_sel) then

          state.timer_overlay_color_mode = opt.id

          state.save_settings()

        end

        if is_sel then ImGui.SetItemDefaultFocus(ctx) end

      end

      ImGui.EndCombo(ctx)

    end

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Нет: постоянный цвет (выбирается ниже, по умолчанию белый).\nВключено: динамический цвет по статусу REAPER (Красный — запись, Зеленый — воспроизведение, Янтарный — пауза, Светлый — стоп).")

    end



    if cur_mode == 1 then

      ImGui.Spacing(ctx)

      ImGui.Text(ctx, "Цвет шрифта таймера:")

      local col = state.timer_custom_color or { 1.0, 1.0, 1.0, 1.0 }

      local ir = math.floor((col[1] or 1.0) * 255 + 0.5)

      local ig = math.floor((col[2] or 1.0) * 255 + 0.5)

      local ib = math.floor((col[3] or 1.0) * 255 + 0.5)

      local cur_rgb = ((ir & 0xFF) << 16) | ((ig & 0xFF) << 8) | (ib & 0xFF)

      ImGui.SetNextItemWidth(ctx, 160)

      local rv_col, new_rgb = ImGui.ColorEdit3(ctx, "##timer_custom_col_edit", cur_rgb)

      if rv_col then

        state.timer_custom_color = {

          ((new_rgb >> 16) & 0xFF) / 255,

          ((new_rgb >> 8) & 0xFF) / 255,

          (new_rgb & 0xFF) / 255,

          1.0

        }

        state.save_settings()

      end

      if ImGui.IsItemHovered(ctx) then

        set_tooltip(ctx, state, ImGui, "Постоянный цвет текста таймера (по умолчанию белый).")

      end

    end



    ImGui.Spacing(ctx)

    local cur_t_alpha_pct = (state.timer_overlay_bg_alpha or 0.75) * 100

    ImGui.Text(ctx, string.format("Прозрачность фона таймера (%.0f%%):", cur_t_alpha_pct))

    local rv_t_alpha, new_t_alpha = render_modern_slider(ctx, state, ImGui, "timer_ov_alpha", cur_t_alpha_pct, 0.0, 100.0, "%.0f%%", act_acc, 260)

    if rv_t_alpha then

      state.timer_overlay_bg_alpha = new_t_alpha / 100.0

      state.save_settings()

    end



    local t_bg_c = state.timer_overlay_bg_color or { 0.0, 0.0, 0.0, 0.75 }

    local t_bg_ir = math.floor((t_bg_c[1] or 0.0) * 255 + 0.5)

    local t_bg_ig = math.floor((t_bg_c[2] or 0.0) * 255 + 0.5)

    local t_bg_ib = math.floor((t_bg_c[3] or 0.0) * 255 + 0.5)

    local cur_t_bg_rgb = ((t_bg_ir & 0xFF) << 16) | ((t_bg_ig & 0xFF) << 8) | (t_bg_ib & 0xFF)

    ImGui.SetNextItemWidth(ctx, 160)

    local rv_t_bgcol, new_t_bg_rgb = ImGui.ColorEdit3(ctx, "Цвет фона таймера", cur_t_bg_rgb)

    if rv_t_bgcol then

      if not state.timer_overlay_bg_color then state.timer_overlay_bg_color = { 0.0, 0.0, 0.0, 0.75 } end

      state.timer_overlay_bg_color[1] = ((new_t_bg_rgb >> 16) & 0xFF) / 255

      state.timer_overlay_bg_color[2] = ((new_t_bg_rgb >> 8) & 0xFF) / 255

      state.timer_overlay_bg_color[3] = (new_t_bg_rgb & 0xFF) / 255

      state.save_settings()

    end

  end

  end_control_box(ctx, ImGui, open_ov_timer)



  -- 2. TYPOGRAPHY & APPEARANCE CARD

  local open_ov2 = begin_control_box(ctx, state, ImGui, "ov_card_style")

  if open_ov2 then

    render_section_header(ctx, ImGui, "РАЗМЕРЫ ШРИФТОВ ХАРДСАБА", act_acc)



    ImGui.Text(ctx, "Размер текста реплики хардсаба (px):")

    local rv_fsize, new_fsize = render_modern_slider(ctx, state, ImGui, "ov_fsize", state.overlay_font_size or 24.0, 14.0, 96.0, "%.0f", act_acc, 260)

    if rv_fsize then

      state.overlay_font_size = new_fsize

      state.save_settings()

    end



    ImGui.Text(ctx, "Размер шрифта актера (px):")

    local rv_act_fsize, new_act_fsize = render_modern_slider(ctx, state, ImGui, "ov_act_fsize", state.overlay_actor_font_size or 18.0, 10.0, 72.0, "%.0f", act_acc, 260)

    if rv_act_fsize then

      state.overlay_actor_font_size = new_act_fsize

      state.save_settings()

    end



    ImGui.Text(ctx, "Размер текста следующей реплики (px):")

    local rv_nxt_fsize, new_nxt_fsize = render_modern_slider(ctx, state, ImGui, "ov_nxt_fsize", state.overlay_next_font_size or 16.0, 10.0, 72.0, "%.0f", act_acc, 260)

    if rv_nxt_fsize then

      state.overlay_next_font_size = new_nxt_fsize

      state.save_settings()

    end



    render_section_header(ctx, ImGui, "ВНЕШНИЙ ВИД И ЦВЕТА ХАРДСАБА", act_acc)



    local cur_alpha_pct = (state.overlay_bg_alpha or 0.75) * 100

    ImGui.Text(ctx, string.format("Прозрачность фона хардсаба (%.0f%%):", cur_alpha_pct))

    local rv_alpha, new_alpha = render_modern_slider(ctx, state, ImGui, "ov_alpha", cur_alpha_pct, 0.0, 100.0, "%.0f%%", act_acc, 260)

    if rv_alpha then

      state.overlay_bg_alpha = new_alpha / 100.0

      state.save_settings()

    end



    local bg_c = state.overlay_bg_color or { 0.0, 0.0, 0.0, 0.75 }

    local bg_ir = math.floor((bg_c[1] or 0.0) * 255 + 0.5)

    local bg_ig = math.floor((bg_c[2] or 0.0) * 255 + 0.5)

    local bg_ib = math.floor((bg_c[3] or 0.0) * 255 + 0.5)

    local cur_bg_rgb = ((bg_ir & 0xFF) << 16) | ((bg_ig & 0xFF) << 8) | (bg_ib & 0xFF)

    ImGui.SetNextItemWidth(ctx, 160)

    local rv_bgcol, new_bg_rgb = ImGui.ColorEdit3(ctx, "Цвет фона хардсаба", cur_bg_rgb)

    if rv_bgcol then

      state.overlay_bg_color[1] = ((new_bg_rgb >> 16) & 0xFF) / 255

      state.overlay_bg_color[2] = ((new_bg_rgb >> 8) & 0xFF) / 255

      state.overlay_bg_color[3] = (new_bg_rgb & 0xFF) / 255

      state.save_settings()

    end



    local txt_c = state.overlay_text_color or { 1.0, 1.0, 1.0, 1.0 }

    local txt_ir = math.floor((txt_c[1] or 1.0) * 255 + 0.5)

    local txt_ig = math.floor((txt_c[2] or 1.0) * 255 + 0.5)

    local txt_ib = math.floor((txt_c[3] or 1.0) * 255 + 0.5)

    local cur_txt_rgb = ((txt_ir & 0xFF) << 16) | ((txt_ig & 0xFF) << 8) | (txt_ib & 0xFF)

    ImGui.SetNextItemWidth(ctx, 160)

    local rv_txtcol, new_txt_rgb = ImGui.ColorEdit3(ctx, "Цвет текста реплики хардсаба", cur_txt_rgb)

    if rv_txtcol then

      state.overlay_text_color[1] = ((new_txt_rgb >> 16) & 0xFF) / 255

      state.overlay_text_color[2] = ((new_txt_rgb >> 8) & 0xFF) / 255

      state.overlay_text_color[3] = (new_txt_rgb & 0xFF) / 255

      state.save_settings()

    end



    local alignments = { "Слева", "По центру", "Справа" }

    ImGui.SetNextItemWidth(ctx, 160)

    local p_cols, p_vars = push_modern_combo_styles(ctx, ImGui, state)

    if ImGui.BeginCombo(ctx, "Выравнивание текста хардсаба", alignments[(state.overlay_align or 1) + 1]) then

      for idx, name in ipairs(alignments) do

        if ImGui.Selectable(ctx, name, (state.overlay_align == idx - 1)) then

          state.overlay_align = idx - 1

          state.save_settings()

        end

      end

      ImGui.EndCombo(ctx)

    end

    pop_modern_combo_styles(ctx, ImGui, p_cols, p_vars)

  end

  end_control_box(ctx, ImGui, open_ov2)



  -- 3. RESET BUTTON CARD

  local open_ov3 = begin_control_box(ctx, state, ImGui, "ov_card_reset", 44.0)

  if open_ov3 then

    local btn_w = 260.0

    if render_reset_pill_button(ctx, ImGui, "reset_overlay_fonts", "Сбросить настройки оверлеев", btn_w, nil, true) then

      state.overlay_font_size = 24.0

      state.overlay_actor_font_size = 18.0

      state.overlay_next_font_size = 16.0

      state.overlay_always_on_top = false

      state.overlay_show_all_actors = true

      state.overlay_show_actor = true

      state.overlay_actor_position = "top"

      state.overlay_actor_left_layout = "grid"

      state.overlay_actor_gap = 12.0

      state.overlay_tint_lines = false

      state.overlay_hold_mode = 2

      state.overlay_target_cps = 17.0

      state.overlay_max_hold = 0.7

      state.overlay_max_drift = 2.5

      state.overlay_show_drift_badge = true

      state.timer_overlay_bg_alpha = 0.75

      state.timer_overlay_bg_color = { 0.0, 0.0, 0.0, 0.75 }

      state.save_settings()

    end

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Возвращает настройки хардсаба и таймера к значениям по умолчанию.")

    end

  end

  end_control_box(ctx, ImGui, open_ov3)

  ImGui.Spacing(ctx)

  ImGui.TextDisabled(ctx, "Подсказка: Окно оверлея можно перемещать по экрану за фон и изменять размер за правый нижний угол.")

  ui.handle_file_drop(ctx, state, ImGui)

end



-- Render Tab 5: General Settings (Общие настройки)

function ui.render_tab_general(ctx, state, ImGui)

  local base_acc, hov_acc, act_acc, soft_acc = get_accent_colors(state, ImGui)



  -- 1. ACCENT COLOR SECTION (New requested feature)

  local open_g1 = begin_control_box(ctx, state, ImGui, "gen_card_accent")

  if open_g1 then

    render_section_header(ctx, ImGui, "АКЦЕНТНЫЙ ЦВЕТ ИНТЕРФЕЙСА", act_acc)



    ImGui.Text(ctx, "Цвет акцентных кнопок, ползунков и чекбоксов:")

    ImGui.Spacing(ctx)



    -- Row 1: Presets

    ImGui.AlignTextToFramePadding(ctx)

    ImGui.TextDisabled(ctx, "Пресеты:")

    ImGui.SameLine(ctx, 0, 8)



    local presets = {

      { name = "Черный", rgb = { 35 / 255, 35 / 255, 35 / 255 }, col = 0x232323FF },

      { name = "Изумруд", rgb = { 0.14, 0.48, 0.30 }, col = 0x247A4DFF },

      { name = "Синий", rgb = { 0.18, 0.40, 0.68 }, col = 0x2E66ADFF },

      { name = "Бирюза", rgb = { 0.10, 0.50, 0.50 }, col = 0x1A8080FF },

      { name = "Янтарь", rgb = { 0.68, 0.42, 0.14 }, col = 0xAD6B24FF },

      { name = "Пурпур", rgb = { 0.44, 0.28, 0.64 }, col = 0x7047A3FF },

    }



    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 4.0)

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, 1.0)

    ImGui.PushStyleColor(ctx, ImGui.Col_Border, 0xCCCCCC66)

    for _, pr in ipairs(presets) do

      ImGui.PushStyleColor(ctx, ImGui.Col_Button, pr.col)

      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, pr.col)

      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, pr.col)

      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFFFFFFFF)

      if ImGui.Button(ctx, pr.name .. "##pr_" .. pr.name) then

        state.accent_color = { pr.rgb[1], pr.rgb[2], pr.rgb[3] }

        state.save_settings()

      end

      ImGui.PopStyleColor(ctx, 4)

      ImGui.SameLine(ctx, 0, 6)

    end

    ImGui.NewLine(ctx)

    ImGui.PopStyleColor(ctx, 1)

    ImGui.PopStyleVar(ctx, 2)



    -- Row 2: Custom color picker

    ImGui.AlignTextToFramePadding(ctx)

    ImGui.TextDisabled(ctx, "Задать свой цвет:")

    ImGui.SameLine(ctx, 0, 8)



    local cur_acc = state.accent_color or { 35 / 255, 35 / 255, 35 / 255 }

    local ir = math.floor((cur_acc[1] or (35 / 255)) * 255 + 0.5)

    local ig = math.floor((cur_acc[2] or (35 / 255)) * 255 + 0.5)

    local ib = math.floor((cur_acc[3] or (35 / 255)) * 255 + 0.5)

    local cur_rgb = ((ir & 0xFF) << 16) | ((ig & 0xFF) << 8) | (ib & 0xFF)



    ImGui.SetNextItemWidth(ctx, 180)

    local rv_acc, new_rgb = ImGui.ColorEdit3(ctx, "##main_accent_picker", cur_rgb)

    if rv_acc then

      local r = ((new_rgb >> 16) & 0xFF) / 255

      local g = ((new_rgb >> 8) & 0xFF) / 255

      local b = (new_rgb & 0xFF) / 255

      state.accent_color = { r, g, b }

      state.save_settings()

    end



    -- Palette options for control boxes

    render_section_header(ctx, ImGui, "СТИЛЬ ВЫДЕЛЕНИЯ БЛОКОВ ИНТЕРФЕЙСА", act_acc)

    ImGui.Text(ctx, "Выберите вариант фоновой палитры для карточек интерфейса:")



    local cur_pal = state.control_box_palette or 1

    local pal_names = {

      "Графит",

      "Легкая тонировка",

      "Умеренная тонировка"

    }



    ImGui.SetNextItemWidth(ctx, 320)

    local p_cols, p_vars = push_modern_combo_styles(ctx, ImGui, state)

    if ImGui.BeginCombo(ctx, "##combo_ctrl_pal", pal_names[cur_pal]) then

      for idx, p_label in ipairs(pal_names) do

        local is_sel = (cur_pal == idx)

        if ImGui.Selectable(ctx, p_label, is_sel) then

          state.control_box_palette = idx

          state.save_settings()

        end

      end

      ImGui.EndCombo(ctx)

    end

    pop_modern_combo_styles(ctx, ImGui, p_cols, p_vars)

  end

  end_control_box(ctx, ImGui, open_g1)



  -- 2. STARTUP INTEGRATION SECTION

  local open_g2 = begin_control_box(ctx, state, ImGui, "gen_card_startup")

  if open_g2 then

    render_section_header(ctx, ImGui, "ИНТЕГРАЦИЯ С REAPER", act_acc)



    if state.startup_enabled == nil then

      state.startup_enabled = actions.is_startup_enabled()

    end

    local rv_st, new_st = render_toggle_switch(ctx, state, ImGui, "startup_sw", "Автоматически открывать плагин при запуске REAPER", state.startup_enabled, act_acc)

    if rv_st then

      state.startup_enabled = new_st

      actions.set_startup_enabled(new_st)

    end

    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x8892B0FF)

    ImGui.Text(ctx, "  Управляет автозапуском через Scripts/__startup.lua (окно открывается при старте REAPER).")

    ImGui.PopStyleColor(ctx, 1)



    ImGui.Spacing(ctx)

    ImGui.Separator(ctx)

    ImGui.Spacing(ctx)



    if state.toolbar_button_enabled == nil then

      state.toolbar_button_enabled = actions.is_toolbar_button_enabled()

    end

    local rv_tb, new_tb = render_toggle_switch(ctx, state, ImGui, "toolbar_sw", "Кнопка NutNotes на главной панели инструментов REAPER", state.toolbar_button_enabled, act_acc)

    if rv_tb then

      state.toolbar_button_enabled = new_tb

      actions.set_toolbar_button_enabled(new_tb)

    end

    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x8892B0FF)

    ImGui.Text(ctx, "  Для применения изменений перезагрузите рипер")

    ImGui.PopStyleColor(ctx, 1)



    ImGui.Spacing(ctx)

    ImGui.Separator(ctx)

    ImGui.Spacing(ctx)



    render_section_header(ctx, ImGui, "ГОРЯЧИЕ КЛАВИШИ", act_acc)



    ImGui.AlignTextToFramePadding(ctx)

    ImGui.Text(ctx, "Создать субтитр по Time Selection:")

    ImGui.SameLine(ctx, 0, 10.0)



    local hotkey_options = { "Shift+T", "T" }

    local cur_hk = state.hotkey_create_sub or "Shift+T"

    if cur_hk ~= "Shift+T" and cur_hk ~= "T" then

      cur_hk = "Shift+T"

      state.hotkey_create_sub = cur_hk

    end

    local cur_hk_idx = 1

    for idx, opt in ipairs(hotkey_options) do

      if opt == cur_hk then

        cur_hk_idx = idx

        break

      end

    end



    ImGui.SetNextItemWidth(ctx, 140)

    local p_cols, p_vars = push_modern_combo_styles(ctx, ImGui, state)

    if ImGui.BeginCombo(ctx, "##hotkey_create_sub_combo", cur_hk) then

      for idx, opt in ipairs(hotkey_options) do

        local is_sel = (idx == cur_hk_idx)

        if ImGui.Selectable(ctx, opt, is_sel) then

          state.hotkey_create_sub = opt

          state.save_settings()

        end

      end

      ImGui.EndCombo(ctx)

    end

    pop_modern_combo_styles(ctx, ImGui, p_cols, p_vars)



    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Комбинация клавиш для создания субтитра по выделенному Time Selection в проекте.\nЕсли Time Selection не выделен, действие не выполняется.")

    end

  end

  end_control_box(ctx, ImGui, open_g2)



  -- 3. OPTIMIZATION SECTION (Динамическая подгрузка регионов)

  local open_g_opt = begin_control_box(ctx, state, ImGui, "gen_card_optimization")

  if open_g_opt then

    render_section_header(ctx, ImGui, "ОПТИМИЗАЦИЯ", act_acc)



    -- Toggle: Динамическая подгрузка

    if state.timeline_streaming_enabled == nil then

      state.timeline_streaming_enabled = false

    end

    local rv_dyn, new_dyn = render_toggle_switch(ctx, state, ImGui, "sw_dyn_streaming", "Динамическая подгрузка регионов", state.timeline_streaming_enabled, act_acc)

    if rv_dyn then

      state.timeline_streaming_enabled = new_dyn

      state.save_settings()

      local ok_act, actions = pcall(require, 'actions')

      if ok_act and actions then

        local filtered = state.get_filtered_subtitles()

        if actions.has_plugin_regions and actions.has_plugin_regions() then

          actions.set_regions(filtered, state.actor_palette, state)

        end

      end

    end

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Создаёт регионы в REAPER только в радиусе вокруг курсора, а не для всего файла сразу.\nЗначительно ускоряет работу REAPER на очень больших файлах (>3000 строк).")

    end



    ImGui.Spacing(ctx)



    local is_stream_on = state.timeline_streaming_enabled

    local alpha_sub = is_stream_on and 1.0 or 0.45

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha, alpha_sub)



    -- Выбор радиуса времени (по умолчанию 5 минут)

    ImGui.Text(ctx, "Радиус времени вокруг курсора:")

    local cur_rad = state.timeline_streaming_radius_min or 5.0

    local rv_rad, new_rad = render_modern_slider(ctx, state, ImGui, "sl_stream_radius", cur_rad, 1.0, 30.0, "%.0f мин", act_acc, 260)

    if rv_rad and is_stream_on then

      state.timeline_streaming_radius_min = new_rad

      state.save_settings()

      local ok_act, actions = pcall(require, 'actions')

      if ok_act and actions then

        local filtered = state.get_filtered_subtitles()

        if actions.has_plugin_regions and actions.has_plugin_regions() then

          actions.set_regions(filtered, state.actor_palette, state)

        end

      end

    end

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "В REAPER будут отображаться регионы в пределах ±N минут от текущей позиции курсора.\nПо умолчанию: 5 минут.")

    end



    ImGui.Spacing(ctx)



    -- Выбор количества строк для срабатывания (по умолчанию 3000)

    ImGui.Text(ctx, "Порог включения (количество строк субтитров):")

    local cur_threshold = state.timeline_streaming_min_subs or 3000

    local rv_th, new_th = render_modern_slider(ctx, state, ImGui, "sl_stream_threshold", cur_threshold, 500, 10000, "%.0f строк", act_acc, 260)

    if rv_th and is_stream_on then

      state.timeline_streaming_min_subs = math.floor(new_th + 0.5)

      state.save_settings()

      local ok_act, actions = pcall(require, 'actions')

      if ok_act and actions then

        local filtered = state.get_filtered_subtitles()

        if actions.has_plugin_regions and actions.has_plugin_regions() then

          actions.set_regions(filtered, state.actor_palette, state)

        end

      end

    end

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Динамическая подгрузка активируется, если в текущем файле больше указанного числа строк.\nПо умолчанию: 3000 строк.")

    end



    ImGui.PopStyleVar(ctx, 1)



    ImGui.Spacing(ctx)

    local sub_count = #state.subtitles

    local is_active_now = state.timeline_streaming_enabled and (sub_count >= (state.timeline_streaming_min_subs or 3000))

    ImGui.PushStyleColor(ctx, ImGui.Col_Text, is_active_now and 0x58D68DFF or 0x8892B0FF)

    ImGui.Text(ctx, string.format("Статус: %s (строк в проекте: %d, порог: %d)",

      is_active_now and "АКТИВНО (потоковый режим)" or "НЕ АКТИВНО (полный режим)",

      sub_count,

      state.timeline_streaming_min_subs or 3000

    ))

    ImGui.PopStyleColor(ctx, 1)

  end

  end_control_box(ctx, ImGui, open_g_opt)



  -- 3.5. IMPORT SETTINGS (SRT actor parsing)

  local open_g_import = begin_control_box(ctx, state, ImGui, "gen_card_import")

  if open_g_import then

    render_section_header(ctx, ImGui, "ИМПОРТ", act_acc)



    if state.parse_srt_actors == nil then

      state.parse_srt_actors = true

    end

    local rv_import, new_import = render_toggle_switch(ctx, state, ImGui, "sw_parse_srt_actors", "Включить режим парсинга SRT с актерами", state.parse_srt_actors, act_acc)

    if rv_import then

      state.parse_srt_actors = new_import

      state.save_settings()

    end

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Включает режим чтения SRT файлов с распределением:\n- Автоматически распознает имена персонажей и распределение по актерам\n- Умный парсер включен по умолчанию: отсекает случайные двоеточия, ремарки в скобках и защищает от пустых строк\n- При отключении: все строки считываются единым текстом как NoActor без разделения\nПо умолчанию: включено.")

    end

    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x8892B0FF)

    ImGui.Text(ctx, "  Включает режим чтения srt файлов с распределением, автоматически распознает ошибки разметки и исключает ложные имена персонажей. При выключении считывает все строки как NoActor.")

    ImGui.PopStyleColor(ctx, 1)



    ImGui.Spacing(ctx)



  end

  end_control_box(ctx, ImGui, open_g_import)



  -- 4. UI SCALE SECTION

  local open_g3 = begin_control_box(ctx, state, ImGui, "gen_card_scale")

  if open_g3 then

    render_section_header(ctx, ImGui, "МАСШТАБ ЭЛЕМЕНТОВ ИНТЕРФЕЙСА", act_acc)



    ImGui.Text(ctx, "Масштаб шрифта интерфейса (px):")

    local rv_ui, new_ui = render_modern_slider(ctx, state, ImGui, "ui_sz", state.ui_font_size or 11.0, 11.0, 26.0, "%.0f px", act_acc, 260)

    if rv_ui then

      state.ui_font_size = new_ui

      state.save_settings()

    end

    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Масштабирует шрифты в блоках настроек и таблицу в базе актеров")

    end



    ImGui.Text(ctx, "Масштаб всплывающих окон и меню (px):")

    local rv_pop, new_pop = render_modern_slider(ctx, state, ImGui, "pop_sz", state.popup_font_size or 16.0, 11.0, 28.0, "%.0f px", act_acc, 260)

    if rv_pop then

      state.popup_font_size = new_pop

      state.save_settings()

    end



    ImGui.Text(ctx, "Масштаб подсказок (px):")

    local rv_tip, new_tip = render_modern_slider(ctx, state, ImGui, "tip_sz", state.tooltip_font_size or 14.0, 10.0, 26.0, "%.0f px", act_acc, 260)

    if rv_tip then

      state.tooltip_font_size = new_tip

      state.save_settings()

    end

  end

  end_control_box(ctx, ImGui, open_g3)



  -- Reset UI scale defaults button (Centered modern pill button matching Mockup 3)

  local open_g4 = begin_control_box(ctx, state, ImGui, "gen_card_reset")

  if open_g4 then

    local btn_w = 320.0

    if render_reset_pill_button(ctx, ImGui, "reset_general_settings", "Сбросить масштабы и акцент по умолчанию", btn_w, nil, true) then

      state.ui_font_size = 11.0

      state.popup_font_size = 16.0

      state.tooltip_font_size = 14.0

      state.accent_color = { 35 / 255, 35 / 255, 35 / 255 }

      state.control_box_palette = 1

      state.watermark_style = 1

      state.save_settings()

    end



    if ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, "Возвращает: шрифт интерфейса = 11 px, меню = 16 px, подсказки = 14 px, акцентный цвет = Черный (35,35,35), палитра = Графит")

    end

  end

  end_control_box(ctx, ImGui, open_g4)



  -- Version & Author info note with clickable git link

  ImGui.Spacing(ctx)

  local base_acc, hov_acc, act_acc = get_accent_colors(state, ImGui)

  local avail_w, _ = ImGui.GetContentRegionAvail(ctx)



  -- Line 1: NutNotes version, Line 2: Author, Line 3: Donate button (scale with ui_font_size)

  local font_ui = get_or_attach_font(ctx, ImGui, state.text_font_family or "Segoe UI", state.ui_font_size or 11.0)

  local font_pushed = false

  if font_ui and ImGui.PushFont then

    ImGui.PushFont(ctx, font_ui)

    font_pushed = true

  end



  local ver_text = "NutNotes v" .. (state.version or "0.3.0-beta")

  local w_ver, _ = ImGui.CalcTextSize(ctx, ver_text)

  if w_ver < avail_w then

    ImGui.SetCursorPosX(ctx, (avail_w - w_ver) * 0.5)

  end

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x8892B0FF)

  ImGui.Text(ctx, ver_text)

  ImGui.PopStyleColor(ctx, 1)



  -- Line 2: Автор: BelkaVBanke · GitHub

  local author_prefix = "Автор: BelkaVBanke · "

  local link_text = "GitHub"

  local w_auth, _ = ImGui.CalcTextSize(ctx, author_prefix)

  local w_link, _ = ImGui.CalcTextSize(ctx, link_text)

  local total_row2_w = w_auth + w_link



  if total_row2_w < avail_w then

    ImGui.SetCursorPosX(ctx, (avail_w - total_row2_w) * 0.5)

  end



  ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x6E7B8BFF)

  ImGui.Text(ctx, author_prefix)

  ImGui.PopStyleColor(ctx, 1)



  ImGui.SameLine(ctx, 0, 0)

  local git_url = "https://github.com/BelkaVBanke/NutNotes" -- Ссылка на git репозиторий



  -- Fixed accessible, non-blending link color (GitHub Blue #58A6FF)

  local link_color = 0x58A6FFFF

  local is_link_hovered = false

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, link_color)

  ImGui.Text(ctx, link_text)

  if ImGui.IsItemHovered(ctx) then

    is_link_hovered = true

    set_tooltip(ctx, state, ImGui, git_url .. "\n(Нажмите, чтобы открыть в браузере)")

    if ImGui.IsMouseClicked(ctx, 0) then

      open_url_async(git_url)

    end

  end

  ImGui.PopStyleColor(ctx, 1)



  -- Underline on hover

  if is_link_hovered then

    local p_min_x, p_min_y = ImGui.GetItemRectMin(ctx)

    local p_max_x, p_max_y = ImGui.GetItemRectMax(ctx)

    local draw_list = ImGui.GetWindowDrawList(ctx)

    if draw_list and ImGui.DrawList_AddLine then

      ImGui.DrawList_AddLine(draw_list, p_min_x, p_max_y, p_max_x, p_max_y, 0x79C0FFFF, 1.0)

    end

  end



  -- Line 3: Кнопка "Поддержать" (DonationAlerts)

  ImGui.Spacing(ctx)

  local donate_url = "https://dalink.to/belkavbanke"

  if render_reset_pill_button(ctx, ImGui, "btn_donate_support", "Поддержать", 160.0, nil, true) then

    open_url_async(donate_url)

  end

  if ImGui.IsItemHovered(ctx) then

    set_tooltip(ctx, state, ImGui, donate_url .. "\n(Поддержать автора на DonationAlerts)")

  end



  if font_pushed and ImGui.PopFont then

    ImGui.PopFont(ctx)

  end



  ImGui.Spacing(ctx)

  ui.handle_file_drop(ctx, state, ImGui)

end



-- Render Modal Dialog: Replace Subtitles Confirmation

function ui.render_replace_modal(ctx, state, ImGui)

  if state.show_replace_modal then

    ImGui.OpenPopup(ctx, "Подтверждение замены###REPLACE_MODAL")

    state.show_replace_modal = false

  end



  local pop_c, pop_v = push_modern_popup_styles(ctx, ImGui, state)

  if ImGui.BeginPopupModal(ctx, "Подтверждение замены###REPLACE_MODAL", nil, ImGui.WindowFlags_AlwaysAutoResize) then

    local popup_font = get_or_attach_font(ctx, ImGui, state.text_font_family, state.popup_font_size or 16.0)

    local popup_font_pushed = false

    if popup_font and ImGui.PushFont then

      ImGui.PushFont(ctx, popup_font)

      popup_font_pushed = true

    end



    local base_acc, hov_acc, act_acc = get_accent_colors(state, ImGui)



    render_section_header(ctx, ImGui, "ЗАМЕНА СУБТИТРОВ", act_acc)



    ImGui.Text(ctx, "В текущем проекте уже загружены субтитры.")

    ImGui.Text(ctx, string.format("Текущих строк: %d. Загрузить новый файл?", #state.subtitles))

    if state.pending_filepath then

      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x8892B0FF)

      ImGui.Text(ctx, "Файл: " .. state.pending_filepath)

      ImGui.PopStyleColor(ctx, 1)

    end

    ImGui.Spacing(ctx)

    ImGui.Separator(ctx)

    ImGui.Spacing(ctx)



    local btn_w = 140.0

    local btn_h = 28.0

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, btn_h * 0.5)



    -- Primary Action Button (Accent themed)

    ImGui.PushStyleColor(ctx, ImGui.Col_Button, base_acc)

    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, hov_acc)

    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, act_acc)

    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFFFFFFFF)

    if ImGui.Button(ctx, "Да, заменить", btn_w, btn_h) then

      if state.pending_filepath then

        state.load_file(state.pending_filepath)

        state.pending_filepath = nil

        actions.sync_filter_to_timeline(state)

        actions.init_timeline_sync(state)

      end

      ImGui.CloseCurrentPopup(ctx)

      actions.return_focus_to_reaper()

    end

    ImGui.PopStyleColor(ctx, 4)



    ImGui.SameLine(ctx, 0, 10.0)



    -- Secondary Cancel Button (Neutral dark pill)

    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x242A35CC)

    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x333C4CAA)

    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x424D60EE)

    ImGui.PushStyleColor(ctx, ImGui.Col_Border, 0x3A445688)

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, 1.0)

    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xB0B7C3FF)

    if ImGui.Button(ctx, "Отмена", 100.0, btn_h) or (ImGui.Key_Escape and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape)) then

      state.pending_filepath = nil

      ImGui.CloseCurrentPopup(ctx)

      actions.return_focus_to_reaper()

    end

    ImGui.PopStyleColor(ctx, 5)

    ImGui.PopStyleVar(ctx, 2) -- pop FrameRounding and FrameBorderSize



    if popup_font_pushed then

      ImGui.PopFont(ctx)

    end

    ImGui.EndPopup(ctx)

  else

    if state.pending_filepath and not state.show_replace_modal then

      state.pending_filepath = nil

    end

  end

  pop_modern_popup_styles(ctx, ImGui, pop_c, pop_v)

end



-- Render Modal Dialog: Missing js_ReaScriptAPI Extension Notification

function ui.render_missing_js_modal(ctx, state, ImGui)

  if state.show_missing_js_modal then

    ImGui.OpenPopup(ctx, "Требуется расширение###MISSING_JS_MODAL")

    state.show_missing_js_modal = false

  end



  local pop_c, pop_v = push_modern_popup_styles(ctx, ImGui, state)

  if ImGui.BeginPopupModal(ctx, "Требуется расширение###MISSING_JS_MODAL", nil, ImGui.WindowFlags_AlwaysAutoResize) then

    local popup_font = get_or_attach_font(ctx, ImGui, state.text_font_family, state.popup_font_size or 16.0)

    local popup_font_pushed = false

    if popup_font and ImGui.PushFont then

      ImGui.PushFont(ctx, popup_font)

      popup_font_pushed = true

    end



    local base_acc, hov_acc, act_acc = get_accent_colors(state, ImGui)



    render_section_header(ctx, ImGui, "ЭКСПОРТ ФАЙЛОВ", act_acc)



    ImGui.Text(ctx, "Для экспорта файлов необходимо расширение:")

    ImGui.Spacing(ctx)



    ImGui.PushStyleColor(ctx, ImGui.Col_Text, act_acc)

    ImGui.Text(ctx, "js_ReaScriptAPI: API functions for ReaScripts")

    ImGui.PopStyleColor(ctx, 1)



    ImGui.Spacing(ctx)

    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x94A3B8FF)

    ImGui.Text(ctx, "Установите его в REAPER через меню:\nExtensions -> ReaPack -> Browse packages...")

    ImGui.PopStyleColor(ctx, 1)



    ImGui.Spacing(ctx)

    ImGui.Separator(ctx)

    ImGui.Spacing(ctx)



    local btn_w = 120.0

    local btn_h = 28.0

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, btn_h * 0.5)



    -- Primary Button: "Понятно"

    ImGui.PushStyleColor(ctx, ImGui.Col_Button, base_acc)

    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, hov_acc)

    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, act_acc)

    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFFFFFFFF)

    if ImGui.Button(ctx, "Понятно", btn_w, btn_h) or (ImGui.Key_Escape and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape)) or (ImGui.Key_Enter and ImGui.IsKeyPressed(ctx, ImGui.Key_Enter)) then

      ImGui.CloseCurrentPopup(ctx)

      actions.return_focus_to_reaper()

    end

    ImGui.PopStyleColor(ctx, 4)

    ImGui.PopStyleVar(ctx, 1)



    if popup_font_pushed then

      ImGui.PopFont(ctx)

    end

    ImGui.EndPopup(ctx)

  end

  pop_modern_popup_styles(ctx, ImGui, pop_c, pop_v)

end



-- Helper to render custom modern modal header matching mockup (without close cross)

local function render_modal_header(ctx, ImGui, title, act_acc, win_w)

  local p_min_x, p_min_y = ImGui.GetCursorScreenPos(ctx)

  local draw_list = ImGui.GetWindowDrawList(ctx)

  local txt_w, txt_h = ImGui.CalcTextSize(ctx, title)

  local bar_w = 4.0

  local bar_h = math.max(20.0, txt_h + 2.0)

  local header_h = bar_h + 10.0



  -- Header background panel bar

  local head_bg = 0x20232AFF

  ImGui.DrawList_AddRectFilled(draw_list, p_min_x - 6.0, p_min_y - 6.0, p_min_x + win_w + 6.0, p_min_y + header_h, head_bg, 6.0, ImGui.DrawFlags_RoundCornersTop or 3)

  -- Accent vertical pill indicator

  ImGui.DrawList_AddRectFilled(draw_list, p_min_x, p_min_y + 2.0, p_min_x + bar_w, p_min_y + 2.0 + bar_h, act_acc, 2.0)



  -- Title text

  local start_cur_y = ImGui.GetCursorPosY(ctx)

  ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + bar_w + 10.0)

  ImGui.SetCursorPosY(ctx, start_cur_y + 2.0)

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xE3E7EDFF)

  ImGui.Text(ctx, title)

  ImGui.PopStyleColor(ctx, 1)



  -- Bottom divider under header

  ImGui.DrawList_AddLine(draw_list, p_min_x - 6.0, p_min_y + header_h, p_min_x + win_w + 6.0, p_min_y + header_h, 0x343A44FF, 1.0)



  -- Set next item cursor relative to start_cur_y

  ImGui.SetCursorPosY(ctx, start_cur_y + header_h + 8.0)

end



-- Helper to render modern modal footer matching mockup

local function render_modal_footer(ctx, state, ImGui, act_acc, base_acc, hov_acc, win_w, save_btn_text, can_save, is_default_enter, save_tooltip)

  local p_min_x, _ = ImGui.GetCursorScreenPos(ctx)

  local draw_list = ImGui.GetWindowDrawList(ctx)



  ImGui.Spacing(ctx)

  local _, sep_y = ImGui.GetCursorScreenPos(ctx)

  -- Accent horizontal top border for footer

  ImGui.DrawList_AddLine(draw_list, p_min_x - 6.0, sep_y, p_min_x + win_w + 6.0, sep_y, act_acc, 1.0)

  ImGui.Spacing(ctx)

  ImGui.SetCursorPosY(ctx, ImGui.GetCursorPosY(ctx) + 6.0)



  local btn_w_save = 110.0

  local btn_w_cancel = 90.0

  local btn_h = 28.0

  local gap = 8.0

  local actions_w = btn_w_cancel + gap + btn_w_save



  ImGui.SetCursorPosX(ctx, win_w - actions_w)



  -- Secondary Cancel button (#252a33)

  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 5.0)

  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, 1.0)

  ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x252A33FF)

  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x303743FF)

  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x3C4554FF)

  ImGui.PushStyleColor(ctx, ImGui.Col_Border, 0x4B5665FF)

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xE3E7EDFF)

  local cancel_pressed = ImGui.Button(ctx, "Отмена", btn_w_cancel, btn_h)

  ImGui.PopStyleColor(ctx, 5)



  ImGui.SameLine(ctx, 0, gap)



  if not can_save then

    ImGui.BeginDisabled(ctx, true)

  end



  -- Primary Accent Save button

  ImGui.PushStyleColor(ctx, ImGui.Col_Button, act_acc)

  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, base_acc)

  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, hov_acc)

  ImGui.PushStyleColor(ctx, ImGui.Col_Border, act_acc)

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFFFFFFFF)

  local save_pressed = ImGui.Button(ctx, save_btn_text or "Сохранить", btn_w_save, btn_h)

  ImGui.PopStyleColor(ctx, 5)



  if save_tooltip and ImGui.IsItemHovered(ctx) then

    set_tooltip(ctx, state, ImGui, save_tooltip)

  end



  if not can_save then

    ImGui.EndDisabled(ctx)

  end

  ImGui.PopStyleVar(ctx, 2)



  if is_default_enter and can_save then

    local enter_pressed = ImGui.Key_Enter and ImGui.IsKeyPressed(ctx, ImGui.Key_Enter)

    if enter_pressed then

      save_pressed = true

    end

  end



  if ImGui.Key_Escape and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then

    cancel_pressed = true

  end



  return save_pressed, cancel_pressed

end



-- Render Dedicated Subtitle Actor Edit Modal (Right-Click Menu -> Изменить актера -> Задать новое имя)

function ui.render_sub_actor_modal(ctx, state, ImGui)

  if state.focus_mode then

    state.open_sub_actor_modal = false

    return

  end

  if state.open_sub_actor_modal then

    ImGui.OpenPopup(ctx, "Изменить актера субтитра###SUB_ACTOR_EDIT_MODAL")

    state.open_sub_actor_modal = false

    state.sub_actor_modal_focused = false

  end



  local pop_c, pop_v = push_modern_popup_styles(ctx, ImGui, state)

  local modal_flags = ImGui.WindowFlags_AlwaysAutoResize

  if ImGui.WindowFlags_NoTitleBar then

    modal_flags = modal_flags | ImGui.WindowFlags_NoTitleBar

  end

  if ImGui.BeginPopupModal(ctx, "Изменить актера субтитра###SUB_ACTOR_EDIT_MODAL", nil, modal_flags) then

    local popup_font = get_or_attach_font(ctx, ImGui, state.text_font_family, state.popup_font_size or 16.0)

    local popup_font_pushed = false

    if popup_font and ImGui.PushFont then

      ImGui.PushFont(ctx, popup_font)

      popup_font_pushed = true

    end



    local base_acc, hov_acc, act_acc = get_accent_colors(state, ImGui)

    local modal_w = 460.0



    -- Header matching rename modal

    render_modal_header(ctx, ImGui, "Изменение актера реплики", act_acc, modal_w)



    local idx = state.sub_actor_modal_idx

    local sub = idx and state.subtitles[idx]

    if sub then

      local time_str = string.format("[%s - %s]", parser.format_time(sub.start_time), parser.format_time(sub.end_time))

      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xE3E7EDFF)

      ImGui.Text(ctx, string.format("Реплика #%d", idx))

      ImGui.PopStyleColor(ctx, 1)



      ImGui.SameLine(ctx, 0, 20.0)

      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x8892B0FF)

      ImGui.Text(ctx, string.format("Тайминг: %s", time_str))

      ImGui.PopStyleColor(ctx, 1)



      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x8892B0FF)

      ImGui.Text(ctx, "Текст: " .. parser.truncate_utf8(sub.text, 50))

      ImGui.PopStyleColor(ctx, 1)



      ImGui.Spacing(ctx)

      -- Uppercase section label

      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xA0A7B2FF)

      ImGui.Text(ctx, "ИМЯ АКТЁРА")

      ImGui.PopStyleColor(ctx, 1)



      if not state.sub_actor_modal_focused then

        ImGui.SetKeyboardFocusHere(ctx)

        state.sub_actor_modal_focused = true

      end



      ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0x191C22FF)

      ImGui.PushStyleColor(ctx, ImGui.Col_Border, 0x4B5665FF)

      ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 5.0)

      ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, 1.0)

      ImGui.SetNextItemWidth(ctx, modal_w)

      local rv_name, new_name = ImGui.InputText(ctx, "##sub_new_actor_input", state.sub_actor_modal_name or "", 280)

      if rv_name then

        state.sub_actor_modal_name = new_name

      end

      ImGui.PopStyleVar(ctx, 2)

      ImGui.PopStyleColor(ctx, 2)



      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x7E8B9BFF)

      ImGui.Text(ctx, "Формат: 'Имя' или 'Имя (Персонаж)'. Пустое поле = NoActor.")

      ImGui.PopStyleColor(ctx, 1)



      -- Footer matching mockup

      local save_pressed, cancel_pressed = render_modal_footer(ctx, state, ImGui, act_acc, base_acc, hov_acc, modal_w, "Сохранить", true, true, "Сохранить (Enter)")



      if save_pressed then

        local target_name = state.sub_actor_modal_name or ""

        target_name = target_name:gsub("^%s+", ""):gsub("%s+$", "")

        if target_name == "" then target_name = "NoActor" end

        state.change_subtitle_actor_with_undo(idx, target_name)

        actions.update_subtitle_timeline(state, idx)

        actions.sync_filter_to_timeline(state)

        state.sub_actor_modal_idx = nil

        state.sub_actor_modal_name = nil

        state.sub_actor_modal_focused = false

        ImGui.CloseCurrentPopup(ctx)

        actions.return_focus_to_reaper()

      end



      if cancel_pressed then

        state.sub_actor_modal_idx = nil

        state.sub_actor_modal_name = nil

        state.sub_actor_modal_focused = false

        ImGui.CloseCurrentPopup(ctx)

        actions.return_focus_to_reaper()

      end

    else

      ImGui.Text(ctx, "Субтитр не найден.")

      local btn_h = 28.0

      ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, btn_h * 0.5)

      if ImGui.Button(ctx, "Закрыть", 100.0, btn_h) then

        state.sub_actor_modal_idx = nil

        state.sub_actor_modal_name = nil

        state.sub_actor_modal_focused = false

        ImGui.CloseCurrentPopup(ctx)

        actions.return_focus_to_reaper()

      end

      ImGui.PopStyleVar(ctx, 1)

    end



    if popup_font_pushed then

      ImGui.PopFont(ctx)

    end

    ImGui.EndPopup(ctx)

  else

    if state.sub_actor_modal_idx ~= nil then

      state.sub_actor_modal_idx = nil

      state.sub_actor_modal_name = nil

      state.sub_actor_modal_focused = false

      actions.return_focus_to_reaper()

    end

  end

  pop_modern_popup_styles(ctx, ImGui, pop_c, pop_v)

end



-- Render Global Rename Actor Modal (Tab 2 -> Right-Click -> Переименовать актера)

function ui.render_rename_actor_modal(ctx, state, ImGui)

  if state.open_rename_actor_modal then

    ImGui.OpenPopup(ctx, "Переименовать актера###RENAME_ACTOR_MODAL")

    state.open_rename_actor_modal = false

    state.rename_actor_focused = false

  end



  local pop_c, pop_v = push_modern_popup_styles(ctx, ImGui, state)

  local modal_flags = ImGui.WindowFlags_AlwaysAutoResize

  if ImGui.WindowFlags_NoTitleBar then

    modal_flags = modal_flags | ImGui.WindowFlags_NoTitleBar

  end

  if ImGui.BeginPopupModal(ctx, "Переименовать актера###RENAME_ACTOR_MODAL", nil, modal_flags) then

    local popup_font = get_or_attach_font(ctx, ImGui, state.text_font_family, state.popup_font_size or 16.0)

    local popup_font_pushed = false

    if popup_font and ImGui.PushFont then

      ImGui.PushFont(ctx, popup_font)

      popup_font_pushed = true

    end



    local base_acc, hov_acc, act_acc = get_accent_colors(state, ImGui)

    local modal_w = 460.0



    -- Header matching HTML mockup (no cross icon)

    render_modal_header(ctx, ImGui, "Изменение имени актёра", act_acc, modal_w)



    local orig = state.rename_actor_orig

    local count = orig and state.actor_counts[orig] or 0



    -- Compact single row for Actor and Lines count: Актер: [имя]   Реплик: [количество]

    local full_orig = orig or ""

    local scale_factor = (state.popup_font_size or 16.0) / 16.0

    local max_orig_len = math.max(12, math.floor(25 / scale_factor))

    local disp_orig = parser.truncate_utf8(full_orig, max_orig_len)



    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xE3E7EDFF)

    ImGui.Text(ctx, string.format("Актер: %s", disp_orig))

    ImGui.PopStyleColor(ctx, 1)

    if disp_orig ~= full_orig and ImGui.IsItemHovered(ctx) then

      set_tooltip(ctx, state, ImGui, string.format("Полное имя: %s", full_orig))

    end



    ImGui.SameLine(ctx, 0, 24.0)

    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x8892B0FF)

    ImGui.Text(ctx, string.format("Реплик: %d", count))

    ImGui.PopStyleColor(ctx, 1)



    ImGui.Spacing(ctx)

    -- Uppercase section label matching mockup

    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xA0A7B2FF)

    ImGui.Text(ctx, "ИМЯ АКТЁРА")

    ImGui.PopStyleColor(ctx, 1)



    if not state.rename_actor_focused then

      ImGui.SetKeyboardFocusHere(ctx)

      state.rename_actor_focused = true

    end



    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0x191C22FF)

    ImGui.PushStyleColor(ctx, ImGui.Col_Border, 0x4B5665FF)

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 5.0)

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, 1.0)

    ImGui.SetNextItemWidth(ctx, modal_w)

    local rv_inp, new_inp = ImGui.InputText(ctx, "##rename_actor_input", state.rename_actor_input or "", 280)

    if rv_inp then

      state.rename_actor_input = new_inp

    end

    ImGui.PopStyleVar(ctx, 2)

    ImGui.PopStyleColor(ctx, 2)



    local new_clean = (state.rename_actor_input or ""):gsub("^%s+", ""):gsub("%s+$", "")

    local is_already_exists = false

    if state.actors then

      for _, a in ipairs(state.actors) do

        if a == new_clean and a ~= orig then

          is_already_exists = true

          break

        end

      end

    end



    local can_save = (new_clean ~= "" and new_clean ~= orig and not is_already_exists)



    if is_already_exists then

      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF6B6BFF)

      ImGui.Text(ctx, string.format("❌ Имя «%s» уже занято другим актером в проекте.\nДля слияния используйте ПКМ «Объединить с другим актером».", new_clean))

      ImGui.PopStyleColor(ctx, 1)

    else

      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x7E8B9BFF)

      ImGui.Text(ctx, "Имя будет обновлено для связанных реплик.")

      ImGui.PopStyleColor(ctx, 1)

    end



    -- Footer matching HTML mockup

    local save_pressed, cancel_pressed = render_modal_footer(ctx, state, ImGui, act_acc, base_acc, hov_acc, modal_w, "Сохранить", can_save, true, "Сохранить (Enter)")



    if save_pressed and can_save then

      state.rename_actor_globally_with_undo(orig, new_clean)

      actions.update_all_timeline_actors(state)

      actions.sync_filter_to_timeline(state)

      actions.init_timeline_sync(state)



      state.rename_actor_orig = nil

      state.rename_actor_input = nil

      state.rename_actor_focused = false

      ImGui.CloseCurrentPopup(ctx)

      actions.return_focus_to_reaper()

    end



    if cancel_pressed then

      state.rename_actor_orig = nil

      state.rename_actor_input = nil

      state.rename_actor_focused = false

      ImGui.CloseCurrentPopup(ctx)

      actions.return_focus_to_reaper()

    end



    if popup_font_pushed then

      ImGui.PopFont(ctx)

    end

    ImGui.EndPopup(ctx)

  else

    if state.rename_actor_orig ~= nil then

      state.rename_actor_orig = nil

      state.rename_actor_input = nil

      state.rename_actor_focused = false

      actions.return_focus_to_reaper()

    end

  end

  pop_modern_popup_styles(ctx, ImGui, pop_c, pop_v)

end



-- Render Dedicated Subtitle Text Edit Modal (Right-Click Menu -> Изменить текст)

function ui.render_text_edit_modal(ctx, state, ImGui)

  if state.focus_mode then

    state.open_text_edit_popup = false

    return

  end

  if state.open_text_edit_popup then

    if ImGui.SetNextWindowFocus then

      ImGui.SetNextWindowFocus(ctx)

    end

    ImGui.OpenPopup(ctx, "Изменить текст субтитра###SUB_TEXT_EDIT_MODAL")

    state.open_text_edit_popup = false

    state.text_edit_focused = false

    if actions.focus_nutnotes_window then

      actions.focus_nutnotes_window()

    end

  end



  local pop_c, pop_v = push_modern_popup_styles(ctx, ImGui, state)

  local modal_flags = ImGui.WindowFlags_AlwaysAutoResize

  if ImGui.WindowFlags_NoTitleBar then

    modal_flags = modal_flags | ImGui.WindowFlags_NoTitleBar

  end

  if ImGui.SetNextWindowFocus then

    ImGui.SetNextWindowFocus(ctx)

  end

  if ImGui.BeginPopupModal(ctx, "Изменить текст субтитра###SUB_TEXT_EDIT_MODAL", nil, modal_flags) then

    if ImGui.SetNextFrameWantCaptureKeyboard then

      ImGui.SetNextFrameWantCaptureKeyboard(ctx, true)

    end

    local popup_font = get_or_attach_font(ctx, ImGui, state.text_font_family, state.popup_font_size or 16.0)

    local popup_font_pushed = false

    if popup_font and ImGui.PushFont then

      ImGui.PushFont(ctx, popup_font)

      popup_font_pushed = true

    end



    local base_acc, hov_acc, act_acc = get_accent_colors(state, ImGui)

    local modal_w = 480.0



    -- Header matching HTML mockup (no cross icon)

    render_modal_header(ctx, ImGui, "Изменение текста субтитра", act_acc, modal_w)



    local idx = state.text_edit_idx

    local sub = idx and state.subtitles[idx]

    if sub then

      local time_str = string.format("[%s - %s]", parser.format_time(sub.start_time), parser.format_time(sub.end_time))



      -- Full actor string formatting & tooltip if truncated

      local full_act_str = ""

      if sub.actors and #sub.actors > 1 then

        full_act_str = table.concat(sub.actors, ", ")

        if sub.character and sub.character ~= "" then

          full_act_str = full_act_str .. " (" .. sub.character .. ")"

        end

      else

        full_act_str = sub.raw_actor or sub.actor or "NoActor"

      end



      -- First item: Line number

      local line_label = string.format("Строка #%d", idx)

      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xE3E7EDFF)

      ImGui.Text(ctx, line_label)

      ImGui.PopStyleColor(ctx, 1)



      -- Second item: Timing

      ImGui.SameLine(ctx, 0, 14.0)

      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x8892B0FF)

      ImGui.Text(ctx, time_str)

      ImGui.PopStyleColor(ctx, 1)



      -- Calculate remaining width for Actor in modal_w to prevent stretching dialog

      local w_line, _ = ImGui.CalcTextSize(ctx, line_label)

      local w_time, _ = ImGui.CalcTextSize(ctx, time_str)

      local prefix_act = "Актер: "

      local w_prefix, _ = ImGui.CalcTextSize(ctx, prefix_act)

      local remaining_w = modal_w - (w_line + 14.0 + w_time + 14.0 + w_prefix)



      -- Start with maximum 25 characters

      local scale_factor = (state.popup_font_size or 16.0) / 16.0

      local max_act_len = math.max(10, math.floor(25 / scale_factor))

      local disp_act_str = parser.truncate_utf8(full_act_str, max_act_len)



      -- Binary search truncation if it still exceeds remaining_w

      local cur_w, _ = ImGui.CalcTextSize(ctx, disp_act_str)

      if cur_w > remaining_w then

        local u_chars = {}

        for uchar in full_act_str:gmatch("[%z\1-\127\194-\244][\128-\191]*") do

          table.insert(u_chars, uchar)

        end

        local low = 1

        local high = math.min(#u_chars, max_act_len)

        local best_str = (u_chars[1] or "") .. "..."

        while low <= high do

          local mid = math.floor((low + high) * 0.5)

          local candidate = table.concat(u_chars, "", 1, mid) .. "..."

          local c_w, _ = ImGui.CalcTextSize(ctx, candidate)

          if c_w <= remaining_w then

            best_str = candidate

            low = mid + 1

          else

            high = mid - 1

          end

        end

        disp_act_str = best_str

      end



      ImGui.SameLine(ctx, 0, 14.0)

      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x88CCFFFF)

      ImGui.Text(ctx, prefix_act .. disp_act_str)

      ImGui.PopStyleColor(ctx, 1)

      if disp_act_str ~= full_act_str and ImGui.IsItemHovered(ctx) then

        set_tooltip(ctx, state, ImGui, string.format("Все актеры:\n%s", full_act_str))

      end



      ImGui.Spacing(ctx)

      -- Uppercase label matching HTML mockup

      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xA0A7B2FF)

      ImGui.Text(ctx, "ТЕКСТ СУБТИТРА")

      ImGui.PopStyleColor(ctx, 1)



      if not state.text_edit_focused then

        ImGui.SetKeyboardFocusHere(ctx)

        state.text_edit_focused = true

      end



      -- Input field height reduced to 3 lines with vertical scrollbar when overflowing

      local line_h = ImGui.GetTextLineHeight(ctx)

      local input_h = math.floor(line_h * 3.0 + 14.0)



      ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0x191C22FF)

      ImGui.PushStyleColor(ctx, ImGui.Col_Border, 0x4B5665FF)

      ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 5.0)

      ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, 1.0)

      local rv_t, new_t = ImGui.InputTextMultiline(ctx, "##edit_text_input", state.text_edit_content or "", modal_w, input_h)

      if rv_t then

        state.text_edit_content = new_t

      end

      ImGui.PopStyleVar(ctx, 2)

      ImGui.PopStyleColor(ctx, 2)



      -- Character count hint matching HTML mockup (without Ctrl+Enter hint)

      local text_content = state.text_edit_content or ""

      local char_count = select(2, text_content:gsub("[^\128-\193]", ""))

      local char_suffix = "символов"

      local mod10 = char_count % 10

      local mod100 = char_count % 100

      if mod10 == 1 and mod100 ~= 11 then

        char_suffix = "символ"

      elseif mod10 >= 2 and mod10 <= 4 and (mod100 < 10 or mod100 >= 20) then

        char_suffix = "символа"

      end



      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x7E8B9BFF)

      ImGui.Text(ctx, string.format("%d %s", char_count, char_suffix))

      ImGui.PopStyleColor(ctx, 1)



      -- Footer matching HTML mockup with Ctrl+Enter tooltip on Save button

      local save_pressed, cancel_pressed = render_modal_footer(ctx, state, ImGui, act_acc, base_acc, hov_acc, modal_w, "Сохранить", true, false, "Сохранить (Ctrl+Enter)")



      -- Check Ctrl+Enter / Cmd+Enter across all versions

      local ctrl_down = false

      if reaper and reaper.JS_Mouse_GetState then

        local ok, mc = pcall(reaper.JS_Mouse_GetState, 0x1C)

        if ok and mc and (mc & 4) ~= 0 then ctrl_down = true end

      end

      if not ctrl_down and ImGui.IsKeyDown then

        local keys = { ImGui.Key_LeftCtrl, ImGui.Key_RightCtrl, ImGui.Mod_Ctrl, ImGui.Key_LeftSuper, ImGui.Key_RightSuper, ImGui.Mod_Super }

        for _, k in ipairs(keys) do

          if k then

            local ok, down = pcall(ImGui.IsKeyDown, ctx, k)

            if ok and down then

              ctrl_down = true

              break

            end

          end

        end

      end



      local enter_pressed = false

      if ImGui.Key_Enter then

        local ok, p = pcall(ImGui.IsKeyPressed, ctx, ImGui.Key_Enter)

        if ok and p then enter_pressed = true end

      end

      if not enter_pressed and ImGui.Key_KeypadEnter then

        local ok, p = pcall(ImGui.IsKeyPressed, ctx, ImGui.Key_KeypadEnter)

        if ok and p then enter_pressed = true end

      end



      if ctrl_down and enter_pressed then

        save_pressed = true

      end



      if save_pressed then

        local new_text = parser.strip_invisible_unicode(state.text_edit_content or "")

        if new_text ~= (sub.text or "") then

          local old_snap = state.capture_snapshot and state.capture_snapshot("Изменение текста строки #" .. idx)

          sub.text = new_text

          if parser and parser.prepare_sub_props then

            parser.prepare_sub_props(sub)

          elseif state.prepare_sub_props then

            state.prepare_sub_props(sub)

          end

          state.row_heights = {}

          state.save_to_project()

          if state.push_undo then

            state.push_undo("Изменение текста строки #" .. idx, old_snap, function()

              actions.update_subtitle_timeline(state, idx)

              actions.sync_filter_to_timeline(state)

            end)

          end

        end

        state.text_edit_idx = nil

        state.text_edit_content = nil

        state.text_edit_focused = false

        state._is_creating_new_sub = nil

        ImGui.CloseCurrentPopup(ctx)

        actions.return_focus_to_reaper()

      end



      if cancel_pressed then

        state.text_edit_idx = nil

        state.text_edit_content = nil

        state.text_edit_focused = false

        state._is_creating_new_sub = nil

        ImGui.CloseCurrentPopup(ctx)

        actions.return_focus_to_reaper()

      end

    else

      ImGui.Text(ctx, "Субтитр не найден.")

      local btn_h = 28.0

      ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 5.0)

      if ImGui.Button(ctx, "Закрыть", 100.0, btn_h) then

        state.text_edit_idx = nil

        state.text_edit_content = nil

        state.text_edit_focused = false

        state._is_creating_new_sub = nil

        ImGui.CloseCurrentPopup(ctx)

        actions.return_focus_to_reaper()

      end

      ImGui.PopStyleVar(ctx, 1)

    end



    if popup_font_pushed then

      ImGui.PopFont(ctx)

    end

    ImGui.EndPopup(ctx)

  else

    if state.text_edit_idx ~= nil then

      state.text_edit_idx = nil

      state.text_edit_content = nil

      state.text_edit_focused = false

      state._is_creating_new_sub = nil

      actions.return_focus_to_reaper()

    end

  end

  pop_modern_popup_styles(ctx, ImGui, pop_c, pop_v)

end



-- Main Window Draw Loop

function ui.draw(ctx, state, ImGui)

  -- Check if project changed in REAPER (tab switch)

  state.check_project_changed(actions)



  local win_flags = ImGui.WindowFlags_MenuBar or 0

  if ImGui.WindowFlags_NoNavInputs then

    win_flags = win_flags | ImGui.WindowFlags_NoNavInputs

  end

  if ImGui.WindowFlags_NoCollapse then

    win_flags = win_flags | ImGui.WindowFlags_NoCollapse

  end

  is_frame_active = true

  local visible, open = ImGui.Begin(ctx, "NutNotes###MAIN_NUTNOTES_WINDOW", true, win_flags)



  if visible then

    local foc_flags = (ImGui.FocusedFlags_RootAndChildWindows or 0)

    if ImGui.FocusedFlags_DockHierarchy then

      foc_flags = foc_flags | ImGui.FocusedFlags_DockHierarchy

    end

    local win_focused = (ImGui.IsWindowFocused and ImGui.IsWindowFocused(ctx, foc_flags))

    local win_hovered = (ImGui.IsWindowHovered and ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_RootAndChildWindows or 0))

    local has_row_sel = (state.user_selected_row_idx ~= nil)

    local is_reaper_playing = reaper and ((reaper.GetPlayState() & 1) ~= 0)

    local is_typing = actions.is_text_editing_active(ctx, state, ImGui)

    state._is_nutnotes_focused = win_focused

    state._is_nutnotes_hovered = win_hovered



    -- Instruct ReaImGui whether to capture keyboard shortcuts from REAPER's global scope:

    -- When NutNotes is focused, hovered, typing, or row is selected, capture keyboard for Delete, Space, Ctrl+Z

    if ImGui.SetNextFrameWantCaptureKeyboard then

      ImGui.SetNextFrameWantCaptureKeyboard(ctx, win_focused or win_hovered or is_typing or has_row_sel)

    end



    -- HOTKEYS (Processed natively when NutNotes window or any child window is focused or hovered or row selected)

    if win_focused or win_hovered or has_row_sel then

      -- 1. Ctrl+R: Transport Record Passthrough

      if not is_typing and ImGui.Key_R and ImGui.IsKeyPressed(ctx, ImGui.Key_R) then

        local ctrl_down = (ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl) or ImGui.IsKeyDown(ctx, ImGui.Key_LeftCtrl) or ImGui.IsKeyDown(ctx, ImGui.Key_RightCtrl))

        local shift_down = (ImGui.IsKeyDown(ctx, ImGui.Mod_Shift) or ImGui.IsKeyDown(ctx, ImGui.Key_LeftShift) or ImGui.IsKeyDown(ctx, ImGui.Key_RightShift))

        local alt_down = (ImGui.IsKeyDown(ctx, ImGui.Mod_Alt) or ImGui.IsKeyDown(ctx, ImGui.Key_LeftAlt) or ImGui.IsKeyDown(ctx, ImGui.Key_RightAlt))

        if ctrl_down and not shift_down and not alt_down then

          if reaper and reaper.Main_OnCommand then

            reaper.Main_OnCommand(1013, 0) -- Transport: Record

          end

        end

      end



      -- 2. Space Passthrough: Play/Stop REAPER playback if not typing in an input field

      if not is_typing and ImGui.IsKeyPressed(ctx, ImGui.Key_Space) then

        if reaper and reaper.Main_OnCommand then

          local ctrl_down = (ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl) or ImGui.IsKeyDown(ctx, ImGui.Key_LeftCtrl) or ImGui.IsKeyDown(ctx, ImGui.Key_RightCtrl))

          reaper.Main_OnCommand(ctrl_down and 40073 or 40044, 0) -- Transport: Play/stop (or play/pause)

        end

      end



      -- 3. Delete / Backspace: Delete selected subtitle when stopped and not typing (disabled in focus mode)

      -- Regular Delete: leaves playback timing position intact

      -- Ctrl+Delete: deletes and jumps playback timing position to next subtitle

      if not is_typing and not is_reaper_playing and not state.focus_mode then

        local ctrl_down = (ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl) or ImGui.IsKeyDown(ctx, ImGui.Key_LeftCtrl) or ImGui.IsKeyDown(ctx, ImGui.Key_RightCtrl) or (ImGui.Mod_Super and ImGui.IsKeyDown(ctx, ImGui.Mod_Super)))

        local del_pressed = ImGui.IsKeyPressed(ctx, ImGui.Key_Delete)

        if not del_pressed and ImGui.Key_Backspace and ImGui.IsKeyPressed(ctx, ImGui.Key_Backspace) then

          del_pressed = true

        end

        if del_pressed and not state.focus_mode then

          local real_idx = state.user_selected_row_idx

          if real_idx and state.subtitles and state.subtitles[real_idx] then

            state.delete_subtitle(real_idx, ctrl_down)

            state.save_to_project()

          end

        end

      end



      -- 4. Ctrl+Z / Cmd+Z: Internal Plugin Undo, Ctrl+Shift+Z / Ctrl+Y: Redo

      if not is_typing then

        local ctrl_down = ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl)

                       or ImGui.IsKeyDown(ctx, ImGui.Key_LeftCtrl)

                       or ImGui.IsKeyDown(ctx, ImGui.Key_RightCtrl)

                       or (ImGui.Mod_Super and ImGui.IsKeyDown(ctx, ImGui.Mod_Super))

                       or (ImGui.Key_LeftSuper and ImGui.IsKeyDown(ctx, ImGui.Key_LeftSuper))

                       or (ImGui.Key_RightSuper and ImGui.IsKeyDown(ctx, ImGui.Key_RightSuper))

        local shift_down = ImGui.IsKeyDown(ctx, ImGui.Mod_Shift)

                        or ImGui.IsKeyDown(ctx, ImGui.Key_LeftShift)

                        or ImGui.IsKeyDown(ctx, ImGui.Key_RightShift)

        local z_pressed = ImGui.Key_Z and ImGui.IsKeyPressed(ctx, ImGui.Key_Z)

        local y_pressed = ImGui.Key_Y and ImGui.IsKeyPressed(ctx, ImGui.Key_Y)

        if ctrl_down and not shift_down and z_pressed then

          if not state.undo(actions) then

            if reaper and reaper.Main_OnCommand then

              reaper.Main_OnCommand(40029, 0) -- Edit: Undo

            end

          end

        elseif (ctrl_down and shift_down and z_pressed) or (ctrl_down and not shift_down and y_pressed) then

          if not state.redo(actions) then

            if reaper and reaper.Main_OnCommand then

              reaper.Main_OnCommand(40030, 0) -- Edit: Redo

            end

          end

        end

      end



      -- 5. Hotkey (Shift+T or T): Create subtitle from REAPER time selection

      if not is_typing and ImGui.Key_T then

        local shift_down = ImGui.IsKeyDown(ctx, ImGui.Mod_Shift)

                        or ImGui.IsKeyDown(ctx, ImGui.Key_LeftShift)

                        or (ImGui.Key_RightShift and ImGui.IsKeyDown(ctx, ImGui.Key_RightShift))

        local ctrl_down = ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl)

                       or ImGui.IsKeyDown(ctx, ImGui.Key_LeftCtrl)

                       or (ImGui.Key_RightCtrl and ImGui.IsKeyDown(ctx, ImGui.Key_RightCtrl))

        local alt_down  = ImGui.IsKeyDown(ctx, ImGui.Mod_Alt)

                       or ImGui.IsKeyDown(ctx, ImGui.Key_LeftAlt)

                       or (ImGui.Key_RightAlt and ImGui.IsKeyDown(ctx, ImGui.Key_RightAlt))

        local t_pressed = ImGui.IsKeyPressed(ctx, ImGui.Key_T)



        local target_hk = state.hotkey_create_sub or "Shift+T"

        local match = false

        if target_hk == "Shift+T" then

          match = shift_down and not ctrl_down and t_pressed

        elseif target_hk == "T" then

          match = not shift_down and not ctrl_down and t_pressed

        end



        if match then

          actions.create_subtitle_from_time_selection(state)

        end

      end



      -- 6. Esc: Deselect row

      if not is_typing and ImGui.Key_Escape and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then

        if state.user_selected_row_idx ~= nil then

          state.user_selected_row_idx = nil

          if actions.return_focus_to_reaper then

            actions.return_focus_to_reaper()

          end

        end

      end





    end



    local frame_bg_pushed = 0

    frame_bg_pushed = frame_bg_pushed + safe_push_style_color(ctx, ImGui, ImGui.Col_FrameBg, 0x2A313EFF)

    frame_bg_pushed = frame_bg_pushed + safe_push_style_color(ctx, ImGui, ImGui.Col_FrameBgHovered, 0x3E4554FF)

    frame_bg_pushed = frame_bg_pushed + safe_push_style_color(ctx, ImGui, ImGui.Col_FrameBgActive, 0x4A5264FF)



    if state.focus_mode then

      -- FOCUS / LOCKED MODE: Subtitles span 100% full height of the window

      -- Discreet dark lock button aligned to the top-right corner

      local win_w = ImGui.GetWindowWidth(ctx)

      local btn_w = 32.0

      local target_x = win_w - btn_w - 14.0



      if state.filename then

        ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x666666FF)

        local mini_info = string.format("[%s] %s (%d)", state.format or "SUB", state.filename, #state.subtitles)

        ImGui.Text(ctx, mini_info)

        ImGui.PopStyleColor(ctx, 1)

        ui.handle_file_drop(ctx, state, ImGui)

        ImGui.SameLine(ctx)

      else

        ImGui.TextDisabled(ctx, "Режим фокуса")

        ui.handle_file_drop(ctx, state, ImGui)

        ImGui.SameLine(ctx)

      end



      -- Mode switcher segmented toggle strictly to the left of the lock button

      local seg_w = 60.0

      local mode_target_x = target_x - seg_w - 6.0

      render_view_mode_segmented_toggle(ctx, state, ImGui, mode_target_x, true)



      -- Dark, non-distracting lock button in top-right corner

      if ImGui.GetCursorPosX(ctx) < target_x then

        ImGui.SameLine(ctx, target_x)

      else

        ImGui.SameLine(ctx, 0, 6.0)

      end



      ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x1A1A1A66)

      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x2A2A2A99)

      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x3A3A3ACC)

      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x777777CC)

      if ImGui.Button(ctx, "🔒###focus_lock_toggle") then

        state.focus_mode = false

        state.need_calc_scroll_target = true

        state.save_settings()

      end

      ImGui.PopStyleColor(ctx, 4)

      if ImGui.IsItemHovered(ctx) then

        set_tooltip(ctx, state, ImGui, "Режим фокуса (полная высота субтитров).\nНажмите, чтобы открыть меню и настройки.")

      end



      ImGui.Spacing(ctx)



      -- Unified geometric center and minimal scale for watermark in Focus Mode (identical for Table and Note View)

      local fc_x, fc_y = ImGui.GetCursorScreenPos(ctx)

      local fc_w, fc_h = ImGui.GetContentRegionAvail(ctx)

      local min_dim = math.min(fc_w, fc_h)

      state.focus_watermark_geo = {

        cx = math.floor(fc_x + fc_w * 0.5),

        cy = math.floor(fc_y + fc_h * 0.5),

        size = math.floor(math.max(90.0, min_dim * 0.50))

      }



      -- Subtitles list spans full remaining height (0, 0)

      ui.render_subtitles_list(ctx, state, ImGui, true)

      ui.handle_file_drop(ctx, state, ImGui)

    else

      -- STANDARD / UNLOCKED MODE: Full UI with toolbar, open lock button, and tabs

      local base_acc, hov_acc, act_acc, soft_acc = get_accent_colors(state, ImGui)

      ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 6.0)



      -- ROW 1: "Load File" button on the left, "Lock" button on the right

      local win_w = ImGui.GetWindowWidth(ctx)

      local lock_btn_w = 32.0

      local lock_target_x = win_w - lock_btn_w - 14.0



      -- Button: Load File (styled with user's accent color)

      ImGui.PushStyleColor(ctx, ImGui.Col_Button, base_acc)

      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, hov_acc)

      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, act_acc)

      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFFFFFFFF)

      if ImGui.Button(ctx, "📁 Загрузить файл субтитров (.ass, .srt)") then

        local fn = nil

        if reaper and reaper.JS_Dialog_BrowseForOpenFiles then

          local rv, files = reaper.JS_Dialog_BrowseForOpenFiles("Выберите файл субтитров (.ass, .srt)", "", "", "Subtitle files (*.ass;*.srt)\0*.ass;*.srt;*.ASS;*.SRT\0ASS files (*.ass)\0*.ass;*.ASS\0SRT files (*.srt)\0*.srt;*.SRT\0All files (*.*)\0*.*\0\0", false)

          if rv and rv > 0 and files and #files > 0 then

            fn = files

          end

        elseif reaper and reaper.GetUserFileNameForRead then

          local rv, chosen = reaper.GetUserFileNameForRead("", "Выберите файл субтитров (.ass, .srt)", "")

          if rv and chosen and #chosen > 0 then

            fn = chosen

          end

        end



        if fn and #fn > 0 then

          fn = fn:gsub("\\", "/")

          if #state.subtitles > 0 then

            state.pending_filepath = fn

            state.show_replace_modal = true

          else

            state.load_file(fn)

            actions.init_timeline_sync(state)

          end

        end

      end

      ImGui.PopStyleColor(ctx, 4)

      ui.handle_file_drop(ctx, state, ImGui)



      ImGui.SameLine(ctx, 0, 8.0)



      -- Button: Export to .ass in Row 1 (Styled identically to Load File with user accent color)

      ImGui.PushStyleColor(ctx, ImGui.Col_Button, base_acc)

      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, hov_acc)

      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, act_acc)

      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFFFFFFFF)

      if ImGui.Button(ctx, "💾 Экспорт в .ass") then

        local default_fn = "subtitles.ass"

        if state.filename and #state.filename > 0 then

          default_fn = state.filename:gsub("%.[^%.]+$", "") .. ".ass"

        end



        local initial_dir = ""

        if state.filepath and #state.filepath > 0 then

          initial_dir = state.filepath:match("^(.*)[/\\]") or ""

        end

        if (not initial_dir or #initial_dir == 0) and reaper and reaper.GetProjectPath then

          local prj_dir = reaper.GetProjectPath("")

          if prj_dir and #prj_dir > 0 then

            initial_dir = prj_dir

          end

        end



        local out_path = nil

        -- Use JS_Dialog_BrowseForSaveFile if available

        if reaper and reaper.JS_Dialog_BrowseForSaveFile then

          local ok_js, rv, chosen = pcall(reaper.JS_Dialog_BrowseForSaveFile, "Сохранить субтитры как .ass", initial_dir or "", default_fn, "ASS Subtitles (*.ass)\0*.ass;*.ASS\0All files (*.*)\0*.*\0\0")

          if ok_js and rv and rv > 0 and chosen and #chosen > 0 then

            out_path = chosen

          end

          -- On cancel/failure, do nothing (never invoke default REAPER modal dialog)

        else

          -- Extension not installed: show missing extension notification modal

          state.show_missing_js_modal = true

        end



        if out_path and #out_path > 0 then

          out_path = out_path:gsub("\\", "/")

          if not out_path:lower():match("%.ass$") then

            out_path = out_path .. ".ass"

          end

          local subs_to_export = (state.sync_with_filter and state.get_filtered_subtitles()) or state.subtitles

          local ok_exp, err_msg = parser.export_to_ass(out_path, subs_to_export, state)

          if ok_exp and reaper and reaper.MB then

            reaper.MB(string.format("Субтитры успешно экспортированы (%d строк):\n%s", #subs_to_export, out_path), "Экспорт завершен", 0)

          elseif not ok_exp and reaper and reaper.MB then

            reaper.MB("Ошибка при экспорте субтитров:\n" .. tostring(err_msg), "Ошибка экспорта", 0)

          end

        end

      end

      ImGui.PopStyleColor(ctx, 4)

      if ImGui.IsItemHovered(ctx) then

        if not (reaper and reaper.JS_Dialog_BrowseForSaveFile) then

          set_tooltip(ctx, state, ImGui, "Для экспорта файлов необходимо расширение:\njs_ReaScriptAPI: API functions for ReaScripts\n(установите через Extensions -> ReaPack -> Browse packages...)")

        else

          set_tooltip(ctx, state, ImGui, "Экспортирует текущий список субтитров в файл формата Advanced SubStation Alpha (.ass)")

        end

      end



      -- Mode switcher segmented toggle strictly to the left of the lock button

      local seg_w = 60.0

      local mode_target_x = lock_target_x - seg_w - 6.0

      render_view_mode_segmented_toggle(ctx, state, ImGui, mode_target_x, false)



      if ImGui.GetCursorPosX(ctx) < lock_target_x then

        ImGui.SameLine(ctx, lock_target_x)

      else

        ImGui.SameLine(ctx, 0, 6.0)

      end



      ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x2A2A2A88)

      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x3E3E3ECC)

      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x4E4E4EEE)

      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xCCCCCCFF)

      if ImGui.Button(ctx, "🔓###focus_lock_toggle") then

        state.focus_mode = true

        state.need_calc_scroll_target = true

        state.save_settings()

      end

      ImGui.PopStyleColor(ctx, 4)

      if ImGui.IsItemHovered(ctx) then

        set_tooltip(ctx, state, ImGui, "Включить режим фокуса (закрыть меню и развернуть субтитры на всю высоту)")

      end



      -- ROW 2: File status and right-aligned "Clear" button

      ImGui.Spacing(ctx)

      local row2_avail_w, _ = ImGui.GetContentRegionAvail(ctx)



      if #state.subtitles > 0 then

        local label_prefix = (state.filename and #state.filename > 0) and "Загруженный файл: " or "Субтитры: "

        local fmt_badge = (state.filename and #state.filename > 0) and string.format("[%s]", state.format or "SUB") or "[ПРОЕКТ]"

        local lines_count_str = string.format("(%d строк)", #state.subtitles)

        local clear_btn_label = "✕ Очистить"

        local clear_btn_txt_w, _ = ImGui.CalcTextSize(ctx, clear_btn_label)

        local clear_btn_w = clear_btn_txt_w + 18.0



        -- Measure widths of fixed parts:

        local w_prefix, _ = ImGui.CalcTextSize(ctx, label_prefix)

        local w_badge, _ = ImGui.CalcTextSize(ctx, fmt_badge)

        local w_count, _ = ImGui.CalcTextSize(ctx, lines_count_str)

        local fixed_total_w = w_prefix + w_badge + w_count + clear_btn_w + 40.0 -- gaps and padding



        -- Available width specifically for the filename

        local max_name_w = math.max(60.0, row2_avail_w - fixed_total_w)

        local full_name = (state.filename and #state.filename > 0) and state.filename or "Субтитры проекта"

        local disp_name = full_name



        -- If full filename doesn't fit, truncate it with ellipsis without cutting off lines count or clear button

        local w_full_name, _ = ImGui.CalcTextSize(ctx, full_name)

        if w_full_name > max_name_w then

          local u_chars = {}

          for uchar in full_name:gmatch("[%z\1-\127\194-\244][\128-\191]*") do

            table.insert(u_chars, uchar)

          end

          local low = 1

          local high = #u_chars

          local best_str = full_name

          while low <= high do

            local mid = math.floor((low + high) * 0.5)

            local candidate = table.concat(u_chars, "", 1, mid) .. "..."

            local c_w, _ = ImGui.CalcTextSize(ctx, candidate)

            if c_w <= max_name_w then

              best_str = candidate

              low = mid + 1

            else

              high = mid - 1

            end

          end

          disp_name = best_str

        end



        ImGui.AlignTextToFramePadding(ctx)

        ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x8892B0FF)

        ImGui.Text(ctx, label_prefix)

        ImGui.PopStyleColor(ctx, 1)



        ImGui.SameLine(ctx, 0, 4.0)

        ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x4ADE80FF)

        ImGui.Text(ctx, fmt_badge)

        ImGui.PopStyleColor(ctx, 1)



        ImGui.SameLine(ctx, 0, 6.0)

        ImGui.Text(ctx, disp_name)

        if disp_name ~= full_name and ImGui.IsItemHovered(ctx) then

          set_tooltip(ctx, state, ImGui, full_name)

        end



        ImGui.SameLine(ctx, 0, 6.0)

        ImGui.TextDisabled(ctx, lines_count_str)



        -- Align "Clear" button to the right border of the window

        local clear_target_x = win_w - clear_btn_w - 14.0

        if ImGui.GetCursorPosX(ctx) < clear_target_x then

          ImGui.SameLine(ctx, clear_target_x)

        else

          ImGui.SameLine(ctx, 0, 8.0)

        end



        ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x33394666)

        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x7F1D1D88)

        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x991B1BCC)

        ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xE2E8F0FF)

        if ImGui.Button(ctx, clear_btn_label, clear_btn_w, 0) then

          local old_snap = state.capture_snapshot and state.capture_snapshot("Очистить все субтитры")

          state.filepath = nil

          state.filename = nil

          state.format = nil

          state.subtitles = {}

          state.actors = {}

          state.actor_counts = {}

          state.actor_palette = {}

          state.selected_actors = {}

          state.selected_real_sub_idx = nil

          state.active_sub_idx = nil

          state.refresh_filter_set()

          actions.clear_regions()

          actions.delete_subtitle_track()

          actions.init_timeline_sync(state)

          if state.push_undo then

            state.push_undo("Очистить все субтитры", old_snap)

          end

          state.save_to_project()

        end

        ImGui.PopStyleColor(ctx, 4)

        if ImGui.IsItemHovered(ctx) then

          set_tooltip(ctx, state, ImGui, "Очистить все субтитры из плагина и с таймлайна (Undoable / Ctrl+Z)")

        end

      else

        ImGui.AlignTextToFramePadding(ctx)

        ImGui.TextDisabled(ctx, "Файл не загружен. Перетащите .ass / .srt в это окно или нажмите Shift+T.")

        ui.handle_file_drop(ctx, state, ImGui)

      end



      ImGui.PopStyleVar(ctx, 1)

      ImGui.Separator(ctx)



      -- Main Navigation Tabs: Flat bottom, top-only rounding, active tab merges into horizontal accent line

      if type(state.active_tab) ~= "string" or state.active_tab == "" or state.active_tab == 0 then

        state.active_tab = "TAB_SUBS"

      end



      local c = (state and state.accent_color) or { 0.16, 0.55, 0.35 }

      local r, g, b = c[1] or 0.16, c[2] or 0.55, c[3] or 0.35



      -- Active tab background: clearly defined pastel accent color

      local active_tab_bg = ImGui.ColorConvertDouble4ToU32(0.12 + r * 0.48, 0.14 + g * 0.48, 0.18 + b * 0.48, 0.95)

      -- Inactive tabs background: subtly tinted with the user's theme color (much less noticeable)

      local inactive_tab_bg = ImGui.ColorConvertDouble4ToU32(0.13 + r * 0.14, 0.14 + g * 0.14, 0.17 + b * 0.14, 0.90)

      -- Horizontal boundary accent line (matching selected active tab color)

      local accent_line_col = active_tab_bg



      local tabs_meta = {

        { id = "TAB_SUBS",          label = "Субтитры" },

        { id = "TAB_ACTORS",        label = "База актеров" },

        { id = "TAB_TEXT_SETTINGS", label = "Настройки текста" },

        { id = "TAB_OVERLAY",       label = "Оверлеи" },

        { id = "TAB_GENERAL",       label = "Общие настройки" },

      }



      local draw_list = ImGui.GetWindowDrawList(ctx)

      local start_x, start_y = ImGui.GetCursorScreenPos(ctx)

      local avail_w, _ = ImGui.GetContentRegionAvail(ctx)

      local tab_h = 28.0

      local line_h = 2.0

      local line_y = start_y + tab_h



      for i, tab in ipairs(tabs_meta) do

        local is_curr = (state.active_tab == tab.id)

        local txt_w, txt_h = ImGui.CalcTextSize(ctx, tab.label)

        local pad_x = 16.0

        local tab_w = txt_w + pad_x * 2.0



        local cur_tab_x, cur_tab_y = ImGui.GetCursorScreenPos(ctx)



        -- Invisible button covering the tab area for interaction (no hover visual change)

        if ImGui.InvisibleButton(ctx, "###tab_nav_" .. tab.id, tab_w, tab_h) then

          state.active_tab = tab.id

          if tab.id == "TAB_SUBS" then

            state.last_centered_idx = -1

            state.need_calc_scroll_target = true

            state.suppress_autoscroll_until = 0

          end

          state.save_settings()

        end



        local bg_col = is_curr and active_tab_bg or inactive_tab_bg

        local txt_col = is_curr and 0xFFFFFFFF or 0xB0BAC8FF



        -- Draw tab background with ONLY top corners rounded (flat bottom edge!)

        local round_flags = ImGui.DrawFlags_RoundCornersTop or 0

        -- For active tab: extend height by 1px so it directly overlaps/touches the accent line

        local tab_bottom_y = is_curr and (line_y + 1.0) or line_y

        ImGui.DrawList_AddRectFilled(draw_list, cur_tab_x, start_y, cur_tab_x + tab_w, tab_bottom_y, bg_col, 6.0, round_flags)



        -- Draw centered text

        local tx = cur_tab_x + (tab_w - txt_w) * 0.5

        local ty = start_y + (tab_h - txt_h) * 0.5

        ImGui.DrawList_AddText(draw_list, tx, ty, txt_col, tab.label)



        if i < #tabs_meta then

          ImGui.SameLine(ctx, 0, 3.0)

        end

      end



      -- Horizontal accent boundary line spanning the full width

      ImGui.DrawList_AddRectFilled(draw_list, start_x, line_y, start_x + avail_w, line_y + line_h, accent_line_col)



      -- Advance cursor below the horizontal accent boundary line properly using Dummy

      ImGui.Dummy(ctx, 0.0, line_h + 6.0)



      -- Common tab content geometry for pixel-identical watermark placement across tabs:

      local content_screen_x, content_screen_y = ImGui.GetCursorScreenPos(ctx)

      local content_avail_w, content_avail_h = ImGui.GetContentRegionAvail(ctx)

      state.watermark_geo = {

        cx = content_screen_x + content_avail_w * 0.5,

        cy = content_screen_y + math.max(180.0, content_avail_h * 0.55),

        max_dim = math.min(content_avail_w, content_avail_h)

      }



      if state.active_tab == "TAB_SUBS" then

        ui.render_tab_subtitles(ctx, state, ImGui)

      elseif state.active_tab == "TAB_TEXT_SETTINGS" then

        ui.render_tab_text_settings(ctx, state, ImGui)

      else

        if ImGui.BeginChild(ctx, "TabContentScrollArea", 0, 0, 0) then

          if state.active_tab == "TAB_ACTORS" then

            ui.render_tab_actors(ctx, state, ImGui)

          elseif state.active_tab == "TAB_OVERLAY" then

            ui.render_tab_overlay(ctx, state, ImGui)

          elseif state.active_tab == "TAB_GENERAL" then

            ui.render_tab_general(ctx, state, ImGui)

          end

          ImGui.EndChild(ctx)

        end

      end

    end



    -- Modals

    ui.render_replace_modal(ctx, state, ImGui)

    ui.render_missing_js_modal(ctx, state, ImGui)

    ui.render_text_edit_modal(ctx, state, ImGui)

    ui.render_sub_actor_modal(ctx, state, ImGui)

    ui.render_rename_actor_modal(ctx, state, ImGui)



    ui.handle_file_drop(ctx, state, ImGui)



    if frame_bg_pushed > 0 then

      ImGui.PopStyleColor(ctx, frame_bg_pushed)

    end



    pcall(ImGui.End, ctx)

  end



  is_frame_active = false



  return open

end



ui.render_main_window = ui.draw



return ui

