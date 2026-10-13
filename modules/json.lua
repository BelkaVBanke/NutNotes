--[[
  Pure Lua JSON encoder and decoder
  Compatible with Lua 5.1, 5.2, 5.3, 5.4, 5.5 and LuaJIT
]]

local json = {}

local function kind_of(obj)
  if type(obj) ~= 'table' then return type(obj) end
  local i = 1
  for _ in pairs(obj) do
    if obj[i] ~= nil then
      i = i + 1
    else
      return 'table'
    end
  end
  if i == 1 then
    return 'empty_table'
  else
    return 'array'
  end
end

local function escape_str(s)
  local escape_map = {
    ['\\'] = '\\\\',
    ['"']  = '\\"',
    ['\b'] = '\\b',
    ['\f'] = '\\f',
    ['\n'] = '\\n',
    ['\r'] = '\\r',
    ['\t'] = '\\t',
  }
  return s:gsub('["\\%z\1-\31]', function(c)
    if escape_map[c] then
      return escape_map[c]
    else
      return string.format('\\u%04x', c:byte())
    end
  end)
end

function json.encode(val)
  local t = type(val)
  if t == 'nil' then
    return 'null'
  elseif t == 'boolean' then
    return val and 'true' or 'false'
  elseif t == 'number' then
    if val ~= val then return 'null' end -- NaN
    if val >= math.huge or val <= -math.huge then return 'null' end
    return tostring(val)
  elseif t == 'string' then
    return '"' .. escape_str(val) .. '"'
  elseif t == 'table' then
    local kind = kind_of(val)
    if kind == 'array' then
      local parts = {}
      for i, item in ipairs(val) do
        parts[i] = json.encode(item)
      end
      return '[' .. table.concat(parts, ',') .. ']'
    else
      local parts = {}
      for k, v in pairs(val) do
        if type(k) == 'string' or type(k) == 'number' then
          table.insert(parts, '"' .. escape_str(tostring(k)) .. '":' .. json.encode(v))
        end
      end
      return '{' .. table.concat(parts, ',') .. '}'
    end
  else
    return 'null'
  end
end

-- Decoder
local function create_decoder(str)
  local pos = 1
  local len = #str

  local function skip_whitespace()
    while pos <= len do
      local b = str:byte(pos)
      if b == 32 or b == 9 or b == 10 or b == 13 then
        pos = pos + 1
      else
        break
      end
    end
  end

  local decode_val -- forward declaration

  local function decode_str()
    pos = pos + 1 -- skip opening "
    local s_parts = {}
    while pos <= len do
      local c = str:sub(pos, pos)
      if c == '"' then
        pos = pos + 1
        return table.concat(s_parts)
      elseif c == '\\' then
        pos = pos + 1
        local esc = str:sub(pos, pos)
        pos = pos + 1
        if esc == '"' or esc == '\\' or esc == '/' then
          table.insert(s_parts, esc)
        elseif esc == 'b' then
          table.insert(s_parts, '\b')
        elseif esc == 'f' then
          table.insert(s_parts, '\f')
        elseif esc == 'n' then
          table.insert(s_parts, '\n')
        elseif esc == 'r' then
          table.insert(s_parts, '\r')
        elseif esc == 't' then
          table.insert(s_parts, '\t')
        elseif esc == 'u' then
          local hex = str:sub(pos, pos + 3)
          pos = pos + 4
          local code = tonumber(hex, 16) or 63
          -- Simple UTF-8 encoding of codepoint
          if code < 128 then
            table.insert(s_parts, string.char(code))
          elseif code < 2048 then
            table.insert(s_parts, string.char(192 + math.floor(code / 64), 128 + (code % 64)))
          else
            table.insert(s_parts, string.char(224 + math.floor(code / 4096), 128 + (math.floor(code / 64) % 64), 128 + (code % 64)))
          end
        else
          table.insert(s_parts, esc)
        end
      else
        local next_special = str:find('["\\]', pos)
        if not next_special then
          table.insert(s_parts, str:sub(pos))
          pos = len + 1
          break
        else
          table.insert(s_parts, str:sub(pos, next_special - 1))
          pos = next_special
        end
      end
    end
    return table.concat(s_parts)
  end

  local function decode_num()
    local start_p = pos
    if str:sub(pos, pos) == '-' then pos = pos + 1 end
    while pos <= len and str:sub(pos, pos):match('[0-9]') do
      pos = pos + 1
    end
    if pos <= len and str:sub(pos, pos) == '.' then
      pos = pos + 1
      while pos <= len and str:sub(pos, pos):match('[0-9]') do
        pos = pos + 1
      end
    end
    if pos <= len and (str:sub(pos, pos) == 'e' or str:sub(pos, pos) == 'E') then
      pos = pos + 1
      if str:sub(pos, pos) == '+' or str:sub(pos, pos) == '-' then pos = pos + 1 end
      while pos <= len and str:sub(pos, pos):match('[0-9]') do
        pos = pos + 1
      end
    end
    local num_str = str:sub(start_p, pos - 1)
    return tonumber(num_str)
  end

  local function decode_arr()
    pos = pos + 1 -- skip [
    local arr = {}
    skip_whitespace()
    if pos <= len and str:sub(pos, pos) == ']' then
      pos = pos + 1
      return arr
    end
    while pos <= len do
      skip_whitespace()
      local val = decode_val()
      table.insert(arr, val)
      skip_whitespace()
      local c = str:sub(pos, pos)
      if c == ']' then
        pos = pos + 1
        return arr
      elseif c == ',' then
        pos = pos + 1
      else
        break
      end
    end
    return arr
  end

  local function decode_obj()
    pos = pos + 1 -- skip {
    local obj = {}
    skip_whitespace()
    if pos <= len and str:sub(pos, pos) == '}' then
      pos = pos + 1
      return obj
    end
    while pos <= len do
      skip_whitespace()
      if str:sub(pos, pos) ~= '"' then break end
      local key = decode_str()
      skip_whitespace()
      if str:sub(pos, pos) == ':' then
        pos = pos + 1
      end
      skip_whitespace()
      local val = decode_val()
      obj[key] = val
      skip_whitespace()
      local c = str:sub(pos, pos)
      if c == '}' then
        pos = pos + 1
        return obj
      elseif c == ',' then
        pos = pos + 1
      else
        break
      end
    end
    return obj
  end

  function decode_val()
    skip_whitespace()
    if pos > len then return nil end
    local c = str:sub(pos, pos)
    if c == '"' then
      return decode_str()
    elseif c == '{' then
      return decode_obj()
    elseif c == '[' then
      return decode_arr()
    elseif c == 't' and str:sub(pos, pos + 3) == 'true' then
      pos = pos + 4
      return true
    elseif c == 'f' and str:sub(pos, pos + 4) == 'false' then
      pos = pos + 5
      return false
    elseif c == 'n' and str:sub(pos, pos + 3) == 'null' then
      pos = pos + 4
      return nil
    elseif c == '-' or c:match('[0-9]') then
      return decode_num()
    else
      pos = pos + 1
      return nil
    end
  end

  return decode_val()
end

function json.decode(str)
  if type(str) ~= 'string' or #str == 0 then return nil end
  return create_decoder(str)
end

return json
