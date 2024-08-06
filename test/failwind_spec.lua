local failwind = require "failwind"

---@diagnostic disable-next-line: undefined-field
local eq = assert.are.same

---comment
---@param name string
---@return failwind.PluginSetup
local make_empty_setup = function(name)
  return { module = name, opts = {} }
end

describe("failwind", function()
  it("one multiple setup", function()
    local text = [[
:repo("mini") {
  setup: "mini.trailspace";
}
    ]]

    local parser = vim.treesitter.get_string_parser(text, "css")
    local root = parser:parse()[1]:root()
    local plugin = failwind._evaluate_plugin_spec(parser, text, root)
    eq({ make_empty_setup "mini.trailspace" }, plugin.mini.setup)
  end)

  it("have multiple setup", function()
    local text = [[
:repo("mini") {
  setup: "mini.trailspace" "mini.ai";
}
    ]]

    local parser = vim.treesitter.get_string_parser(text, "css")
    local root = parser:parse()[1]:root()
    local plugin = failwind._evaluate_plugin_spec(parser, text, root)
    eq({
      make_empty_setup "mini.trailspace",
      make_empty_setup "mini.ai",
    }, plugin.mini.setup)
  end)

  it("have map-type setup", function()
    local text = [[
:repo("oil") {
  depends: "nvim-tree/nvim-web-devicons";

  :setup("oil") {
    columns: ["icon"];
  }
} ]]

    local parser = vim.treesitter.get_string_parser(text, "css")
    local root = parser:parse()[1]:root()
    local plugin = failwind._evaluate_plugin_spec(parser, text, root)

    print(vim.inspect(plugin.oil))
    local column_value = plugin.oil.setup[1].opts.columns
    eq({ "icon" }, column_value)
  end)
end)
