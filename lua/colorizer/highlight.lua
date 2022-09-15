local api = vim.api

local M = {}

M.MODE_NAMES = { background = "mb"; foreground = "mf"; }

--- Make a deterministic name for a highlight given these attributes
local function make_highlight_name(rgb, mode)
  return table.concat({'colorizer', M.MODE_NAMES[mode], rgb}, '_')
end

--- Determine whether to use black or white text
-- Ref: https://stackoverflow.com/a/1855903/837964
-- https://stackoverflow.com/questions/596216/formula-to-determine-brightness-of-rgb-color
local function color_is_bright(rgb_hex)
  local r = tonumber(rgb_hex:sub(1,2), 16)
  local g = tonumber(rgb_hex:sub(3,4), 16)
  local b = tonumber(rgb_hex:sub(5,6), 16)
  -- Counting the perceptive luminance - human eye favors green color
  local luminance = (0.299*r + 0.587*g + 0.114*b)/255
  return luminance > 0.5
end

local function create(rgb_hex, mode)
  if #rgb_hex == 3 then
    rgb_hex = table.concat {
      rgb_hex:sub(1,1):rep(2);
      rgb_hex:sub(2,2):rep(2);
      rgb_hex:sub(3,3):rep(2);
    }
  end
  -- Create the highlight
  local highlight_name = make_highlight_name(rgb_hex, mode)
  if mode == 'foreground' then
    api.nvim_set_hl(0, highlight_name, {fg = tonumber('0x'..rgb_hex)})
  else
    local fg_color = color_is_bright(rgb_hex) and 'Black' or 'White'
    api.nvim_set_hl(0, highlight_name, { fg = fg_color, bg = tonumber('0x'..rgb_hex)})
  end
  return highlight_name
end

local hl_cache = {}

function M.get_or_create(rgb_hex, options)
  local mode = options.mode or 'background'
  -- TODO validate rgb format?
  rgb_hex = rgb_hex:lower()
  local cache_key = table.concat({M.MODE_NAMES[mode], rgb_hex}, "_")
  local highlight_name = hl_cache[cache_key]
  -- Look up in our cache.
  if not highlight_name then
    highlight_name = create(rgb_hex, options.mode)
    hl_cache[cache_key] = highlight_name
  end
  return highlight_name
end

return M
