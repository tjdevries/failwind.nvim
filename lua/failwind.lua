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

local eval_block_as_table

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
local eval_lua_query = vim.treesitter.query.parse(
  "css",
  [[
  ((call_expression
    (function_name) @_name
    (arguments (string_value) @value))
   (#eq? @_name "lua"))
]]
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

local get_capture_idx = function(captures, name)
  for i, capture in ipairs(captures) do
    if capture == name then
      return i
    end
  end
  error(string.format("capture not found: %s // %s", name, vim.inspect(captures)))
end

local evaluate_css_value

--- Evaluate stuff RECURSIVELY
---@param parser vim.treesitter.LanguageTree
---@param source string
---@param node TSNode
evaluate_css_value = function(parser, source, node)
  local ty = node:type()
  local text = vim.treesitter.get_node_text(node, source)
  if ty == "plain_value" then
    if text == "true" then
      return true
    elseif text == "false" then
      return false
    end

    error(string.format("Unknown plain_value %s", text))
  elseif ty == "string_value" then
    return string.sub(text, 2, -2)
  elseif ty == "integer_value" then
    return tonumber(text)
  elseif ty == "property_name" then
    return text
  elseif ty == "call_expression" then
    local function_node = assert(node:child(0), "all call_expression have function_node")
    local function_name = vim.treesitter.get_node_text(function_node, source)
    if function_name == "lua" then
      local value_idx = get_capture_idx(eval_lua_query.captures, "value")
      local values = {}
      for _, call, _ in eval_lua_query:iter_matches(node, source, 0, -1, { all = true }) do
        table.insert(values, evaluate_css_value(parser, source, call[value_idx][1]))
      end

      local code = table.concat(values, "\n")
      return loadstring(code)
    else
      function_name = function_name:gsub("-", ".")
      local function_ref = loadstring("return " .. function_name)()

      local arguments = {}
      local arguments_node = assert(node:child(1), "all call_expression have arguments")
      for _, arg in ipairs(arguments_node:named_children()) do
        table.insert(arguments, evaluate_css_value(parser, source, arg))
      end

      return function_ref(unpack(arguments))
    end
  elseif ty == "grid_value" then
    local values = {}
    for _, child in ipairs(node:named_children()) do
      table.insert(values, evaluate_css_value(parser, source, child))
    end

    return values
  elseif ty == "selectors" then
    -- TODO: This seems questionable?
    return vim.treesitter.get_node_text(node, source)
  elseif ty == "postcss_statement" then
    local child = assert(node:named_child(0), "must have a child")
    local keyword = vim.treesitter.get_node_text(child, source)
    error(string.format("unknown postcss_statement: %s", keyword))

    -- if keyword == "@call" then
    --   local node_text = vim.treesitter.get_node_text(node, source)
    --   local parts = vim.split(node_text, " ")
    --   table.remove(parts, 1)
    --   node_text = table.concat(parts, " ")
    --   print("Calling:", node_text)
    --   local brace = string.find(node_text, "{", 0, true)
    --   node_text = string.sub(node_text, 1, brace + 1)
    --   print("Calling:", node_text)
    --
    --   local function_node = assert(node:named_child(1), "must have a function_name")
    --   local function_text = string.format("pcall(%s)", vim.treesitter.get_node_text(function_node, source))
    --   local function_ref = assert(loadstring(function_text, "must load function"))
    --   return function()
    --     print("Calling:", function_text, function_node, node:named_child_count(), function_node:range())
    --     return function_ref()
    --   end
    -- else
    -- end
  else
    error(string.format("Unknown css_value %s / %s", ty, source))
  end
end

---
---@param text number
---@param node TSNode
local fold_declaration = function(parser, text, node, filter)
  local result = {}

  local count = node:named_child_count()
  for i = 0, count - 1 do
    local child = node:named_child(i)
    if child and child:type() == "declaration" then
      local property_name = child:named_child(0)
      if property_name then
        local property = vim.treesitter.get_node_text(property_name, text)
        if property_name:type() == "property_name" and property == filter then
          for j = 1, child:named_child_count() - 1 do
            table.insert(result, evaluate_css_value(parser, text, assert(child:named_child(j))))
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

eval_block_as_table = function(parser, text, module_config_node)
  local result = {}

  local count = module_config_node:named_child_count()
  for i = 0, count - 1 do
    local child = assert(module_config_node:named_child(i))
    local child_type = child:type()

    if child_type == "declaration" then
      local declaration_count = child:named_child_count()
      if declaration_count == 2 then
        local property_name = evaluate_css_value(parser, text, child:named_child(0))
        local property_value = evaluate_css_value(parser, text, child:named_child(1))
        result[property_name] = property_value
      end
    elseif child_type == "rule_set" then
      local property_name = evaluate_css_value(parser, text, child:named_child(0))
      local property_value = eval_block_as_table(parser, text, child:named_child(1))
      result[property_name] = property_value
    elseif child_type == "postcss_statement" then
      local keyword = vim.treesitter.get_node_text(child:named_child(0), text)
      if keyword == "@-" then
        local child_count = child:named_child_count()
        if child_count == 3 then
          local property_name = evaluate_css_value(parser, text, child:named_child(1))
          local property_value = evaluate_css_value(parser, text, child:named_child(2))
          result[property_name] = property_value
        elseif child_count == 2 then
          local property_value = evaluate_css_value(parser, text, child:named_child(1))
          table.insert(result, property_value)
        else
          error(string.format("Unknown postcss_statement %s: %d", vim.inspect(child), child_count))
        end
      end
    end
  end

  return result
end

---@param parser any
---@param text any
---@param plugin_config_node any
---@return failwind.PluginSpec
local evaluate_plugin_setup = function(parser, text, plugin_config_node)
  local setup = {}
  local default_setups = vim.tbl_map(function(str)
    return { module = str, opts = {} }
  end, fold_declaration(parser, text, plugin_config_node, "setup"))
  vim.list_extend(setup, default_setups)

  local custom_setups = {}

  local module_name_idx = get_capture_idx(plugin_setup_query.captures, "module_name")
  local module_config_idx = get_capture_idx(plugin_setup_query.captures, "module_config")
  for _, plugin_setup_node, _ in plugin_setup_query:iter_matches(plugin_config_node, text, 0, -1, { all = true }) do
    local module_name = evaluate_css_value(parser, text, plugin_setup_node[module_name_idx][1])
    local module_config = eval_block_as_table(parser, text, plugin_setup_node[module_config_idx][1])
    table.insert(custom_setups, { module = module_name, opts = module_config })
  end
  vim.list_extend(setup, custom_setups)

  return setup
end

---
---@param parser any
---@param text any
---@param plugin_name any
---@param plugin_config_node any
---@return failwind.PluginSpec
local evaluate_plugin_config = function(parser, text, plugin_name, plugin_config_node)
  ---@type failwind.PluginSpec
  local config = {
    name = plugin_name,
    setup = evaluate_plugin_setup(parser, text, plugin_config_node),
    depends = fold_declaration(parser, text, plugin_config_node, "depends"),
    config = fold_declaration(parser, text, plugin_config_node, "config"),
  }

  return config
end

local evaluate_plugin_spec = function(parser, text, root_node)
  ---@type table<string, failwind.PluginSpec>
  local plugins = {}

  local plugin = get_capture_idx(plugin_spec_query.captures, "plugin")
  local plugin_config = get_capture_idx(plugin_spec_query.captures, "plugin_config")
  for _, match, _ in plugin_spec_query:iter_matches(root_node:root(), text, 0, -1, { all = true }) do
    local plugin_name = evaluate_css_value(parser, text, match[plugin][1])
    local plugin_config_node = match[plugin_config][1]
    local config = evaluate_plugin_config(parser, text, plugin_name, plugin_config_node)
    plugins[config.name] = config
  end

  return plugins
end

M.test = function()
  M.evaluate "/home/tjdevries/plugins/css.nvim/examples/init.css"
end

local evaluate_keymaps = function(parser, source, root_node)
  local mode_idx = get_capture_idx(keymaps_query.captures, "mode")
  local key_idx = get_capture_idx(keymaps_query.captures, "key")
  local keymap_idx = get_capture_idx(keymaps_query.captures, "keymap")

  local name_idx = get_capture_idx(keymaps_value_query.captures, "name")
  local value_idx = get_capture_idx(keymaps_value_query.captures, "value")

  local keymaps = {}
  for _, match, _ in keymaps_query:iter_matches(root_node:root(), source, 0, -1, { all = true }) do
    local mode = vim.treesitter.get_node_text(match[mode_idx][1], source)
    local key = evaluate_css_value(parser, source, match[key_idx][1])
    local keymap = match[keymap_idx][1]

    local action = nil
    local opts = {}
    for _, declaration, _ in keymaps_value_query:iter_matches(keymap, source, 0, -1, { all = true }) do
      local name = evaluate_css_value(parser, source, declaration[name_idx][1])
      local value = declaration[value_idx][1]

      if name == "action" then
        action = evaluate_css_value(parser, source, value)
      elseif name == "desc" then
        opts.desc = evaluate_css_value(parser, source, value)
      end
    end

    for _, child in ipairs(keymap:named_children()) do
      if child:type() == "postcss_statement" then
        local keyword = vim.treesitter.get_node_text(assert(child:named_child(0)), source)
        if keyword == "@call" then
          local call_node = assert(child:named_child(1), "must have call")
          local ruleset_node = assert(child:next_sibling(), "must have ruleset")
          local node_text = vim.treesitter.get_node_text(call_node, source)
            .. vim.treesitter.get_node_text(ruleset_node, source)
          local brace = string.find(node_text, "{", 0, true)
          node_text = vim.trim(string.sub(node_text, 1, brace - 1))

          -- local function_node = assert(node:named_child(1), "must have a function_name")
          local function_text = string.format("return function(...) return %s(...) end", node_text)
          local function_ref = assert(loadstring(function_text, "must load function"))()

          action = function()
            local arguments
            for _, rule_child in ipairs(ruleset_node:named_children()) do
              if rule_child:type() == "block" then
                arguments = eval_block_as_table(parser, source, rule_child)
              end
            end

            return function_ref(arguments)
          end
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
  local text = table.concat(vim.fn.readfile(filename), "\n")
  local parser = vim.treesitter.get_string_parser(text, "css")

  local root_node = parser:parse()[1]

  for _, match, _ in options_query:iter_matches(root_node:root(), text, 0, -1, { all = true }) do
    local name_node = match[2][1]
    local value_node = match[3][1]
    local name = vim.treesitter.get_node_text(name_node, text)
    local value = evaluate_css_value(parser, text, value_node)
    vim.o[name] = value
  end

  do
    local filetype_idx = get_capture_idx(filetype_options_query.captures, "filetype")
    local name_idx = get_capture_idx(filetype_options_query.captures, "name")
    local value_idx = get_capture_idx(filetype_options_query.captures, "value")

    local ftoptions = {}
    for _, match, _ in filetype_options_query:iter_matches(root_node:root(), text, 0, -1, { all = true }) do
      local filetype = vim.treesitter.get_node_text(match[filetype_idx][1], text)
      local name_node = match[name_idx][1]
      local value_node = match[value_idx][1]
      local name = vim.treesitter.get_node_text(name_node, text)
      local value = evaluate_css_value(parser, text, value_node)

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

  local keymaps = evaluate_keymaps(parser, text, root_node)
  for mode, keymap in pairs(keymaps or {}) do
    for key, settings in pairs(keymap) do
      vim.keymap.set(mode, key, settings.action, settings.opts)
    end
  end

  local deps = require "failwind.deps"
  deps.setup {}
  local plugin_spec = evaluate_plugin_spec(parser, text, root_node)
  for _, plugin in pairs(plugin_spec) do
    for _, dep in pairs(plugin.depends) do
      deps.add(dep)
    end

    deps.add(plugin.name)

    for _, setup in pairs(plugin.setup) do
      require(setup.module).setup(setup.opts)
    end

    for _, config in pairs(plugin.config) do
      config()
    end
  end
end

M._evaluate_plugin_spec = evaluate_plugin_spec
M._evaluate_keymaps = evaluate_keymaps

-- local test_plugin_manager = function()
--   local deps = require "failwind.deps"
--   deps.setup {}
--   -- deps.add "nvim-treesitter/nvim-treesitter"
--   deps.add "vim-scripts/MountainDew.vim"
-- end
-- test_plugin_manager()

-- M.test()

return M
