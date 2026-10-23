--[[
  Color generation and management module for REAPER Subtitle Plugin.
  Generates pastel colors based on 360-degree color wheel divided by max(13, num_actors).
]]

local colors = {}

-- Convert HSV (h in 0..1, s in 0..1, v in 0..1) to RGB (0..1)
function colors.hsv_to_rgb(h, s, v)
  h = (h or 0) % 1.0
  local r, g, b
  local i = math.floor(h * 6)
  local f = h * 6 - i
  local p = v * (1 - s)
  local q = v * (1 - f * s)
  local t = v * (1 - (1 - f) * s)
  local mod = i % 6

  if mod == 0 then r, g, b = v, t, p
  elseif mod == 1 then r, g, b = q, v, p
  elseif mod == 2 then r, g, b = p, v, t
  elseif mod == 3 then r, g, b = p, q, v
  elseif mod == 4 then r, g, b = t, p, v
  elseif mod == 5 then r, g, b = v, p, q
  end

  return r, g, b
end

-- Convert RGB (0..1) and Alpha (0..1) to ReaImGui 32-bit integer (0xRRGGBBAA)
-- In ReaImGui, ColorConvertDouble4ToU32 converts (r, g, b, a) to U32:
-- uint32: (R << 24) | (G << 16) | (B << 8) | A
function colors.rgb_to_u32(r, g, b, a)
  a = a or 1.0
  local ir = math.min(255, math.max(0, math.floor(r * 255 + 0.5)))
  local ig = math.min(255, math.max(0, math.floor(g * 255 + 0.5)))
  local ib = math.min(255, math.max(0, math.floor(b * 255 + 0.5)))
  local ia = math.min(255, math.max(0, math.floor(a * 255 + 0.5)))
  return (ir * 16777216) + (ig * 65536) + (ib * 256) + ia
end

-- Convert RGB (0..1) to REAPER native color integer (ColorToNative(r, g, b) | 0x1000000)
function colors.rgb_to_reaper(r, g, b)
  local ir = math.min(255, math.max(0, math.floor(r * 255 + 0.5)))
  local ig = math.min(255, math.max(0, math.floor(g * 255 + 0.5)))
  local ib = math.min(255, math.max(0, math.floor(b * 255 + 0.5)))
  if reaper and reaper.ColorToNative then
    return reaper.ColorToNative(ir, ig, ib) | 0x1000000
  end
  local native = ir + (ig * 256) + (ib * 65536)
  return native | 0x1000000
end

-- Unpack U32 (0xRRGGBBAA) back to r, g, b, a (0..1)
function colors.u32_to_rgba(u32)
  local r = ((u32 >> 24) & 0xFF) / 255
  local g = ((u32 >> 16) & 0xFF) / 255
  local b = ((u32 >> 8) & 0xFF) / 255
  local a = (u32 & 0xFF) / 255
  return r, g, b, a
end

-- Generate pastel color palette for actor list
-- Non-actor gets neutral gray; actors get pastel colors distributed on 360-deg wheel
-- Offset by 1 so the first actor starts at 360/divisions instead of 0
function colors.generate_actor_palette(actors_list, default_rgn_col)
  local palette = {}
  local named_actors = {}

  for _, name in ipairs(actors_list or {}) do
    if name ~= "NoActor" then
      table.insert(named_actors, name)
    end
  end

  local def_r, def_g, def_b = 80 / 255, 133 / 255, 133 / 255
  local def_reaper_col = 0
  if default_rgn_col and type(default_rgn_col) == "table" and default_rgn_col[1] then
    def_r = default_rgn_col[1]
    def_g = default_rgn_col[2]
    def_b = default_rgn_col[3]
    def_reaper_col = colors.rgb_to_reaper(def_r, def_g, def_b)
  elseif reaper and reaper.GetThemeColor then
    local tc = reaper.GetThemeColor("region", 0)
    if tc and tc >= 0 then
      def_r = (tc & 0xFF) / 255
      def_g = ((tc >> 8) & 0xFF) / 255
      def_b = ((tc >> 16) & 0xFF) / 255
    end
  end

  -- When only one actor exists in the project, assign default region color instead of palette wheel
  if #named_actors == 1 then
    local single_name = named_actors[1]
    palette[single_name] = {
      r = def_r,
      g = def_g,
      b = def_b,
      a = 1.0,
      u32 = colors.rgb_to_u32(def_r, def_g, def_b, 1.0),
      reaper_color = def_reaper_col,
      hue = 0
    }
  else
    local divisions = math.max(13, #named_actors)
    local sat = 0.55 -- Clear, distinctive pastel saturation
    local val = 0.95 -- Bright clean lightness

    for i, name in ipairs(named_actors) do
      local hue = (i / divisions) % 1.0
      local r, g, b = colors.hsv_to_rgb(hue, sat, val)
      local u32 = colors.rgb_to_u32(r, g, b, 1.0)
      local reaper_col = colors.rgb_to_reaper(r, g, b)

      palette[name] = {
        r = r,
        g = g,
        b = b,
        a = 1.0,
        u32 = u32,
        reaper_color = reaper_col,
        hue = hue * 360
      }
    end
  end

  -- NoActor: assigned default region color
  palette["NoActor"] = {
    r = def_r,
    g = def_g,
    b = def_b,
    a = 1.0,
    u32 = colors.rgb_to_u32(def_r, def_g, def_b, 1.0),
    reaper_color = def_reaper_col,
    hue = 0
  }

  return palette
end

return colors
