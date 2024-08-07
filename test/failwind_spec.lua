local failwind = require "failwind"
local failwind_hl = require "failwind.highlight"

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

    pending("should handle @call syntax", function()
      local text = [[
keymaps {
  normal {
    :key(' /') {
      @call require('mod').f {}
    }
  }
} ]]
      local parser = vim.treesitter.get_string_parser(text, "css")
      local root = parser:parse()[1]:root()
      local keymaps = failwind._evaluate_keymaps(parser, text, root)
      eq({}, keymaps)
    end)
  end)

  describe("highlights", function()
    it("should handle simple class highlights", function()
      local text = [[
highlight {
  .DiagnosticUnderlineWarn {
    border-color: pink;
  }
} ]]
      local parser = vim.treesitter.get_string_parser(text, "css")
      local root = parser:parse()[1]:root()
      local highlights = failwind_hl.evaluate_highlight_blocks(parser, text, root)
      eq({
        DiagnosticUnderlineWarn = { sp = "pink" },
      }, highlights)
    end)

    it("should handle simple tag highlights", function()
      local text = [[
highlight {
  keyword {
    color: yellow;
  }
} ]]
      local parser = vim.treesitter.get_string_parser(text, "css")
      local root = parser:parse()[1]:root()
      local highlights = failwind_hl.evaluate_highlight_blocks(parser, text, root)
      eq({
        ["@keyword"] = { fg = "yellow" },
      }, highlights)
    end)

    it("should handle nested tag highlights", function()
      local text = [[
highlight {
  keyword {
    background: blue;

    lua {
      color: yellow;
    }
  }
} ]]
      local parser = vim.treesitter.get_string_parser(text, "css")
      local root = parser:parse()[1]:root()
      local highlights = failwind_hl.evaluate_highlight_blocks(parser, text, root)
      eq({
        ["@keyword"] = { bg = "blue" },
        ["@keyword.lua"] = { fg = "yellow", bg = "blue" },
      }, highlights)
    end)

    it("should evaluate rgb(...)", function()
      local text = [[
highlight {
  keyword {
    color: rgb(255, 0, 0);
  }
} ]]
      local parser = vim.treesitter.get_string_parser(text, "css")
      local root = parser:parse()[1]:root()
      local highlights = failwind_hl.evaluate_highlight_blocks(parser, text, root)
      eq({
        ["@keyword"] = { fg = "#FF0000" },
      }, highlights)
    end)
  end)
end)
