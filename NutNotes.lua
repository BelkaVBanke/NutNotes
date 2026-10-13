--[[
  @description NutNotes - REAPER Subtitle & Dubbing Assistant (ASS & SRT)
  @version 0.3.0-beta
  @author NutNotes Community
  @about
    Полнофункциональный плагин/скрипт для Cockos REAPER для работы с субтитрами ASS и SRT.
    - Встраиваемое окно (Docker / Dockable Panel)
    - Drag & Drop субтитров с сохранением per-project и запросом на замену
    - Вкладка "Субтитры": фильтр актеров (ИЛИ), чипы с крестиками, авто-центрирование текущей строки
    - Вкладка "База актеров": цветовой круг 360°/13+ пастельных тонов, чекбоксы фильтра, выбор цветов
    - Вкладка "Оверлей": прозрачное хардсаб-окно поверх видеоряда с автоподстройкой шрифта
    - Кнопки управления: "Задать регионы", "Создать items" на треке subtitle, "Очистить трек"
    - Чекбоксы: "Синхронизировать с фильтром", "Переходить к таймингу по клику", "Авто-прокрутка"
    - Двойной клик по строке для редактирования таймингов и текста
--]]

-- Setup search path for local modules
local info = debug.getinfo(1, 'S')
local script_path = info.source:match([[^@?(.*[\/])[^\/]-$]]) or ""
package.path = script_path .. "?.lua;" .. script_path .. "modules/?.lua;" .. package.path

-- Require ReaImGui
local ImGui
if reaper.ImGui_GetBuiltinPath then
  package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
  local ok, imgui_pkg = pcall(require, 'imgui')
  if ok and type(imgui_pkg) == 'function' then
    for _, ver in ipairs({'0.9', '0.8', '0.10'}) do
      local ok_v, res_v = pcall(imgui_pkg, ver)
      if ok_v and res_v then
        ImGui = res_v
        break
      end
    end
  end
end

if not ImGui then
  ImGui = {}
  for k, v in pairs(reaper) do
    if k:sub(1, 6) == "ImGui_" then
      ImGui[k:sub(7)] = v
    end
  end
end

-- Wrap ImGui metatable so that querying optional/version-dependent fields returns nil instead of throwing errors
-- Also unwraps function-returned constants if ReaImGui returns constants as accessor functions
if ImGui then
  local raw_mt = getmetatable(ImGui)
  if raw_mt and raw_mt.__index then
    local orig_index = raw_mt.__index
    setmetatable(ImGui, {
      __index = function(tbl, key)
        local ok_idx, val = pcall(orig_index, tbl, key)
        if ok_idx and val ~= nil then
          -- In some ReaImGui bindings / shim versions, flags/constants are getter functions
          if type(val) == "function" and (key:match("^[A-Z][A-Za-z0-9_]*Flags") or key:match("^Col_") or key:match("^StyleVar_") or key:match("^Key_") or key:match("^Mod_") or key:match("^DrawFlags_") or key:match("^ConfigVar_")) then
            local ok_call, res = pcall(val)
            if ok_call and res ~= nil then return res end
          end
          return val
        end
        return nil
      end
    })
  end
end

-- Check if ReaImGui is available
if not ImGui.CreateContext then
  reaper.ShowMessageBox(
    "Для работы NutNotes требуется расширение ReaImGui!\n\n" ..
    "Пожалуйста, установите 'ReaImGui: ReaScript binding for Dear ImGui' через ReaPack:\n" ..
    "1. Откройте Extensions -> ReaPack -> Browse packages...\n" ..
    "2. Найдите 'ReaImGui'\n" ..
    "3. Нажмите правой кнопкой мыши -> Install, затем Apply.",
    "Ошибка: ReaImGui не установлен",
    0
  )
  return
end

-- Compatibility wrappers: ReaImGui C shim requires count parameter explicitly
if ImGui.PopStyleColor then
  local raw_pop_color = ImGui.PopStyleColor
  ImGui.PopStyleColor = function(ctx, count)
    return raw_pop_color(ctx, count or 1)
  end
end

if ImGui.PopStyleVar then
  local raw_pop_var = ImGui.PopStyleVar
  ImGui.PopStyleVar = function(ctx, count)
    return raw_pop_var(ctx, count or 1)
  end
end

if ImGui.CreateFont then
  local raw_create_font = ImGui.CreateFont
  ImGui.CreateFont = function(family, arg2, arg3)
    -- ReaImGui 0.10: (family, flags)
    -- If arg3 is given, arg2 is size (0.9), arg3 is flags
    -- If only arg2 is given, in 0.10 it is flags, in 0.9 it is size
    if arg3 ~= nil then
      local ok, f = pcall(raw_create_font, family, arg2, arg3)
      if ok and f then return f end
    end
    -- Try 2 arguments (ReaImGui 0.10: family, flags)
    local ok_10, font_10 = pcall(raw_create_font, family, arg3 or 0)
    if ok_10 and font_10 then return font_10 end
    -- Try 3 arguments (ReaImGui 0.9: family, size, flags)
    local ok_9, font_9 = pcall(raw_create_font, family, arg2 or 16, arg3 or 0)
    if ok_9 and font_9 then return font_9 end
    return raw_create_font(family, 0)
  end
end

if ImGui.PushFont then
  local raw_push_font = ImGui.PushFont
  ImGui.PushFont = function(ctx, font, size)
    if not font then return end
    -- Try 3 arguments first (ReaImGui 0.10+: ctx, font, size)
    if size and size > 0 then
      local ok_3, res_3 = pcall(raw_push_font, ctx, font, size)
      if ok_3 then return res_3 end
    end
    -- Fallback to 2 arguments (ReaImGui 0.9 / 0.8: ctx, font)
    return raw_push_font(ctx, font)
  end
end

-- Load plugin modules
local state = require('state')
local ui = require('ui')
local overlay = require('overlay')
local actions = require('actions')

-- Re-run behavior: seamlessly restart without prompt if already running
if reaper.set_action_options then
  pcall(reaper.set_action_options, 1)
end

-- Create ImGui context with docking support
local config_flags = ImGui.ConfigFlags_DockingEnable
if type(config_flags) == "function" then
  local ok_f, val_f = pcall(config_flags)
  config_flags = (ok_f and val_f) or 0
end
if type(config_flags) ~= "number" then
  config_flags = 0
end
local ctx = ImGui.CreateContext('NutNotes', config_flags)

-- Keyboard passthrough: do not swallow REAPER global hotkeys (e.g. Space play/pause)
-- Keyboard input is only captured when an InputText widget is actively receiving text
local nav_cap = ImGui.ConfigVar_NavCaptureKeyboard
if type(nav_cap) == "function" then nav_cap = nav_cap() end
if nav_cap and ImGui.SetConfigVar then
  pcall(ImGui.SetConfigVar, ctx, nav_cap, 0)
end

-- Load saved project subtitles & settings on launch
state.load_from_project()
actions.init_timeline_sync(state)
actions.return_focus_to_reaper()

-- Pre-initialize fonts and assets before starting frame loop
local watermark = require('watermark')
if ui.init_fonts then ui.init_fonts(ctx, state, ImGui) end
if overlay.init_fonts then overlay.init_fonts(ctx, state, ImGui) end
if watermark.init then watermark.init(ctx, ImGui) end

-- Main loop
local function loop()
  -- Pre-attach any pending fonts before beginning any window or frame
  if ui.check_fonts then ui.check_fonts(ctx, state, ImGui) end
  if overlay.check_fonts then overlay.check_fonts(ctx, state, ImGui) end

  -- Always set keyboard capture for global shortcuts: only capture when text is actively being edited
  local is_text_active = actions.is_text_editing_active(ctx, state, ImGui)
  if ImGui.SetNextFrameWantCaptureKeyboard then
    pcall(ImGui.SetNextFrameWantCaptureKeyboard, ctx, is_text_active)
  end

  -- Two-way timeline duration & position sync (Item <-> Region <-> Subtitles)
  actions.check_timeline_sync(state)

  -- Draw main dockable window and tabs
  local running = ui.draw(ctx, state, ImGui)

  -- Draw floating hardsub overlay window if enabled
  if state.overlay_enabled then
    overlay.draw(ctx, state, ImGui)
  end

  -- Return keyboard focus to REAPER on mouse release (clicks, drags, moving overlay, tab switches, etc.)
  -- Ensures all REAPER shortcuts & binds (Record, Play/Pause, custom actions) work immediately
  if (ImGui.IsMouseReleased(ctx, 0) or ImGui.IsMouseReleased(ctx, 1) or ImGui.IsMouseReleased(ctx, 2)) then
    if not actions.is_text_editing_active(ctx, state, ImGui) and not actions.is_popup_open(ctx, ImGui) then
      actions.return_focus_to_reaper()
    end
  end

  if running then
    reaper.defer(loop)
  else
    -- Save final state on close
    state.save_to_project()
  end
end

-- Start loop
reaper.defer(loop)
