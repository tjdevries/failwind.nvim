local deps = require "failwind.deps"
deps.setup {}

local init_css = vim.fs.joinpath(vim.fn.stdpath "config", "init.css")
if vim.uv.fs_stat(init_css) then
  require("failwind").evaluate(init_css)
end
