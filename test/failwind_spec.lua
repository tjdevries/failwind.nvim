local failwind = require "failwind"
local failwind_hl = require "failwind.highlight"

local context = require "failwind.context"

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

    local ctx = context.new(text)
    local plugin = failwind._evaluate_plugin_spec(ctx)
    eq({ make_empty_setup "mini.trailspace" }, plugin.mini.setup)
  end)

  it("have multiple setup", function()
    local text = [[
:repo("mini") {
  setup: "mini.trailspace" "mini.ai";
}
    ]]

    local ctx = context.new(text)
    local plugin = failwind._evaluate_plugin_spec(ctx)
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

    local ctx = context.new(text)
    local plugin = failwind._evaluate_plugin_spec(ctx)
    local column_value = plugin.oil.setup[1].opts.columns
    eq({ "icon" }, column_value)
  end)

  it("have one depedency", function()
    local text = [[
:repo("oil") {
  depends: "nvim-tree/nvim-web-devicons";
} ]]

    local ctx = context.new(text)
    local plugin = failwind._evaluate_plugin_spec(ctx)
    local depends = plugin.oil.depends
    eq({ "nvim-tree/nvim-web-devicons" }, depends)
  end)

  it("have multiple depedencies", function()
    local text = [[
:repo("oil") {
    depends:
      "neovim/nvim-lspconfig"
      "williamboman/mason.nvim" 
      "williamboman/mason-lspconfig.nvim"
      "WhoIsSethDaniel/mason-tool-installer.nvim";
} ]]

    local ctx = context.new(text)
    local plugin = failwind._evaluate_plugin_spec(ctx)
    local depends = plugin.oil.depends
    eq({
      "neovim/nvim-lspconfig",
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
      "WhoIsSethDaniel/mason-tool-installer.nvim",
    }, depends)
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
      local ctx = context.new(text)
      local keymaps = failwind._evaluate_keymaps(ctx)
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
      local ctx = context.new(text)
      local keymaps = failwind._evaluate_keymaps(ctx)
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
      local ctx = context.new(text)
      local keymaps = failwind._evaluate_keymaps(ctx)
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

      local ctx = context.new(text)
      local highlights = failwind_hl.evaluate_highlight_blocks(ctx, ctx.root)
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
      local ctx = context.new(text)
      local highlights = failwind_hl.evaluate_highlight_blocks(ctx, ctx.root)
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
      local ctx = context.new(text)
      local highlights = failwind_hl.evaluate_highlight_blocks(ctx, ctx.root)
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
      local ctx = context.new(text)
      local highlights = failwind_hl.evaluate_highlight_blocks(ctx, ctx.root)
      eq({
        ["@keyword"] = { fg = "#FF0000" },
      }, highlights)
    end)
  end)
end)
