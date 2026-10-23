--[[
  @description NutNotes - Create Subtitle from Time Selection
  @version 1.0
  @author NutNotes Community
  @about
    Triggers creation of a new subtitle row in NutNotes based on current REAPER time selection.
--]]

if reaper then
  local is_running = reaper.GetExtState and (reaper.GetExtState("NUTNOTES", "RUNNING") == "true")
  reaper.SetExtState("NUTNOTES", "ACTION_TRIGGER", "create_sub", false)
  if not is_running and reaper.NamedCommandLookup and reaper.Main_OnCommand then
    local cmd_id = reaper.NamedCommandLookup("_RS_NUTNOTES_LAUNCHER")
    if cmd_id and cmd_id > 0 then
      reaper.Main_OnCommand(cmd_id, 0)
    end
  end
end
