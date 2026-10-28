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

-- Full UTF-8 case-insensitive converter (supporting ASCII, Latin, and Russian/Cyrillic А..Я, Ё)
function parser.utf8_lower(str)
  if not str then return "" end
  -- 1. Standard ASCII lowercase
  local s = str:lower()
  -- 2. Russian Cyrillic uppercase: Ё -> ё
  s = s:gsub("\208\129", "\209\145")
  -- 3. Russian Cyrillic uppercase: А..П (0xD0 0x90..0x9F) -> а..п (0xD0 0xB0..0xBF)
  s = s:gsub("\208([\144-\159])", function(c)
    return "\208" .. string.char(c:byte(1) + 32)
  end)
  -- 4. Russian Cyrillic uppercase: Р..Я (0xD0 0xA0..0xAF) -> р..я (0xD1 0x80..0x8F)
  s = s:gsub("\208([\160-\175])", function(c)
    return "\209" .. string.char(c:byte(1) - 32)
  end)
  return s
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

-- Universal subtitle tag cleaner: strips braced ASS tags ({...}), HTML tags (<...>),
-- and unbraced ASS override tags (\c&Hffffff&, \1c&H...&, \an8, \i1, \b0, \pos(...), etc.)
function parser.strip_formatting_tags(text)
  if not text then return "" end
  text = parser.strip_invisible_unicode(text)

  -- 1. Standard ASS escaped spaces and newlines
  text = text:gsub("\\N", "\n"):gsub("\\n", "\n"):gsub("\\h", " ")

  -- 2. Strip braced ASS style override blocks: {...}
  text = text:gsub("{[^}]+}", "")

  -- 3. Strip HTML/XML formatting tags: <...> (e.g. <i>, </b>, <font...>)
  text = text:gsub("<[^>]+>", "")

  -- 4. Strip unbraced ASS color and alpha override tags (e.g. \c&Hffffff&, \1c&H...&, \3a&H...&)
  text = text:gsub("\\[1-4]?[ca]&H%x+&?", "")

  -- 5. Strip unbraced ASS tags with parenthesized parameters (\pos(...), \fad(...), \move(...), \org(...), etc.)
  text = text:gsub("\\[%a]+%b()", "")

  -- 6. Strip unbraced ASS simple style tags (\i0, \i1, \b0, \b1, \u0, \s0, \an8, \a9, \fs20, \q2, etc.)
  text = text:gsub("\\[abikouprs][%a%d_]*", "")

  -- 7. Strip leftover backslash tags like \blur1, \fscx100, \bord2
  text = text:gsub("\\[%a]+[%d%.]*", "")

  -- 8. Strip carriage returns and trim whitespace
  text = text:gsub("\r", "")
  text = text:match("^%s*(.-)%s*$") or text
  return text
end

-- Stably sort subtitles in chronological order by start_time (then end_time)
function parser.sort_subtitles(subs)
  if not subs or #subs <= 1 then return subs end
  for i = 1, #subs do
    subs[i]._orig_idx = i
  end
  table.sort(subs, function(a, b)
    local diff = a.start_time - b.start_time
    if math.abs(diff) > 0.0001 then
      return a.start_time < b.start_time
    end
    local diff_end = (a.end_time or 0) - (b.end_time or 0)
    if math.abs(diff_end) > 0.0001 then
      return (a.end_time or 0) < (b.end_time or 0)
    end
    return (a._orig_idx or 0) < (b._orig_idx or 0)
  end)
  for i = 1, #subs do
    subs[i]._orig_idx = nil
  end
  return subs
end

-- Clean ASS text: strip all formatting tags and convert escapes
function parser.clean_ass_text(text)
  return parser.strip_formatting_tags(text)
end

-- Clean SRT text: strip HTML/formatting tags and unbraced ASS override codes
function parser.clean_srt_text(text)
  return parser.strip_formatting_tags(text)
end

-- Detect if a candidate string is an obvious director note / stage direction / foley effect
-- instead of an actor name. Keeps such notes intact in dialogue text.
function parser.is_director_note(str)
  if not str or #str == 0 then return false end
  local s = str:lower():match("^%s*(.-)%s*$")
  if not s or #s == 0 then return false end

  -- Sound and foley keywords anywhere in the phrase
  local sound_keywords = {
    "звук", "шум", "стук", "звон", "лязг", "грохот", "шаг", "выстрел", "музык",
    "взрыв", "гудок", "скрип", "треск", "кашель", "хлопок", "сирен", "шепот", "шёпот",
    "дыхани", "дышит", "голос", "пауз", "вздох", "смех", "плач", "крик", "поворач", "оглядыв"
  }
  for _, kw in ipairs(sound_keywords) do
    if s:find(kw, 1, true) then
      return true
    end
  end

  local exact_notes = {
    ["тихо"]=true, ["громко"]=true, ["кричит"]=true, ["вскрикивает"]=true, ["вскрик"]=true,
    ["смеется"]=true, ["смеётся"]=true, ["усмехается"]=true, ["плачет"]=true, ["рыдает"]=true, ["рыдание"]=true,
    ["всхлипывает"]=true, ["всхлип"]=true, ["молчание"]=true,
    ["в сторону"]=true, ["вбок"]=true, ["за кадром"]=true, ["з.к."]=true, ["зк"]=true, ["з/к"]=true,
    ["по телефону"]=true, ["по рации"]=true, ["рация"]=true, ["телефон"]=true,
    ["мысли"]=true, ["про себя"]=true, ["сонно"]=true, ["устало"]=true, ["сердито"]=true, ["испуганно"]=true,
    ["радостно"]=true, ["грустно"]=true, ["сарказм"]=true, ["иронично"]=true, ["зевает"]=true, ["стонет"]=true, ["стон"]=true,
    ["быстро"]=true, ["медленно"]=true, ["спокойно"]=true, ["холодно"]=true,
    ["хмыкает"]=true, ["хмыкнул"]=true, ["бормочет"]=true, ["напевает"]=true, ["поет"]=true, ["поёт"]=true, ["сдавленно"]=true, ["злобно"]=true,
    ["ехидно"]=true, ["недовольно"]=true, ["возмущенно"]=true, ["удивленно"]=true,
    ["растерянно"]=true, ["дрожащим голосом"]=true, ["сквозь слезы"]=true,
    ["сквозь зубы"]=true, ["поворачивается"]=true, ["оглядывается"]=true,
    ["перебивает"]=true, ["перебивая"]=true, ["улыбается"]=true, ["улыбаясь"]=true,
    ["смеясь"]=true, ["плача"]=true, ["крича"]=true, ["задыхаясь"]=true, ["хрипит"]=true, ["шепчет"]=true, ["рычит"]=true,
    ["воет"]=true, ["пищит"]=true, ["заикается"]=true, ["дрожит"]=true,
    ["в ужасе"]=true, ["в ярости"]=true, ["с насмешкой"]=true, ["с иронией"]=true
  }
  if exact_notes[s] then
    return true
  end

  for w in s:gmatch("%S+") do
    local clean_w = w:gsub("[%p]", "")
    if exact_notes[clean_w] then
      return true
    end
    if clean_w:find("ось$") or clean_w:find("ясь$") or clean_w:find("вшись$") or clean_w:find("ая$") or clean_w:find("яя$") then
      return true
    end
  end

  return false
end

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
        local trimmed_rest = rest:match("^%s*(.-)%s*$") or ""
        -- If no dialogue follows the bracket, it's a sound effect or caption (e.g. "[Шум дождя]"), not an actor!
        if #trimmed_rest > 0 then
          if #brackets == 1 then
            local b_actor = brackets[1]
            if #b_actor <= 40 and not parser.is_director_note(b_actor) then
              return b_actor, trimmed_rest
            end
          else
            local has_note = false
            for _, b in ipairs(brackets) do
              if parser.is_director_note(b) then has_note = true break end
            end
            if not has_note then
              local b_actor = "[" .. table.concat(brackets, "][") .. "]"
              return b_actor, trimmed_rest
            end
          end
        end
      end
    end
  end

  -- 3. Parenthesis tag: (ActorName): Dialogue or (ActorName) Dialogue
  local p_actor, p_dialogue = clean:match("^%(([^%)]+)%)%s*:?%s*(.*)$")
  if p_actor and #p_actor <= 40 and not p_actor:match("^%d+$") then
    local trimmed_p_diag = p_dialogue and p_dialogue:match("^%s*(.-)%s*$") or ""
    -- If no dialogue follows or it's an obvious director note, keep it intact in dialogue text!
    if #trimmed_p_diag > 0 and not parser.is_director_note(p_actor) then
      return p_actor:match("^%s*(.-)%s*$"), trimmed_p_diag
    end
  end

  -- 4. Colon prefix: ActorName: Dialogue
  local c_actor, c_dialogue = clean:match("^([^:\r\n]+):%s*(.*)$")
  if c_actor and #c_actor <= 35 and not parser.is_director_note(c_actor) then
    local trimmed_actor = c_actor:match("^%s*(.-)%s*$")
    local clean_diag = c_dialogue and c_dialogue:match("^%s*(.-)%s*$") or ""
    if #clean_diag > 0
       and trimmed_actor
       and not trimmed_actor:lower():find("^https?://")
       and not trimmed_actor:match("^%d+$")
       and not trimmed_actor:match("^%d%d$")
       and #trimmed_actor > 0 then
      local is_dialogue_clause = false
      local word_count = 0
      local particles = {
        ["а"]=true, ["А"]=true, ["и"]=true, ["И"]=true, ["но"]=true, ["Но"]=true,
        ["если"]=true, ["Если"]=true, ["бы"]=true, ["Бы"]=true, ["ли"]=true, ["же"]=true,
        ["не"]=true, ["Не"]=true, ["что"]=true, ["Что"]=true, ["как"]=true, ["Как"]=true,
        ["когда"]=true, ["Когда"]=true, ["он"]=true, ["Он"]=true, ["она"]=true, ["Она"]=true,
        ["они"]=true, ["Они"]=true, ["то"]=true, ["То"]=true, ["так"]=true, ["Так"]=true
      }
      for word in trimmed_actor:gmatch("%S+") do
        word_count = word_count + 1
        local clean_w = word:gsub("[%p]", "")
        if particles[clean_w] then
          is_dialogue_clause = true
          break
        end
      end
      if not is_dialogue_clause and word_count <= 4 then
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

  parser.sort_subtitles(subtitles)

  return {
    ok = true,
    format = "ASS",
    subtitles = subtitles,
    actors = actors_list,
    actor_counts = actor_counts
  }
end

-- Parse SRT content (fast linear single-pass parser)
function parser.parse_srt(content, opts)
  content = parser.strip_utf8_bom(content)
  content = parser.strip_invisible_unicode(content)
  content = content:gsub("\r\n", "\n"):gsub("\r", "\n")

  local parse_actors = true
  if opts then
    if opts.parse_srt_actors ~= nil then
      parse_actors = opts.parse_srt_actors
    elseif opts.smart_srt_actors ~= nil then
      parse_actors = opts.smart_srt_actors
    end
  end

  local subtitles = {}
  local actors_set = {}
  local actor_counts = {}

  local cur_timing_start = nil
  local cur_timing_end = nil
  local cur_text_lines = {}

  local function flush_block()
    if cur_timing_start and cur_timing_end and #cur_text_lines > 0 then
      if #cur_text_lines > 1 and cur_text_lines[#cur_text_lines]:match("^%d+$") then
        table.remove(cur_text_lines)
      end
      local raw_text = table.concat(cur_text_lines, "\n")
      if not parse_actors then
        local clean_text = parser.clean_srt_text(raw_text)
        table.insert(subtitles, {
          start_time = cur_timing_start,
          end_time = cur_timing_end,
          actor = "NoActor",
          actors = { "NoActor" },
          character = "",
          raw_actor = "",
          text = clean_text,
          _raw_block_text = raw_text
        })
        actors_set["NoActor"] = true
        actor_counts["NoActor"] = (actor_counts["NoActor"] or 0) + 1
      else
        local raw_actor, clean_text = parser.parse_srt_actor(raw_text)
        local actors, character, display_actor = parser.parse_actor_and_character(raw_actor)

        table.insert(subtitles, {
          start_time = cur_timing_start,
          end_time = cur_timing_end,
          actor = display_actor,
          actors = actors,
          character = character,
          raw_actor = raw_actor,
          text = clean_text,
          _raw_block_text = raw_text
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

  -- Smart SRT Actor Heuristics:
  -- Detect and fix false-positive actors in plain SRT files
  -- Smart SRT heuristics are applied automatically when SRT actor parsing is enabled
  if parse_actors and #subtitles >= 8 then
    local total_subs = #subtitles
    local actor_subs_count = 0
    local empty_text_actor_subs = 0
    local actor_line_counts = {}

    for _, sub in ipairs(subtitles) do
      if sub.actor and sub.actor ~= "NoActor" then
        actor_subs_count = actor_subs_count + 1
        actor_line_counts[sub.actor] = (actor_line_counts[sub.actor] or 0) + 1
        if not sub.text or #sub.text == 0 then
          empty_text_actor_subs = empty_text_actor_subs + 1
        end
      end
    end

    local distinct_actor_count = 0
    for _ in pairs(actor_line_counts) do
      distinct_actor_count = distinct_actor_count + 1
    end

    local is_false_positive = false
    -- Case 1: Almost all lines have no actors, and only 1-2 lines have an actor
    if actor_subs_count > 0 and actor_subs_count <= 2 and total_subs >= 15 then
      is_false_positive = true
    -- Case 2: Subtitles with actors are a tiny fraction (< 4%) of a large file (e.g. 8 lines out of 3500)
    elseif actor_subs_count > 0 and (actor_subs_count / total_subs) < 0.04 then
      is_false_positive = true
    -- Case 3: Many empty text lines caused by stage directions / sounds in brackets/parentheses
    elseif empty_text_actor_subs > 0 and (empty_text_actor_subs / math.max(1, actor_subs_count)) > 0.15 then
      is_false_positive = true
    -- Case 4: High number of distinct actors where nearly each actor has only 1 line
    elseif distinct_actor_count >= 8 and (actor_subs_count / distinct_actor_count) < 1.35 then
      is_false_positive = true
    end

    if is_false_positive then
      actors_set = { ["NoActor"] = true }
      actor_counts = { ["NoActor"] = total_subs }
      for _, sub in ipairs(subtitles) do
        if sub.actor and sub.actor ~= "NoActor" then
          if sub._raw_block_text and #sub._raw_block_text > 0 then
            sub.text = parser.clean_srt_text(sub._raw_block_text)
          elseif not sub.text or #sub.text == 0 then
            sub.text = sub.raw_actor or sub.actor
          else
            sub.text = (sub.raw_actor or sub.actor) .. ": " .. sub.text
          end
          sub.actor = "NoActor"
          sub.actors = { "NoActor" }
          sub.character = ""
          sub.raw_actor = ""
        end
      end
    end
  end

  for _, sub in ipairs(subtitles) do
    sub._raw_block_text = nil
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

  parser.sort_subtitles(subtitles)

  return {
    ok = true,
    format = "SRT",
    subtitles = subtitles,
    actors = actors_list,
    actor_counts = actor_counts
  }
end

function parser.parse(content, filename_or_ext, opts)
  if not content or #content == 0 then
    return { ok = false, error = "Content is empty" }
  end

  local ext = ""
  if filename_or_ext then
    ext = filename_or_ext:match("%.([^%.]+)$") or filename_or_ext
    ext = ext:lower()
  end

  local res = nil
  if ext == "ass" or ext == "ssa" or content:find("%[Script Info%]") or content:find("%[Events%]") then
    res = parser.parse_ass(content, opts)
  elseif ext == "srt" or content:find("%-%->") then
    res = parser.parse_srt(content, opts)
  else
    if content:find("%[Events%]") then
      res = parser.parse_ass(content, opts)
    else
      res = parser.parse_srt(content, opts)
    end
  end
  if res and res.ok and res.subtitles then
    parser.sort_subtitles(res.subtitles)
  end
  return res
end

-- Read from disk and parse
function parser.parse_file(filepath, opts)
  local f, err = io.open(filepath, "rb")
  if not f then
    return { ok = false, error = "Cannot open file: " .. tostring(err) }
  end
  local content = f:read("*a")
  f:close()

  if not content or #content == 0 then
    return { ok = false, error = "File is empty: " .. filepath }
  end

  local res = parser.parse(content, filepath, opts)
  if res and res.ok then
    res.filepath = filepath
    res.filename = filepath:match("([^/\\]+)$") or filepath
  end
  return res
end

-- Format seconds to ASS timestamp format: H:MM:SS.cs
function parser.format_ass_time(sec)
  if not sec or sec < 0 then sec = 0 end
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  local s = math.floor(sec % 60)
  local cs = math.floor(((sec % 1) * 100) + 0.5)
  if cs >= 100 then
    cs = 0
    s = s + 1
    if s >= 60 then
      s = 0
      m = m + 1
      if m >= 60 then
        m = 0
        h = h + 1
      end
    end
  end
  return string.format("%d:%02d:%02d.%02d", h, m, s, cs)
end

-- Export subtitles array to an Advanced SubStation Alpha (.ass) file
function parser.export_to_ass(filepath, subtitles, state)
  if not filepath or not subtitles then
    return false, "Invalid filepath or subtitles"
  end

  local f, err = io.open(filepath, "wb")
  if not f then
    return false, "Cannot create file: " .. tostring(err)
  end

  local ver = (state and state.version) or "0.3.1-beta"

  -- Write UTF-8 BOM
  f:write("\xEF\xBB\xBF")

  -- Script Info with bilingual generator metadata and GitHub repository link
  local header = string.format([=[[Script Info]
; Generated by NutNotes v%s for Cockos REAPER
; GitHub: https://github.com/BelkaVBanke/NutNotes
; Сгенерировано плагином NutNotes версии %s для Cockos REAPER
; Репозиторий: https://github.com/BelkaVBanke/NutNotes
Title: NutNotes Subtitles Export
ScriptType: v4.00+
WrapStyle: 0
ScaledBorderAndShadow: yes
YCbCr Matrix: None

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,20,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,2,2,10,10,10,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
]=], ver, ver)

  f:write(header)

  for _, sub in ipairs(subtitles) do
    local start_str = parser.format_ass_time(sub.start_time)
    local end_str = parser.format_ass_time(sub.end_time)

    local raw_actor = sub.raw_actor or sub.actor or ""
    if raw_actor == "NoActor" then raw_actor = "" end

    local text = parser.strip_invisible_unicode(sub.text or "")
    -- Escape line breaks into \N
    text = text:gsub("\r\n", "\\N"):gsub("\n", "\\N"):gsub("\r", "")

    local line = string.format("Dialogue: 0,%s,%s,Default,%s,0,0,0,,%s\n",
      start_str, end_str, raw_actor, text)
    f:write(line)
  end

  f:close()
  return true
end

return parser
