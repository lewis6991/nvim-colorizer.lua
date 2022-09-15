local matcher = require('colorizer.matcher')
local highlight = require('colorizer.highlight')

local api = vim.api

local DEFAULT_OPTIONS = {
  RGB      = true;         -- #RGB hex codes
  RRGGBB   = true;         -- #RRGGBB hex codes
  names    = true;         -- "Name" codes like Blue
  RRGGBBAA = false;        -- #RRGGBBAA hex codes
  rgb_fn   = false;        -- CSS rgb() and rgba() functions
  hsl_fn   = false;        -- CSS hsl() and hsla() functions
  css      = false;        -- Enable all CSS features: rgb_fn, hsl_fn, names, RGB, RRGGBB
  css_fn   = false;        -- Enable all CSS *functions*: rgb_fn, hsl_fn
  -- Available modes: foreground, background
  mode     = 'background'; -- Set the display mode.
}

local ns = api.nvim_create_namespace "colorizer"

local SETUP_SETTINGS = {
  exclusions = {};
  default_options = DEFAULT_OPTIONS;
}
local BUFFER_OPTIONS = {}
local FILETYPE_OPTIONS = {}

local function get_buf(buf)
  if buf == 0 or buf == nil then
    buf = api.nvim_get_current_buf()
  end
  return buf
end

--- Check if attached to a buffer.
-- @tparam[opt=0|nil] integer buf A value of 0 implies the current buffer.
-- @return true if attached to the buffer, false otherwise.
local function is_buffer_attached(buf)
  return BUFFER_OPTIONS[get_buf(buf)] ~= nil
end

local M = {}

--- Attach to a buffer and continuously highlight changes.
-- @tparam[opt=0|nil] integer buf A value of 0 implies the current buffer.
-- @param[opt] options Configuration options as described in `setup`
-- @see setup
function M.attach_to_buffer(buf, options)
  buf = get_buf(buf)
  if not options then
    options = FILETYPE_OPTIONS[vim.bo[buf].filetype] or SETUP_SETTINGS.default_options
  end
  BUFFER_OPTIONS[buf] = options
end

local function on_buf(_, buf)
  local options = BUFFER_OPTIONS[buf]
  if options then
    options._loop_parse_fn = matcher.make(options)
  end
end

local function on_win(_, _, buf)
  local options = BUFFER_OPTIONS[buf]
  if not options or not options._loop_parse_fn then
    return false
  end
end

local function on_line(_, _, buf, row)
  local options = BUFFER_OPTIONS[buf]
  local loop_parse_fn = options._loop_parse_fn
  local line = api.nvim_buf_get_lines(buf, row, row+1, true)[1]
  local i = 1
  while i < #line do
    local length, rgb_hex = loop_parse_fn(line, i)
    if length then
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

--- Stop highlighting the current buffer.
-- @tparam[opt=0|nil] integer buf A value of 0 or nil implies the current buffer.
-- @tparam[opt=NS] integer ns the namespace id.
local function detach_from_buffer(buf)
  buf = get_buf(buf)
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  BUFFER_OPTIONS[buf] = nil
end

local function colorizer_setup_hook()
  if SETUP_SETTINGS.exclusions[vim.bo.filetype] then
    return
  end
  M.attach_to_buffer()
end

--- Reload all of the currently active highlighted buffers.
local function reload_all_buffers()
  for buf, _ in pairs(BUFFER_OPTIONS) do
    M.attach_to_buffer(buf)
  end
end

--- Easy to use function if you want the full setup without fine grained control.
-- Setup an autocmd which enables colorizing for the filetypes and options specified.
--
-- By default highlights all FileTypes.
--
-- Example config:
-- ```
-- { 'scss', 'html', css = { rgb_fn = true; }, javascript = { no_names = true } }
-- ```
--
-- You can combine an array and more specific options.
-- Possible options:
-- - `no_names`: Don't highlight names like Blue
-- - `rgb_fn`: Highlight `rgb(...)` functions.
-- - `mode`: Highlight mode. Valid options: `foreground`,`background`
--
-- @param[opt={'*'}] filetypes A table/array of filetypes to selectively enable and/or customize. By default, enables all filetypes.
-- @tparam[opt] {[string]=string} default_options Default options to apply for the filetypes enable.
-- @usage require'colorizer'.setup()
function M.setup(filetypes, user_default_options)
  if not vim.o.termguicolors then
    api.nvim_err_writeln("&termguicolors must be set")
    return
  end
  FILETYPE_OPTIONS = {}
  SETUP_SETTINGS = {
    exclusions = {};
    default_options = vim.tbl_extend('force', DEFAULT_OPTIONS, user_default_options or {});
  }
  -- Initialize this AFTER setting COLOR_NAME_SETTINGS
  matcher.initialize_trie()

  local group = api.nvim_create_augroup("ColorizerSetup", {})
  if not filetypes then
    api.nvim_create_autocmd('FileType', {
      group = group,
      callback = colorizer_setup_hook
    })
  else
    for k, v in pairs(filetypes) do
      local filetype
      local options = SETUP_SETTINGS.default_options
      if type(k) == 'string' then
        filetype = k
        if type(v) ~= 'table' then
          api.nvim_err_writeln("colorizer: Invalid option type for filetype "..filetype)
        else
          options = vim.tbl_extend('force', SETUP_SETTINGS.default_options, v)
          assert(highlight.MODE_NAMES[options.mode or 'background'], "colorizer: Invalid mode: "..tostring(options.mode))
        end
      else
        filetype = v
      end
      -- Exclude
      if filetype:sub(1,1) == '!' then
        SETUP_SETTINGS.exclusions[filetype:sub(2)] = true
      else
        FILETYPE_OPTIONS[filetype] = options
        api.nvim_create_autocmd('FileType', {
          pattern = filetype,
          group = group,
          callback = colorizer_setup_hook
        })
      end
    end
  end

  api.nvim_set_decoration_provider(ns, {
    on_win = on_win,
    on_buf = on_buf,
    on_line = on_line
  })

  local function command(name, fn)
    api.nvim_create_user_command(name, function()
      fn()
    end, { force = true})
  end

  command('ColorizerAttachToBuffer', M.attach_to_buffer)
  command('ColorizerDetachFromBuffer', detach_from_buffer)
  command('ColorizerReloadAllBuffers', reload_all_buffers)
  command('ColorizerToggle', function()
    if is_buffer_attached() then
      detach_from_buffer()
    else
      M.attach_to_buffer()
    end
  end)

end

return M
