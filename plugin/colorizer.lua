
local function command(name, fn)
  vim.api.nvim_create_user_command(name, function()
    fn()
  end, { force = true})
end

---@module "colorizer"
local colorizer = setmetatable({}, {
  __index = function(_, k)
    return function()
      local c = require('colorizer')
      c[k]()
    end
  end
})

command('ColorizerAttachToBuffer', colorizer.attach_to_buffer)
command('ColorizerDetachFromBuffer', colorizer.detach_from_buffer)
command('ColorizerReloadAllBuffers', colorizer.reload_all_buffers)
command('ColorizerToggle', colorizer.toggle)

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup("ColorizerSetup", {}),
  callback = colorizer.on_filetype_autocmd
})
