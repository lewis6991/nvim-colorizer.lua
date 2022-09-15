local lshift, bor, tohex = bit.lshift, bit.bor, bit.tohex
local floor = math.floor

local function percent_or_hex(v)
  if v:sub(-1,-1) == "%" then
    return tonumber(v:sub(1,-2))/100*255
  end
  local x = tonumber(v)
  if x > 255 then return end
  return x
end

-- https://gist.github.com/mjackson/5311256
local function hue_to_rgb(p, q, t)
  if t < 0 then t = t + 1 end
  if t > 1 then t = t - 1 end
  if t < 1/6 then return p + (q - p) * 6 * t end
  if t < 1/2 then return q end
  if t < 2/3 then return p + (q - p) * (2/3 - t) * 6 end
  return p
end

local function hsl_to_rgb(h, s, l)
  if h > 1 or s > 1 or l > 1 then return end
  if s == 0 then
    local r = l * 255
    return r, r, r
  end
  local q
  if l < 0.5 then
    q = l * (1 + s)
  else
    q = l + s - l * s
  end
  local p = 2 * l - q
  return 255*hue_to_rgb(p, q, h + 1/3), 255*hue_to_rgb(p, q, h), 255*hue_to_rgb(p, q, h - 1/3)
end

-- TODO consider removing the regexes here
-- TODO this might not be the best approach to alpha channel.
-- Things like pumblend might be useful here.
local M = {}
local CSS_RGB_FN_MINIMUM_LENGTH = #'rgb(0,0,0)' - 1
local CSS_RGBA_FN_MINIMUM_LENGTH = #'rgba(0,0,0,0)' - 1
local CSS_HSL_FN_MINIMUM_LENGTH = #'hsl(0,0%,0%)' - 1
local CSS_HSLA_FN_MINIMUM_LENGTH = #'hsla(0,0%,0%,0)' - 1
function M.rgb(line, i)
  if #line < i + CSS_RGB_FN_MINIMUM_LENGTH then return end
  local r, g, b, match_end = line:sub(i):match("^rgb%(%s*(%d+%%?)%s*,%s*(%d+%%?)%s*,%s*(%d+%%?)%s*%)()")
  if not match_end then return end
  r = percent_or_hex(r) if not r then return end
  g = percent_or_hex(g) if not g then return end
  b = percent_or_hex(b) if not b then return end
  local rgb_hex = tohex(bor(lshift(r, 16), lshift(g, 8), b), 6)
  return match_end - 1, rgb_hex
end

function M.hsl(line, i)
  if #line < i + CSS_HSL_FN_MINIMUM_LENGTH then return end
  local h, s, l, match_end = line:sub(i):match("^hsl%(%s*(%d+)%s*,%s*(%d+)%%%s*,%s*(%d+)%%%s*%)()")
  if not match_end then return end
  h = tonumber(h) if h > 360 then return end
  s = tonumber(s) if s > 100 then return end
  l = tonumber(l) if l > 100 then return end
  local r, g, b = hsl_to_rgb(h/360, s/100, l/100)
  if r == nil or g == nil or b == nil then return end
  local rgb_hex = tohex(bor(lshift(floor(r), 16), lshift(floor(g), 8), floor(b)), 6)
  return match_end - 1, rgb_hex
end

function M.rgba(line, i)
  if #line < i + CSS_RGBA_FN_MINIMUM_LENGTH then return end
  local r, g, b, a, match_end = line:sub(i):match("^rgba%(%s*(%d+%%?)%s*,%s*(%d+%%?)%s*,%s*(%d+%%?)%s*,%s*([.%d]+)%s*%)()")
  if not match_end then return end
  a = tonumber(a) if not a or a > 1 then return end
  r = percent_or_hex(r) if not r then return end
  g = percent_or_hex(g) if not g then return end
  b = percent_or_hex(b) if not b then return end
  local rgb_hex = tohex(bor(lshift(floor(r*a), 16), lshift(floor(g*a), 8), floor(b*a)), 6)
  return match_end - 1, rgb_hex
end

function M.hsla(line, i)
  if #line < i + CSS_HSLA_FN_MINIMUM_LENGTH then return end
  local h, s, l, a, match_end = line:sub(i):match("^hsla%(%s*(%d+)%s*,%s*(%d+)%%%s*,%s*(%d+)%%%s*,%s*([.%d]+)%s*%)()")
  if not match_end then return end
  a = tonumber(a) if not a or a > 1 then return end
  h = tonumber(h) if h > 360 then return end
  s = tonumber(s) if s > 100 then return end
  l = tonumber(l) if l > 100 then return end
  local r, g, b = hsl_to_rgb(h/360, s/100, l/100)
  if r == nil or g == nil or b == nil then return end
  local rgb_hex = tohex(bor(lshift(floor(r*a), 16), lshift(floor(g*a), 8), floor(b*a)), 6)
  return match_end - 1, rgb_hex
end

return M
