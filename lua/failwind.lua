-- This file is self documenting, btw
--
--[[

TODO: Autocommands
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.highlight.on_yank()
  end,
})

--]]

local eval = require "failwind.eval"

local get_capture_idx = require("failwind.utils").get_capture_idx
local get_text = require("failwind.utils").get_text
local read_file = require("failwind.utils").read_file

local M = {}

local options_query = vim.treesitter.query.parse(
  "css",
  [[
((rule_set
  (selectors (tag_name) @tag)
  (block
    (declaration (property_name) @option (_) @value )))
 (#eq? @tag "options")) ]]
)

local filetype_options_query = vim.treesitter.query.parse(
  "css",
  [[ ((rule_set
        (selectors (tag_name) @tag)
        (block
          (rule_set 
            (selectors (tag_name) @filetype)
            (block (declaration
                     (property_name) @name
                     (_) @value)))))
       (#eq? @tag "options"))  ]]
)

local plugin_spec_query = vim.treesitter.query.parse(
  "css",
  [[ ((rule_set
       (selectors
         (pseudo_class_selector
          (class_name) @_class
          (arguments (string_value) @plugin) @selector))
       (block) @plugin_config)
     (#eq? @_class "repo")) ]]
)

local plugin_group_query = vim.treesitter.query.parse(
  "css",
  [[ 
(stylesheet
 (rule_set
  (selectors
   (tag_name) @_plugins (#eq? @_plugins "plugins"))
  (block
   (rule_set
    (selectors (tag_name) @plugin)
    (block) @plugin_config))))
 ]]
)

local plugin_setup_query = vim.treesitter.query.parse(
  "css",
  [[ ((rule_set
       (selectors
        (pseudo_class_selector
         (class_name) @_setup
         (arguments (string_value) @module_name)))
       (block) @module_config)
     (#eq? @_setup "setup"))]]
)

local config_setup_query = vim.treesitter.query.parse(
  "css",
  [[ ((rule_set
       (selectors
        (pseudo_class_selector
         (class_name) @_config))
       (block) @module_config)
     (#eq? @_config "config"))]]
)

--- Fold declarations
---@param ctx failwind.Context
local fold_declaration = function(ctx, node, filter)
  local result = {}

  local count = node:named_child_count()
  for i = 0, count - 1 do
    local child = node:named_child(i)
    if child and child:type() == "declaration" then
      local property_name = child:named_child(0)
      if property_name then
        local property = get_text(ctx, property_name)
        if property_name:type() == "property_name" and property == filter then
          for j = 1, child:named_child_count() - 1 do
            table.insert(result, eval.css_value(ctx, assert(child:named_child(j))))
          end
        end
      end
    end
  end

  return result
end

---@class failwind.PluginSetup
---@field module string
---@field opts table

---@class failwind.PluginSpec
---@field name string
---@field setup failwind.PluginSetup[]
---@field depends string[]
---@field config function[]
---@field is_repo boolean

---@param ctx failwind.Context
---@param plugin_config_node any
---@return failwind.PluginSpec
local evaluate_plugin_setup = function(ctx, plugin_config_node)
  local setup = {}
  local default_setups = vim.tbl_map(function(str)
    return { module = str, opts = {} }
  end, fold_declaration(ctx, plugin_config_node, "setup"))
  vim.list_extend(setup, default_setups)

  local custom_setups = {}

  local module_name_idx = get_capture_idx(plugin_setup_query.captures, "module_name")
  local module_config_idx = get_capture_idx(plugin_setup_query.captures, "module_config")
  for _, plugin_setup_node in ctx:iter(plugin_setup_query, plugin_config_node) do
    local module_name = eval.css_value(ctx, plugin_setup_node[module_name_idx][1])
    local module_config = eval.block_as_table(ctx, plugin_setup_node[module_config_idx][1])
    table.insert(custom_setups, { module = module_name, opts = module_config })
  end
  vim.list_extend(setup, custom_setups)

  return setup
end

local evaluate_plugin_config_items = function(ctx, plugin_config_node)
  local setup = {}
  table.insert(setup, function()
    fold_declaration(ctx, plugin_config_node, "config")
  end)

  local custom_setups = {}
  local module_config_idx = get_capture_idx(config_setup_query.captures, "module_config")
  for _, plugin_setup_node in ctx:iter(config_setup_query, plugin_config_node) do
    local config_node = plugin_setup_node[module_config_idx][1]

    for _, child in ipairs(config_node:named_children()) do
      local f = eval.call_statement(ctx, child)
      table.insert(custom_setups, f)
    end
  end
  vim.list_extend(setup, custom_setups)

  return setup
end

---
---@param ctx failwind.Context
---@param plugin_name any
---@param plugin_config_node any
---@param is_repo boolean
---@return failwind.PluginSpec
local evaluate_plugin_config = function(ctx, plugin_name, plugin_config_node, is_repo)
  ---@type failwind.PluginSpec
  local config = {
    name = plugin_name,
    depends = fold_declaration(ctx, plugin_config_node, "depends"),
    setup = evaluate_plugin_setup(ctx, plugin_config_node),
    config = evaluate_plugin_config_items(ctx, plugin_config_node),
    is_repo = is_repo,
  }

  return config
end

local evaluate_plugin_spec = function(ctx)
  ---@type table<string, failwind.PluginSpec>
  local plugins = {}

  do -- :repo("...") {}
    local plugin = get_capture_idx(plugin_spec_query.captures, "plugin")
    local plugin_config = get_capture_idx(plugin_spec_query.captures, "plugin_config")
    for _, match in ctx:iter(plugin_spec_query) do
      local plugin_name = eval.css_value(ctx, match[plugin][1])
      local plugin_config_node = match[plugin_config][1]
      local config = evaluate_plugin_config(ctx, plugin_name, plugin_config_node, true)
      plugins[config.name] = config
    end
  end

  do -- group {}
    local plugin = get_capture_idx(plugin_group_query.captures, "plugin")
    local plugin_config = get_capture_idx(plugin_group_query.captures, "plugin_config")
    for _, match, _ in ctx:iter(plugin_group_query) do
      local plugin_name = get_text(ctx, match[plugin][1])
      local plugin_config_node = match[plugin_config][1]
      local config = evaluate_plugin_config(ctx, plugin_name, plugin_config_node, false)
      plugins[config.name] = config
    end
  end

  return plugins
end

M.evaluate = function(filename)
  local ctx = require("failwind.context").new(read_file(filename))

  while true do
    local node, import_spec = require("failwind.import").evaluate(ctx)
    if not import_spec then
      break
    end

    local content = require("failwind.import").read(import_spec)
    content = string.format("/* Imported from: %s */\n%s\n", import_spec.name, content)
    require("failwind.utils").replace_node_with_text(ctx, node, content)
  end

  -- Very helpful for debugging import problems.
  -- vim.fn.writefile(vim.split(ctx.source, "\n"), "/tmp/failwind.globals.css")

  -- Evaluate all global variables
  require("failwind.variables").globals(ctx)

  for _, match in ctx:iter(options_query) do
    local name_node = match[2][1]
    local value_node = match[3][1]
    local name = get_text(ctx, name_node)
    local value = eval.css_value(ctx, value_node)
    vim.opt[name] = value
  end

  do
    local filetype_idx = get_capture_idx(filetype_options_query.captures, "filetype")
    local name_idx = get_capture_idx(filetype_options_query.captures, "name")
    local value_idx = get_capture_idx(filetype_options_query.captures, "value")

    local ftoptions = {}
    for _, match in ctx:iter(filetype_options_query) do
      local filetype = get_text(ctx, match[filetype_idx][1])
      local name_node = match[name_idx][1]
      local value_node = match[value_idx][1]
      local name = get_text(ctx, name_node)
      local value = eval.css_value(ctx, value_node)

      if not ftoptions[filetype] then
        ftoptions[filetype] = {}
      end

      ftoptions[filetype][name] = value
    end

    vim.api.nvim_create_autocmd("FileType", {
      pattern = "*",
      callback = vim.schedule_wrap(function(ev)
        local options = ftoptions[ev.match]
        if not options then
          return
        end

        for name, value in pairs(options) do
          vim.opt_local[name] = value
        end
      end),
    })
  end

  local keymaps = require("failwind.keymaps").evaluate(ctx)
  for mode, keymap in pairs(keymaps or {}) do
    for key, settings in pairs(keymap) do
      vim.keymap.set(mode, key, settings.action, settings.opts)
    end
  end

  local deps = require "failwind.deps"
  deps.setup {}
  local plugin_spec = evaluate_plugin_spec(ctx)
  for _, plugin in pairs(plugin_spec) do
    for _, dep in pairs(plugin.depends) do
      deps.add(dep)
    end

    if plugin.is_repo then
      deps.add(plugin.name)
    end

    for _, setup in pairs(plugin.setup) do
      local ok, module = pcall(require, setup.module)
      if not ok then
        vim.notify(string.format("[failwind] failed to load: %s", setup.module))
      else
        module.setup(setup.opts)
      end
    end

    for _, config in pairs(plugin.config) do
      config()
    end
  end

  package.loaded["failwind.highlight"] = nil
  local highlights = require("failwind.highlight").evaluate_highlight_blocks(ctx)
  for name, highlight in pairs(highlights) do
    vim.api.nvim_set_hl(0, name, highlight)
  end

  local autocmds = require("failwind.autocmds").evaluate(ctx)
  for _, autocmd in ipairs(autocmds) do
    vim.api.nvim_create_autocmd(autocmd.event, autocmd.opts)
  end
end

M._evaluate_plugin_spec = evaluate_plugin_spec
M._evaluate_keymaps = require("failwind.keymaps").evaluate

return M
