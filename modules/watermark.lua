--[[
  NutNotes - Watermark module for empty state placeholder
  Renders a subtle, semi-transparent placeholder when no subtitles are loaded:
  - In Main Window: subtle circle containing subtle acorn nuts
  - In Overlay Window: subtle acorn nuts without the circle
]]

local watermark = {}

local watermark_img = nil
local watermark_loaded = false

local function get_watermark_image(ctx, ImGui)
  if watermark_loaded then return watermark_img end
  watermark_loaded = true
  if not ImGui or not ImGui.CreateImage then return nil end

  local script_dir = ""
  if debug and debug.getinfo then
    local info = debug.getinfo(1, 'S')
    if info and info.source then
      script_dir = info.source:match([[^@?(.*[\/])[^\/]-$]]) or ""
    end
  end
  local res_path = (reaper and reaper.GetResourcePath) and reaper.GetResourcePath() or ""

  local candidates = {
    script_dir .. "assets/acorn.png",
    script_dir .. "../assets/acorn.png",
    res_path .. "/Scripts/NutNotes/assets/acorn.png",
    res_path .. "/Scripts/MyScripts/assets/acorn.png",
    res_path .. "/Scripts/NutNotes/acorn.png",
    script_dir .. "examples/acorn_3364582.png"
  }

  for _, path in ipairs(candidates) do
    local f = io.open(path, "rb")
    if f then
      f:close()
      local ok, img = pcall(ImGui.CreateImage, path)
      if ok and img then
        if ImGui.Attach then pcall(ImGui.Attach, ctx, img) end
        watermark_img = img
        return watermark_img
      end
    end
  end
  return nil
end

function watermark.init(ctx, ImGui)
  if not ctx or not ImGui then return end
  get_watermark_image(ctx, ImGui)
end

function watermark.draw(ctx, ImGui, center_x, center_y, max_dim, show_circle, state, custom_draw_list)
  if not ctx or not ImGui then return end
  local draw_list = custom_draw_list or (ImGui.GetWindowDrawList and ImGui.GetWindowDrawList(ctx))
  if not draw_list then return end

  local c = (state and state.accent_color) or { 0.16, 0.55, 0.35 }
  local r, g, b = c[1] or 0.16, c[2] or 0.55, c[3] or 0.35
  local style = (state and state.watermark_style) or 1

  local col_circle_fill, col_circle_line, col_acorn

  if style == 1 then
    -- Вариант 1: «Лесной орех и изумрудная дымка»
    -- Кружок: полупрозрачный оттенок текущего акцента (5% заливка, 14% контур)
    -- Орешки: натуральный теплый ореховый цвет (#D4A373) с мягкой прозрачностью 15%
    col_circle_fill = ImGui.ColorConvertDouble4ToU32(r, g, b, 0.05)
    col_circle_line = ImGui.ColorConvertDouble4ToU32(r, g, b, 0.14)
    col_acorn       = ImGui.ColorConvertDouble4ToU32(0.83, 0.64, 0.45, 0.15)

  elseif style == 2 then
    -- Вариант 2: «Адаптивная органика»
    -- Кружок: акцентный полупрозрачный (5% заливка, 12% контур)
    -- Орешки: теплый базовый орех (80%) плавно смешанный с цветом темы (20%), прозрачность 15%
    col_circle_fill = ImGui.ColorConvertDouble4ToU32(r, g, b, 0.05)
    col_circle_line = ImGui.ColorConvertDouble4ToU32(r, g, b, 0.12)
    local nut_r = 0.85 * 0.80 + r * 0.20
    local nut_g = 0.65 * 0.80 + g * 0.20
    local nut_b = 0.45 * 0.80 + b * 0.20
    col_acorn   = ImGui.ColorConvertDouble4ToU32(nut_r, nut_g, nut_b, 0.15)

  else
    -- Вариант 3: «Карамельный орех»
    -- Кружок: чуть высветленный акцент (4% заливка, 10% контур)
    -- Орешки: теплый насыщенный карамельно-бронзовый оттенок (#C68B59), прозрачность 18%
    col_circle_fill = ImGui.ColorConvertDouble4ToU32(math.min(1.0, r + 0.10), math.min(1.0, g + 0.10), math.min(1.0, b + 0.10), 0.04)
    col_circle_line = ImGui.ColorConvertDouble4ToU32(r, g, b, 0.10)
    col_acorn       = ImGui.ColorConvertDouble4ToU32(0.78, 0.55, 0.35, 0.18)
  end

  local img = get_watermark_image(ctx, ImGui)

  if show_circle then
    local radius = math.max(30.0, math.min(94.0, (max_dim or 180.0) * 0.42))
    if ImGui.DrawList_AddCircleFilled then
      pcall(ImGui.DrawList_AddCircleFilled, draw_list, center_x, center_y, radius, col_circle_fill, 64)
    end
    if ImGui.DrawList_AddCircle then
      pcall(ImGui.DrawList_AddCircle, draw_list, center_x, center_y, radius, col_circle_line, 64, 1.5)
    end

    local img_size = radius * 1.30
    if img and ImGui.DrawList_AddImage then
      local h_size = img_size * 0.5
      pcall(ImGui.DrawList_AddImage, draw_list, img,
        center_x - h_size, center_y - h_size,
        center_x + h_size, center_y + h_size,
        0.0, 0.0, 1.0, 1.0, col_acorn
      )
    end
  else
    -- Without circle (Overlay placeholder)
    local img_size = math.max(28.0, math.min(100.0, (max_dim or 100.0) * 0.75))
    if img and ImGui.DrawList_AddImage then
      local h_size = img_size * 0.5
      pcall(ImGui.DrawList_AddImage, draw_list, img,
        center_x - h_size, center_y - h_size,
        center_x + h_size, center_y + h_size,
        0.0, 0.0, 1.0, 1.0, col_acorn
      )
    end
  end
end

return watermark
