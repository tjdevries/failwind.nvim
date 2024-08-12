local eval = require "failwind.eval"

local get_text = require("failwind.utils").get_text
local get_capture_idx = require("failwind.utils").get_capture_idx

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
         (block) @keymap)))))
 (#eq? @_tag "keymaps")
 (#eq? @_selector "key")) ]]
)

local keymaps_value_query = vim.treesitter.query.parse("css", [[ (declaration (property_name) @name (_) @value) ]])

local M = {}

M.evaluate = function(ctx)
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
          action = eval.call_statement(ctx, child)
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

return M
