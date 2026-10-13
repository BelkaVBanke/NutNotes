--[[
  ASS and SRT subtitle parser for REAPER Subtitle Plugin.
  Supports tag cleaning, actor detection, and accurate timestamp parsing.
]]

local parser = {}

-- Strip UTF-8 BOM if present
function parser.strip_utf8_bom(str)
  if not str then return "" end
  if str:sub(1, 3) == "\239\187\191" then
    str = str:sub(4)
  end
  return str
end

-- Strip invisible formatting Unicode characters like U+200E (Left-to-Right Mark, rendered as a vertical bar with arrow)
function parser.strip_invisible_unicode(str)
  if not str then return "" end
  -- Strip LRM (U+200E: \226\128\142) and RLM (U+200F: \226\128\143)
  str = str:gsub("\226\128\142", "")
  str = str:gsub("\226\128\143", "")
  -- Strip Zero Width No-Break Space / BOM mid-text (U+FEFF: \239\187\191)
  str = str:gsub("\239\187\191", "")
  -- Strip Zero Width Space (U+200B: \226\128\139), ZWNJ (\226\128\140), ZWJ (\226\128\141)
  str = str:gsub("\226\128\139", "")
  str = str:gsub("\226\128\140", "")
  str = str:gsub("\226\128\141", "")
  -- Strip directional embeddings and overrides (U+202A - U+202E: \226\128[\170-\174])
  str = str:gsub("\226\128[\170-\174]", "")
  -- Strip directional isolates (U+2066 - U+2069: \226\129[\166-\169])
  str = str:gsub("\226\129[\166-\169]", "")
  return str
end

-- Truncate string with UTF-8 character awareness and add ellipsis
function parser.truncate_utf8(str, max_chars)
  if not str then return "" end
  max_chars = max_chars or 40
  local count = 0
  local byte_idx = 0
  for uchar in str:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    count = count + 1
    if count > max_chars then
      return str:sub(1, byte_idx) .. "..."
    end
    byte_idx = byte_idx + #uchar
  end
  return str
end

-- Format seconds to "HH:MM:SS.cc"
function parser.format_time(sec)
  if not sec or sec < 0 then sec = 0 end
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  local s = math.floor(sec % 60)
  local cs = math.floor((sec - math.floor(sec)) * 100 + 0.5)
  if cs >= 100 then cs = 99 end
  return string.format("%02d:%02d:%02d.%02d", h, m, s, cs)
end

-- Parse ASS timestamp: "H:MM:SS.cs" or "HH:MM:SS.cs" -> seconds
function parser.parse_ass_time(str)
  local h, m, s, cs = str:match("(%d+):(%d+):(%d+)%.(%d+)")
  if h and m and s and cs then
    local cs_val = tonumber(cs)
    -- Handle variable length centiseconds/milliseconds
    local frac = cs_val / (10 ^ #cs)
    return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s) + frac
  end
  return 0
end

-- Parse SRT timestamp: "HH:MM:SS,mmm" or "HH:MM:SS.mmm" -> seconds
function parser.parse_srt_time(str)
  local h, m, s, ms = str:match("(%d+):(%d+):(%d+)[,.](%d+)")
  if h and m and s and ms then
    local ms_val = tonumber(ms)
    local frac = ms_val / (10 ^ #ms)
    return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s) + frac
  end
  return 0
end

-- Clean ASS text: strip {\...} tags, invisible Unicode marks, and convert \N to newlines
function parser.clean_ass_text(text)
  if not text then return "" end
  text = parser.strip_invisible_unicode(text)
  -- Replace escaped newlines
  text = text:gsub("\\N", "\n"):gsub("\\n", "\n"):gsub("\\h", " ")
  -- Strip style tags like {\an8}, {\b1}, {\c&HFFFFFF&}
  text = text:gsub("{[^}]+}", "")
  -- Strip carriage returns
  text = text:gsub("\r", "")
  -- Trim leading/trailing whitespace
  text = text:match("^%s*(.-)%s*$") or text
  return text
end

-- Clean SRT text: strip HTML/formatting tags like <i>, </b>, <font...>, and invisible Unicode marks
function parser.clean_srt_text(text)
  if not text then return "" end
  text = parser.strip_invisible_unicode(text)
  text = text:gsub("<[^>]+>", "")
  text = text:gsub("\r", "")
  text = text:match("^%s*(.-)%s*$") or text
  return text
end

-- Parse actor in SRT text line
function parser.parse_srt_actor(text)
  if not text then return "NoActor", "" end

  -- 1. WebVTT/SRT voice tag: <v ActorName>Dialogue</v>
  local v_actor, v_dialogue = text:match("^<v%s+([^>]+)>(.-)</v>%s*$")
  if not v_actor then
    v_actor, v_dialogue = text:match("^<v%s+([^>]+)>(.*)$")
  end
  if v_actor and #v_actor > 0 then
    return v_actor:match("^%s*(.-)%s*$"), parser.clean_srt_text(v_dialogue)
  end

  -- Clean other tags before regex
  local clean = parser.clean_srt_text(text)

  -- 2. Multi/single bracket tags: [Actor1][Actor2] Dialogue or [Actor1] Dialogue
  if clean:match("^%[[^%]]+%]") then
    local pos = 1
    local brackets = {}
    while true do
      local b_start, b_end, b_content = clean:find("^%s*%[([^%]]+)%]", pos)
      if b_start then
        table.insert(brackets, b_content:match("^%s*(.-)%s*$"))
        pos = b_end + 1
      else
        break
      end
    end
    if #brackets > 0 then
      local is_all_num = true
      for _, b in ipairs(brackets) do
        if not b:match("^%d+$") then is_all_num = false break end
      end
      if not is_all_num then
        local rest = clean:sub(pos):match("^%s*:?%s*(.*)$") or ""
        if #brackets == 1 then
          local b_actor = brackets[1]
          if #b_actor <= 50 then
            return b_actor, rest:match("^%s*(.-)%s*$")
          end
        else
          local b_actor = "[" .. table.concat(brackets, "][") .. "]"
          return b_actor, rest:match("^%s*(.-)%s*$")
        end
      end
    end
  end

  -- 3. Parenthesis tag: (ActorName): Dialogue or (ActorName) Dialogue
  local p_actor, p_dialogue = clean:match("^%(([^%)]+)%)%s*:?%s*(.*)$")
  if p_actor and #p_actor <= 50 and not p_actor:match("^%d+$") then
    return p_actor:match("^%s*(.-)%s*$"), p_dialogue:match("^%s*(.-)%s*$")
  end

  -- 4. Colon prefix: ActorName: Dialogue
  local c_actor, c_dialogue = clean:match("^([^:\r\n]+):%s*(.*)$")
  if c_actor and #c_actor <= 50 then
    local trimmed_actor = c_actor:match("^%s*(.-)%s*$")
    local clean_diag = c_dialogue and c_dialogue:match("^%s*(.-)%s*$") or ""
    -- Must have actual dialogue following the colon
    if #clean_diag > 0
       and trimmed_actor
       and not trimmed_actor:lower():find("^https?://")
       and not trimmed_actor:match("^%d+$")
       and not trimmed_actor:match("^%d%d$")
       and #trimmed_actor > 0 then
      -- Avoid false positives on direct speech sentences like 'А если бы сказал: "Привет"'
      local is_dialogue_clause = false
      local particles = {
        ["а"]=true, ["А"]=true, ["и"]=true, ["И"]=true, ["но"]=true, ["Но"]=true,
        ["если"]=true, ["Если"]=true, ["бы"]=true, ["Бы"]=true, ["ли"]=true, ["же"]=true,
        ["не"]=true, ["Не"]=true, ["что"]=true, ["Что"]=true, ["как"]=true, ["Как"]=true,
        ["когда"]=true, ["Когда"]=true
      }
      for word in trimmed_actor:gmatch("%S+") do
        local clean_w = word:gsub("[%.,!%?\"']", "")
        if particles[clean_w] then
          is_dialogue_clause = true
          break
        end
      end
      if not is_dialogue_clause then
        return trimmed_actor, clean_diag
      end
    end
  end

  return "NoActor", clean
end

-- Parse actor(s) and character(s) from ASS Name field or SRT
-- Supports: "Actor - Character", "[Actor1][Actor2]", "Actor 1; Actor 2 - Char 1; Char 2", "Actor 1 ; Actor 2", etc.
function parser.parse_actor_and_character(raw)
  if not raw or #raw == 0 then
    return { "NoActor" }, "", "NoActor"
  end

  raw = parser.strip_invisible_unicode(raw)
  local trimmed = raw:match("^%s*(.-)%s*$")
  if #trimmed == 0 then
    return { "NoActor" }, "", "NoActor"
  end

  -- Check if raw contains bracketed tags like [Actor1][Actor2] or [Actor1]
  local bracket_matches = {}
  for b in trimmed:gmatch("%[([^%]]+)%]") do
    local b_trimmed = b:match("^%s*(.-)%s*$")
    if #b_trimmed > 0 then
      table.insert(bracket_matches, b_trimmed)
    end
  end

  if #bracket_matches > 0 then
    local actors = {}
    local chars = {}
    local seen_actors = {}
    local seen_chars = {}

    for _, b_item in ipairs(bracket_matches) do
      local a_part = b_item
      local c_part = ""
      local dash_start, dash_end = b_item:find("%s+[%-—–]%s*")
      if not dash_start then
        dash_start, dash_end = b_item:find("%s*[%-—–]%s+")
      end
      if dash_start then
        a_part = b_item:sub(1, dash_start - 1):match("^%s*(.-)%s*$")
        c_part = b_item:sub(dash_end + 1):match("^%s*(.-)%s*$")
      else
        local paren_act, paren_char = b_item:match("^([^%(%)]+)%s*%(([^%(%)]+)%)%s*$")
        if paren_act and paren_char then
          a_part = paren_act:match("^%s*(.-)%s*$")
          c_part = paren_char:match("^%s*(.-)%s*$")
        end
      end

      local normalized = a_part:gsub("%s*[%/;%&%+]%s*", "|")
      for part in normalized:gmatch("[^|]+") do
        local act = part:match("^%s*(.-)%s*$")
        if act and #act > 0 and not seen_actors[act] then
          seen_actors[act] = true
          table.insert(actors, act)
        end
      end

      if c_part and #c_part > 0 and not seen_chars[c_part] then
        seen_chars[c_part] = true
        table.insert(chars, c_part)
      end
    end

    if #actors == 0 then
      actors = { "NoActor" }
    end

    local display_actor
    if #actors == 1 then
      display_actor = actors[1]
    else
      display_actor = "[" .. table.concat(actors, "][") .. "]"
    end

    return actors, table.concat(chars, "; "), display_actor
  end

  -- Non-bracketed text (e.g. ASS format Name field or standard SRT):
  local actors_part = trimmed
  local chars_part = ""

  -- Look for delimiter between Actor(s) and Character(s): " - ", " – ", " — ", or "- " or " -"
  -- Does NOT match hyphens inside compound names like "Лорд-Тюлень" (hyphen without spaces)
  local dash_start, dash_end = trimmed:find("%s+[%-—–]%s*")
  if not dash_start then
    dash_start, dash_end = trimmed:find("%s*[%-—–]%s+")
  end

  if dash_start then
    actors_part = trimmed:sub(1, dash_start - 1):match("^%s*(.-)%s*$")
    chars_part = trimmed:sub(dash_end + 1):match("^%s*(.-)%s*$")
  else
    local paren_act, paren_char = trimmed:match("^([^%(%)]+)%s*%(([^%(%)]+)%)%s*$")
    if paren_act and paren_char then
      actors_part = paren_act:match("^%s*(.-)%s*$")
      chars_part = paren_char:match("^%s*(.-)%s*$")
    end
  end

  -- Split actors_part by ; / & + with deduplication
  local actors = {}
  local seen_actors = {}
  local normalized = actors_part:gsub("%s*[%/;%&%+]%s*", "|")
  for part in normalized:gmatch("[^|]+") do
    local a_clean = part:match("^%s*(.-)%s*$")
    if a_clean and #a_clean > 0 and not seen_actors[a_clean] then
      seen_actors[a_clean] = true
      table.insert(actors, a_clean)
    end
  end

  if #actors == 0 then
    actors = { "NoActor" }
  end

  local display_actor
  if #actors == 1 then
    display_actor = actors[1]
  else
    display_actor = table.concat(actors, "; ")
  end

  return actors, chars_part, display_actor
end

-- Parse ASS content
function parser.parse_ass(content)
  content = parser.strip_utf8_bom(content)
  local lines = {}
  for line in content:gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end

  local in_events = false
  local format_cols = nil
  local start_idx, end_idx, name_idx, text_idx = nil, nil, nil, nil

  local subtitles = {}
  local actors_set = {}
  local actor_counts = {}

  for _, line in ipairs(lines) do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed:sub(1, 1) == "[" and trimmed:sub(-1) == "]" then
      if trimmed:lower() == "[events]" then
        in_events = true
      else
        in_events = false
      end
    elseif in_events then
      local lower_line = trimmed:lower()
      if lower_line:sub(1, 7) == "format:" then
        local header = trimmed:sub(8):match("^%s*(.-)%s*$")
        format_cols = {}
        for col in header:gmatch("[^,]+") do
          local clean_col = col:match("^%s*(.-)%s*$"):lower()
          table.insert(format_cols, clean_col)
          local idx = #format_cols
          if clean_col == "start" then start_idx = idx
          elseif clean_col == "end" then end_idx = idx
          elseif clean_col == "name" or clean_col == "actor" then name_idx = idx
          elseif clean_col == "text" then text_idx = idx
          end
        end
      elseif lower_line:sub(1, 9) == "dialogue:" then
        if format_cols and start_idx and end_idx then
          local body = trimmed:sub(10):match("^%s*(.-)%s*$")
          local parts = {}
          local max_split = #format_cols - 1
          local cur_pos = 1

          for _ = 1, max_split do
            local comma_pos = body:find(",", cur_pos)
            if comma_pos then
              table.insert(parts, body:sub(cur_pos, comma_pos - 1):match("^%s*(.-)%s*$"))
              cur_pos = comma_pos + 1
            else
              break
            end
          end
          -- Remainder is the Text column
          table.insert(parts, body:sub(cur_pos))

          local t_start = parser.parse_ass_time(parts[start_idx] or "0:00:00.00")
          local t_end = parser.parse_ass_time(parts[end_idx] or "0:00:00.00")
          local raw_actor = name_idx and parts[name_idx] or ""
          local raw_text = text_idx and parts[text_idx] or parts[#parts] or ""

          local actors, character, display_actor = parser.parse_actor_and_character(raw_actor)
          local text = parser.clean_ass_text(raw_text)

          if #text > 0 or t_end > t_start then
            table.insert(subtitles, {
              start_time = t_start,
              end_time = t_end,
              actor = display_actor,
              actors = actors,
              character = character,
              raw_actor = raw_actor,
              text = text
            })
            local seen_in_sub = {}
            for _, a in ipairs(actors) do
              if not seen_in_sub[a] then
                seen_in_sub[a] = true
                actors_set[a] = true
                actor_counts[a] = (actor_counts[a] or 0) + 1
              end
            end
          end
        end
      end
    end
  end

  local actors_list = {}
  for actor in pairs(actors_set) do
    table.insert(actors_list, actor)
  end
  table.sort(actors_list, function(a, b)
    if a == "NoActor" then return false end
    if b == "NoActor" then return true end
    return a:lower() < b:lower()
  end)

  return {
    ok = true,
    format = "ASS",
    subtitles = subtitles,
    actors = actors_list,
    actor_counts = actor_counts
  }
end

-- Parse SRT content (fast linear single-pass parser)
function parser.parse_srt(content)
  content = parser.strip_utf8_bom(content)
  content = parser.strip_invisible_unicode(content)
  content = content:gsub("\r\n", "\n"):gsub("\r", "\n")

  local subtitles = {}
  local actors_set = {}
  local actor_counts = {}

  local cur_timing_start = nil
  local cur_timing_end = nil
  local cur_text_lines = {}

  local function flush_block()
    if cur_timing_start and cur_timing_end and #cur_text_lines > 0 then
      -- If last text line was an index number for the next subtitle (in case of missing blank line)
      if #cur_text_lines > 1 and cur_text_lines[#cur_text_lines]:match("^%d+$") then
        table.remove(cur_text_lines)
      end
      local raw_text = table.concat(cur_text_lines, "\n")
      local raw_actor, clean_text = parser.parse_srt_actor(raw_text)
      local actors, character, display_actor = parser.parse_actor_and_character(raw_actor)

      table.insert(subtitles, {
        start_time = cur_timing_start,
        end_time = cur_timing_end,
        actor = display_actor,
        actors = actors,
        character = character,
        raw_actor = raw_actor,
        text = clean_text
      })

      local seen_in_sub = {}
      for _, a in ipairs(actors) do
        if not seen_in_sub[a] then
          seen_in_sub[a] = true
          actors_set[a] = true
          actor_counts[a] = (actor_counts[a] or 0) + 1
        end
      end
    end
    cur_timing_start = nil
    cur_timing_end = nil
    cur_text_lines = {}
  end

  for line in (content .. "\n"):gmatch("([^\n]*)\n") do
    local trimmed = line:match("^%s*(.-)%s*$")
    local s_start, s_end = trimmed:match("(%d+:%d+:%d+[,.]%d+)%s*%-%-%>%s*(%d+:%d+:%d+[,.]%d+)")
    if s_start and s_end then
      flush_block()
      cur_timing_start = parser.parse_srt_time(s_start)
      cur_timing_end = parser.parse_srt_time(s_end)
    elseif cur_timing_start and cur_timing_end then
      if #trimmed > 0 then
        table.insert(cur_text_lines, trimmed)
      else
        flush_block()
      end
    end
  end

  flush_block()

  local actors_list = {}
  for actor in pairs(actors_set) do
    table.insert(actors_list, actor)
  end
  table.sort(actors_list, function(a, b)
    if a == "NoActor" then return false end
    if b == "NoActor" then return true end
    return a:lower() < b:lower()
  end)

  return {
    ok = true,
    format = "SRT",
    subtitles = subtitles,
    actors = actors_list,
    actor_counts = actor_counts
  }
end

-- Auto-detect format and parse
function parser.parse(content, filename_or_ext)
  local ext = ""
  if filename_or_ext then
    ext = filename_or_ext:match("%.([^%.]+)$") or filename_or_ext
    ext = ext:lower()
  end

  if ext == "ass" or ext == "ssa" or content:find("%[Script Info%]") or content:find("%[Events%]") then
    return parser.parse_ass(content)
  elseif ext == "srt" or content:find("%-%->") then
    return parser.parse_srt(content)
  else
    -- Try ASS first, then SRT
    if content:find("%[Events%]") then
      return parser.parse_ass(content)
    else
      return parser.parse_srt(content)
    end
  end
end

-- Read from disk and parse
function parser.parse_file(filepath)
  local f, err = io.open(filepath, "rb")
  if not f then
    return { ok = false, error = "Cannot open file: " .. tostring(err) }
  end
  local content = f:read("*a")
  f:close()

  if not content or #content == 0 then
    return { ok = false, error = "File is empty: " .. filepath }
  end

  local res = parser.parse(content, filepath)
  if res and res.ok then
    res.filepath = filepath
    res.filename = filepath:match("([^/\\]+)$") or filepath
  end
  return res
end

return parser
