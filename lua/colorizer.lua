local matcher = require('colorizer.matcher')
local highlight = require('colorizer.highlight')

local api = vim.api

--- @class colorizer.Options
--- @field RGB      boolean  -- #RGB hex codes
--- @field RRGGBB   boolean  -- #RRGGBB hex codes
--- @field RRGGBBAA boolean  -- #RRGGBBAA hex codes
--- @field names    boolean  -- "Name" codes like Blue
--- @field rgb_fn   boolean  -- CSS rgb() and rgba() functions
--- @field hsl_fn   boolean  -- CSS hsl() and hsla() functions
--- @field css      boolean  -- Enable all CSS features: rgb_fn, hsl_fn, names, RGB, RRGGBB
--- @field css_fn   boolean  -- Enable all CSS *functions*: rgb_fn, hsl_fn
--- @field mode 'background' | 'foreground' Display mode
--- @field _loop_parse_fn colorizer.Matcher
local DEFAULT_OPTIONS = {
  RGB      = true,
  RRGGBB   = true,
  names    = true,
  RRGGBBAA = false,
  rgb_fn   = false,
  hsl_fn   = false,
  css      = false,
  css_fn   = false,
  mode     = 'background',
}

local ns = api.nvim_create_namespace "colorizer"

---@class colorizer.Settings
---@field exclusions table<string,boolean>
---@field default_options colorizer.Options
local settings = {
  exclusions = {},
  default_options = DEFAULT_OPTIONS,
}

---@type table<integer,colorizer.Options>
local buf_options = {}

---@type table<string,table>
local ft_options = {}

local function get_buf(buf)
  if buf == 0 or buf == nil then
    buf = api.nvim_get_current_buf()
  end
  return buf
end

local function is_buffer_attached(buf)
  return buf_options[get_buf(buf)] ~= nil
end

local function on_win(_, _, buf)
  local options = buf_options[buf]
  if not options or not options._loop_parse_fn then
    return false
  end
end

local function on_line(_, _, buf, row)
  local options = buf_options[buf]
  local loop_parse_fn = options._loop_parse_fn
  local line = api.nvim_buf_get_lines(buf, row, row+1, true)[1]
  local i = 1
  while i < #line do
    local length, rgb_hex = loop_parse_fn(line, i)
    if length then
      assert(rgb_hex)
      api.nvim_buf_set_extmark(buf, ns, row, i - 1, {
        end_col = i + length - 1,
        hl_group = highlight.get_or_create(rgb_hex, options),
        ephemeral = true
      })
      i = i + length
    else
      i = i + 1
    end
  end
end

local done_init = false

local function init()
  if done_init then
    return
  end
  done_init = true

  -- Initialize this AFTER setting COLOR_NAME_SETTINGS
  matcher.initialize_trie()

  api.nvim_set_decoration_provider(ns, {
    on_win = on_win,
    on_line = on_line
  })
end

local M = {}

--- Attach to a buffer and continuously highlight changes.
function M.attach_to_buffer(buf, options)
  init()
  buf = get_buf(buf)
  if not options then
    options = ft_options[vim.bo[buf].filetype] or settings.default_options
  end
  options = vim.tbl_extend('keep', options, DEFAULT_OPTIONS)
  options._loop_parse_fn = matcher.make(options)
  buf_options[buf] = options
end

--- Stop highlighting the current buffer.
function M.detach_from_buffer(buf)
  init()
  buf = get_buf(buf)
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  buf_options[buf] = nil
end

function M.toggle()
  init()
  if is_buffer_attached() then
    M.detach_from_buffer()
  else
    M.attach_to_buffer()
  end
end

function M.on_filetype_autocmd()
  init()
  if settings.exclusions[vim.bo.filetype] then
    return
  end
  M.attach_to_buffer()
end

--- Reload all of the currently active highlighted buffers.
function M.reload_all_buffers()
  init()
  for buf, _ in pairs(buf_options) do
    M.attach_to_buffer(buf)
  end
end

---@class colorizer.FileTypeOpts
---@field [integer] string
---@field [string] colorizer.FileTypeOpt

---@class colorizer.FileTypeOpt
---@field mode 'foreground' | 'background'

--- @param filetypes colorizer.FileTypeOpts
local function setup_autocmds(filetypes)
  local group = api.nvim_create_augroup("ColorizerSetup", {})

  if not filetypes then
    api.nvim_create_autocmd('FileType', {
      group = group,
      callback = M.on_filetype_autocmd
    })
    return
  end

  for k, v in pairs(filetypes --[[@as table<any,any>]]) do
    local filetype ---@type string
    local options = settings.default_options
    if type(k) == 'string' then
      filetype = k
      if type(v) ~= 'table' then
        api.nvim_err_writeln("colorizer: Invalid option type for filetype "..filetype)
      else
        options = vim.tbl_extend('force', settings.default_options, v)
        assert(highlight.MODE_NAMES[options.mode or 'background'], "colorizer: Invalid mode: "..tostring(options.mode))
      end
    else
      filetype = v --[[@as string]]
    end

    -- Exclude
    if filetype:sub(1,1) == '!' then
      settings.exclusions[filetype:sub(2)] = true
    else
      ft_options[filetype] = options
      api.nvim_create_autocmd('FileType', {
        pattern = filetype,
        group = group,
        callback = M.on_filetype_autocmd
      })
    end
  end
end

--- Easy to use function if you want the full setup without fine grained control.
---Setup an autocmd which enables colorizing for the filetypes and options specified.
---
---By default highlights all FileTypes.
---
---Example config:
---```
---{ 'scss', 'html', css = { rgb_fn = true; } }
---```
---
---You can combine an array and more specific options.
---Possible options:
--- - `rgb_fn`: Highlight `rgb(...)` functions.
--- - `mode`: Highlight mode. Valid options: `foreground`,`background`
---
---@param filetypes colorizer.FileTypeOpts Filetypes to selectively enable and/or customize. By default, enables all filetypes.
---@param user_default_options colorizer.Options Default options to apply for the filetypes enable.
function M.setup(filetypes, user_default_options)
  init()

  if not vim.o.termguicolors then
    api.nvim_err_writeln("&termguicolors must be set")
    return
  end

  ft_options = {}
  settings.default_options = vim.tbl_extend('force', DEFAULT_OPTIONS, user_default_options or {});

  setup_autocmds(filetypes)
end

return M
