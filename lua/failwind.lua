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

local evaluate_block_as_table

local evaluate_call_statement = function(ctx, child)
  local call_node = assert(child:named_child(1), "must have call")
  local ruleset_node = assert(child:next_sibling(), "must have ruleset")
  local node_text = get_text(ctx, call_node) .. get_text(ctx, ruleset_node)
  local brace = string.find(node_text, "{", 0, true)
  node_text = vim.trim(string.sub(node_text, 1, brace - 1))

  -- local function_node = assert(node:named_child(1), "must have a function_name")
  local function_text = string.format("return function(...) return %s(...) end", node_text)
  local function_ref = assert(loadstring(function_text, "must load function"))()

  return function()
    local arguments
    for _, rule_child in ipairs(ruleset_node:named_children()) do
      if rule_child:type() == "block" then
        arguments = evaluate_block_as_table(ctx, rule_child)
      end
    end

    return function_ref(arguments)
  end
end

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

local keymaps_query = vim.treesitter.query.parse(
  "css",
  [[
((rule_set
   (selectors
    (tag_name) @_tag)
   (block
     (rule_set
       (selectors (tag_name) @mode)
       (block
        (rule_set
         (selectors
          (pseudo_class_selector
            (class_name) @_selector
            (arguments (string_value) @key)))
         (block) @keymap

          )))))
 (#eq? @_tag "keymaps")
 (#eq? @_selector "key")) ]]
)

local keymaps_value_query = vim.treesitter.query.parse("css", [[ (declaration (property_name) @name (_) @value) ]])
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

evaluate_block_as_table = function(ctx, module_config_node)
  local result = {}

  local count = module_config_node:named_child_count()
  for i = 0, count - 1 do
    local child = assert(module_config_node:named_child(i))
    local child_type = child:type()

    if child_type == "declaration" then
      local declaration_count = child:named_child_count()
      if declaration_count == 2 then
        local property_name = eval.css_value(ctx, child:named_child(0)) --[[@as string]]
        local property_value = eval.css_value(ctx, child:named_child(1))
        result[property_name] = property_value
      else
        error "Invalid declaration"
      end
    elseif child_type == "rule_set" then
      local property_name = eval.css_value(ctx, child:named_child(0)) --[[@as string]]
      local property_value = evaluate_block_as_table(ctx, child:named_child(1))
      result[property_name] = property_value
    elseif child_type == "postcss_statement" then
      local keyword = get_text(ctx, child:named_child(0))
      if keyword == "@-" then
        local child_count = child:named_child_count()
        if child_count == 3 then
          local property_name = eval.css_value(ctx, child:named_child(1)) --[[@as string]]
          local property_value = eval.css_value(ctx, child:named_child(2))
          result[property_name] = property_value
        elseif child_count == 2 then
          local property_value = eval.css_value(ctx, child:named_child(1))
          table.insert(result, property_value)
        else
          error(string.format("Unknown postcss_statement %s: %d", vim.inspect(child), child_count))
        end
      end
    elseif child_type == "comment" then
      -- pass
    else
      error(string.format("Unknown block type %s: %s\n%s", child_type, vim.inspect(child), child:range()))
    end
  end

  return result
end

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
    local module_config = evaluate_block_as_table(ctx, plugin_setup_node[module_config_idx][1])
    table.insert(custom_setups, { module = module_name, opts = module_config })
  end
  vim.list_extend(setup, custom_setups)

  return setup
end

local evaluate_plugin_config_items = function(ctx, plugin_config_node)
  local setup = {}
  vim.list_extend(setup, fold_declaration(ctx, plugin_config_node, "config"))

  local custom_setups = {}
  local module_config_idx = get_capture_idx(config_setup_query.captures, "module_config")
  for _, plugin_setup_node in ctx:iter(config_setup_query, plugin_config_node) do
    local config_node = plugin_setup_node[module_config_idx][1]

    for _, child in ipairs(config_node:named_children()) do
      local f = evaluate_call_statement(ctx, child)
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

local evaluate_keymaps = function(ctx)
  local mode_idx = get_capture_idx(keymaps_query.captures, "mode")
  local key_idx = get_capture_idx(keymaps_query.captures, "key")
  local keymap_idx = get_capture_idx(keymaps_query.captures, "keymap")

  local name_idx = get_capture_idx(keymaps_value_query.captures, "name")
  local value_idx = get_capture_idx(keymaps_value_query.captures, "value")

  local keymaps = {}
  for _, match, _ in ctx:iter(keymaps_query) do
    local mode = get_text(ctx, match[mode_idx][1])
    local key = eval.css_value(ctx, match[key_idx][1])
    local keymap = match[keymap_idx][1]

    local action = nil
    local opts = {}
    for _, declaration in ctx:iter(keymaps_value_query, keymap) do
      local name = eval.css_value(ctx, declaration[name_idx][1])
      local value = declaration[value_idx][1]

      if name == "action" then
        action = eval.css_value(ctx, value)
      elseif name == "command" then
        local command = eval.css_value(ctx, value)
        assert(type(command) == "string", "must be string")
        action = string.format("<cmd>%s<CR>", command)
      elseif name == "desc" then
        opts.desc = eval.css_value(ctx, value)
      end
    end

    for _, child in ipairs(keymap:named_children()) do
      if child:type() == "postcss_statement" then
        local keyword = get_text(ctx, assert(child:named_child(0)))
        if keyword == "@call" then
          action = evaluate_call_statement(ctx, child)
        end
      end
    end

    if action then
      if mode == "normal" then
        mode = "n"
      elseif mode == "insert" then
        mode = "i"
      elseif mode == "terminal" then
        mode = "t"
      end

      if not keymaps[mode] then
        keymaps[mode] = {}
      end

      if key then
        keymaps[mode][key] = { action = action, opts = opts }
      end
    end
  end

  return keymaps
end

M.evaluate = function(filename)
  local text = read_file(filename)
  local ctx = require("failwind.context").new(text)

  local imports = require("failwind.import").evaluate(ctx)
  for _, import in pairs(imports) do
    local contents = require("failwind.import").read(import)
    text = contents .. "\n" .. text
  end

  vim.fn.writefile(vim.split(text, "\n"), "/tmp/failwind.globals.css")

  -- Update parser and root_node
  ctx:update(text)

  -- Evaluate all global variables
  require("failwind.variables").globals(ctx)

  for _, match in ctx:iter(options_query) do
    local name_node = match[2][1]
    local value_node = match[3][1]
    local name = get_text(text, name_node)
    local value = eval.css_value(ctx, value_node)
    vim.o[name] = value
  end

  do
    local filetype_idx = get_capture_idx(filetype_options_query.captures, "filetype")
    local name_idx = get_capture_idx(filetype_options_query.captures, "name")
    local value_idx = get_capture_idx(filetype_options_query.captures, "value")

    local ftoptions = {}
    for _, match in ctx:iter(filetype_options_query) do
      local filetype = get_text(text, match[filetype_idx][1])
      local name_node = match[name_idx][1]
      local value_node = match[value_idx][1]
      local name = get_text(text, name_node)
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

  local keymaps = evaluate_keymaps(ctx)
  for mode, keymap in pairs(keymaps or {}) do
    for key, settings in pairs(keymap) do
      vim.keymap.set(mode, key, settings.action, settings.opts)
    end
  end

  local deps = require "failwind.deps"
  deps.setup {}
  local plugin_spec = evaluate_plugin_spec(ctx)
  for _, plugin in pairs(plugin_spec) do
    print("plugin", plugin.name, vim.inspect(plugin))
    for _, dep in pairs(plugin.depends) do
      deps.add(dep)
    end

    if plugin.is_repo then
      deps.add(plugin.name)
    end

    for _, setup in pairs(plugin.setup) do
      local ok, module = pcall(require, setup.module)
      if not ok then
        print("failed to load", setup.module)
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
end

M._evaluate_plugin_spec = evaluate_plugin_spec
M._evaluate_keymaps = evaluate_keymaps

return M
