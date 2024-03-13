local ffi = require('ffi')
local Trie = require('colorizer.trie')

local api = vim.api
local band, lshift, bor, tohex = bit.band, bit.lshift, bit.bor, bit.tohex
local rshift = bit.rshift
local floor, min, max = math.floor, math.min, math.max

local M = {}

local color_map ---@type table<string,string>
local color_trie ---@type colorizer.Trie
local color_minlen ---@type integer
local COLOR_NAME_SETTINGS = {
  lowercase = false,
  strip_digits = false,
}

--- Setup the COLOR_MAP and COLOR_TRIE
function M.initialize_trie()
  if color_trie then
    return
  end

  color_map = {}
  color_trie = Trie()
  for k, v in pairs(api.nvim_get_color_map()) do
    if not (COLOR_NAME_SETTINGS.strip_digits and k:match('%d+$')) then
      color_minlen = color_minlen and min(#k, color_minlen) or #k
      local rgb_hex = tohex(v, 6) --[[@as string]]
      color_map[k] = rgb_hex
      color_trie:insert(k)
      if COLOR_NAME_SETTINGS.lowercase then
        local lowercase = k:lower()
        color_map[lowercase] = rgb_hex
        color_trie:insert(lowercase)
      end
    end
  end
end

-- -- TODO use rgb as the return value from the matcher functions
-- -- instead of the rgb_hex. Can be the highlight key as well
-- -- when you shift it left 8 bits. Use the lower 8 bits for
-- -- indicating which highlight mode to use.
-- ffi.cdef [[
-- typedef struct { uint8_t r, g, b; } colorizer_rgb;
-- ]]
-- local rgb_t = ffi.typeof 'colorizer_rgb'

-- Create a lookup table where the bottom 4 bits are used to indicate the
-- category and the top 4 bits are the hex value of the ASCII byte.
local BYTE_CATEGORY = ffi.new('uint8_t[256]') ---@type table<integer,integer>
local CATEGORY_DIGIT = lshift(1, 0)
local CATEGORY_ALPHA = lshift(1, 1)
local CATEGORY_HEX = lshift(1, 2)
local CATEGORY_ALPHANUM = bor(CATEGORY_ALPHA, CATEGORY_DIGIT)
do
  local byte = string.byte
  for i = 0, 255 do
    local v = 0
    -- Digit is bit 1
    if i >= byte('0') and i <= byte('9') then
      v = bor(v, lshift(1, 0))
      v = bor(v, lshift(1, 2))
      v = bor(v, lshift(i - byte('0'), 4))
    end
    local lowercase = bor(i, 0x20)
    -- Alpha is bit 2
    if lowercase >= byte('a') and lowercase <= byte('z') then
      v = bor(v, lshift(1, 1))
      if lowercase <= byte('f') then
        v = bor(v, lshift(1, 2))
        v = bor(v, lshift(lowercase - byte('a') + 10, 4))
      end
    end
    BYTE_CATEGORY[i] = v
  end
end

local function byte_is_hex(byte)
  return band(BYTE_CATEGORY[byte], CATEGORY_HEX) ~= 0
end

local function byte_is_alphanumeric(byte)
  local category = BYTE_CATEGORY[byte]
  return band(category, CATEGORY_ALPHANUM) ~= 0
end

local function parse_hex(b)
  return rshift(BYTE_CATEGORY[b], 4)
end

--- @param line string
--- @param i integer
--- @return integer?, string?
local function color_name_parser(line, i)
  if i > 1 and byte_is_alphanumeric(line:byte(i - 1)) then
    return
  end
  if #line < i + color_minlen - 1 then
    return
  end
  local prefix = color_trie:longest_prefix(line, i)
  if prefix then
    -- Check if there is a letter here so as to disallow matching here.
    -- Take the Blue out of Blueberry
    -- Line end or non-letter.
    local next_byte_index = i + #prefix
    if #line >= next_byte_index and byte_is_alphanumeric(line:byte(next_byte_index)) then
      return
    end
    return #prefix, color_map[prefix]
  end
end

local b_hash = ('#'):byte()

--- @param line string
--- @param i integer
--- @param minlen integer
--- @param maxlen integer
--- @return integer?, string?
local function rgb_hex_parser(line, i, minlen, maxlen)
  if i > 1 and byte_is_alphanumeric(line:byte(i - 1)) then
    return
  end

  if line:byte(i) ~= b_hash then
    return
  end

  local j = i + 1

  if #line < j + minlen - 1 then
    return
  end

  local n = j + maxlen
  local alpha --- @type number
  local v = 0
  while j <= min(n, #line) do
    local b = line:byte(j)

    if not byte_is_hex(b) then
      break
    end

    if j - i >= 7 then
      alpha = parse_hex(b) + lshift(alpha or 0, 4)
    else
      v = parse_hex(b) + lshift(v, 4)
    end

    j = j + 1
  end

  if #line >= j and byte_is_alphanumeric(line:byte(j)) then
    return
  end

  local length = j - i
  if length ~= 4 and length ~= 7 and length ~= 9 then
    return
  end

  if alpha then
    alpha = tonumber(alpha) / 255
    local r = floor(band(v, 0xFF) * alpha)
    local g = floor(band(rshift(v, 8), 0xFF) * alpha)
    local b = floor(band(rshift(v, 16), 0xFF) * alpha)
    v = bor(lshift(r, 16), lshift(g, 8), b)
    return 9, tohex(v, 6) --[[@as string]]
  end
  return length, line:sub(i + 1, i + length - 1)
end

local css_fn = require('colorizer.css')

local CSS_FUNCTION_TRIE = Trie({ 'rgb', 'rgba', 'hsl', 'hsla' })

--- @param line string
--- @param i integer
--- @return integer?, integer?
local function css_function_parser(line, i)
  local prefix = CSS_FUNCTION_TRIE:longest_prefix(line:sub(i))
  if prefix then
    return css_fn[prefix](line, i)
  end
end

local RGB_FUNCTION_TRIE = Trie({ 'rgb', 'rgba' })

local function rgb_function_parser(line, i)
  local prefix = RGB_FUNCTION_TRIE:longest_prefix(line:sub(i))
  if prefix then
    return css_fn[prefix](line, i)
  end
end

local HSL_FUNCTION_TRIE = Trie({ 'hsl', 'hsla' })

--- @param line string
--- @param i integer
--- @return integer?, integer?
local function hsl_function_parser(line, i)
  local prefix = HSL_FUNCTION_TRIE:longest_prefix(line:sub(i))
  if prefix then
    return css_fn[prefix](line, i)
  end
end

--- @alias colorizer.Matcher fun(line: string, i: integer): integer?, string?

---@param matchers colorizer.Matcher[]
---@return colorizer.Matcher
local function compile_matcher(matchers)
  local parse_fn = matchers[1]
  for j = 2, #matchers do
    local old_parse_fn = parse_fn
    local new_parse_fn = matchers[j]
    parse_fn = function(line, i)
      local length, rgb_hex = new_parse_fn(line, i)
      if length then
        return length, rgb_hex
      end
      return old_parse_fn(line, i)
    end
  end
  return parse_fn
end

local matcher_cache = {} --- @type table<integer,colorizer.Matcher>

--- @param options colorizer.Options
--- @return colorizer.Matcher?
function M.make(options)
  local enable_names = options.css or options.names
  local enable_RGB = options.css or options.RGB
  local enable_RRGGBB = options.css or options.RRGGBB
  local enable_RRGGBBAA = options.css or options.RRGGBBAA
  local enable_rgb = options.css or options.css_fn or options.rgb_fn
  local enable_hsl = options.css or options.css_fn or options.hsl_fn

  local matcher_key = bor(
    lshift(enable_names and 1 or 0, 0),
    lshift(enable_RGB and 1 or 0, 1),
    lshift(enable_RRGGBB and 1 or 0, 2),
    lshift(enable_RRGGBBAA and 1 or 0, 3),
    lshift(enable_rgb and 1 or 0, 4),
    lshift(enable_hsl and 1 or 0, 5)
  )

  if matcher_key == 0 then
    return
  end

  if not matcher_cache[matcher_key] then
    local loop_matchers = {} --- @type colorizer.Matcher[]
    if enable_names then
      loop_matchers[#loop_matchers + 1] = color_name_parser
    end

    local valid_lengths = { [3] = enable_RGB, [6] = enable_RRGGBB, [8] = enable_RRGGBBAA }
    local minlen, maxlen --- @type integer, integer
    for k, v in pairs(valid_lengths) do
      if v then
        minlen = minlen and min(k, minlen) or k
        maxlen = maxlen and max(k, maxlen) or k
      end
    end
    if minlen then
      loop_matchers[#loop_matchers + 1] = function(line, i)
        local length, rgb_hex = rgb_hex_parser(line, i, minlen, maxlen)
        if length and valid_lengths[length - 1] then
          return length, rgb_hex
        end
      end
    end

    if enable_rgb and enable_hsl then
      loop_matchers[#loop_matchers + 1] = css_function_parser
    elseif enable_rgb then
      loop_matchers[#loop_matchers + 1] = rgb_function_parser
    elseif enable_hsl then
      loop_matchers[#loop_matchers + 1] = hsl_function_parser
    end
    matcher_cache[matcher_key] = compile_matcher(loop_matchers)
  end

  return matcher_cache[matcher_key]
end

return M
