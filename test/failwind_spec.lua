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
    local column_value = plugin.oil.setup[1].opts.columns
    eq({ "icon" }, column_value)
  end)

  describe("keymaps", function()
    it("should handle actions", function()
      local text = [[
keymaps {
  normal {
    :key("<esc>") {
      action: "<cmd>nohlsearch<cr>";
    }
  }
} ]]
      local parser = vim.treesitter.get_string_parser(text, "css")
      local root = parser:parse()[1]:root()
      local keymaps = failwind._evaluate_keymaps(parser, text, root)
      eq({ n = { ["<esc>"] = { action = "<cmd>nohlsearch<cr>", opts = {} } } }, keymaps)
    end)

    it("should handle multiple modes", function()
      local text = [[
keymaps {
  normal, insert {
    :key("<esc>") {
      action: "<cmd>nohlsearch<cr>";
    }
  }
} ]]
      local parser = vim.treesitter.get_string_parser(text, "css")
      local root = parser:parse()[1]:root()
      local keymaps = failwind._evaluate_keymaps(parser, text, root)
      local escape_mapping = { ["<esc>"] = { action = "<cmd>nohlsearch<cr>", opts = {} } }
      eq({ n = escape_mapping, i = escape_mapping }, keymaps)
    end)

    it("should handle @call syntax", function()
      local text = [[
keymaps {
  normal {
    :key(' /') {
      @call require('mod').f
    }
  }
} ]]
      local parser = vim.treesitter.get_string_parser(text, "css")
      local root = parser:parse()[1]:root()
      local keymaps = failwind._evaluate_keymaps(parser, text, root)
      eq({}, keymaps)
    end)
  end)
end)
