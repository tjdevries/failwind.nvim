local get_capture_idx = require("failwind.utils").get_capture_idx
local get_text = require("failwind.utils").get_text

local eval = require "failwind.eval"

local vars = {}

local root_query = vim.treesitter.query.parse(
  "css",
  [[
((stylesheet
  (rule_set
   (selectors (pseudo_class_selector (class_name) @class))
   (block
    (declaration
      (property_name) @name
      (_) @value))))
 (#match? @class "root")
 (#vim-match? @name "^--")) ]]
)

--- Evaluate a variable
---@param ctx failwind.Context
---@param name string
---@return any
vars.eval = function(ctx, name)
  -- TODO: Handle nested scopes
  return ctx.scopes[1][name]
end

--- Update context with the root variables
---@param ctx failwind.Context
vars.globals = function(ctx)
  local root = {}

  local name_idx = get_capture_idx(root_query.captures, "name")
  local value_idx = get_capture_idx(root_query.captures, "value")
  for _, match, _ in ctx:iter(root_query) do
    local name = get_text(ctx.source, match[name_idx][1])
    local value = eval.css_value(ctx, match[value_idx][1])
    root[name] = value
  end

  table.insert(ctx.scopes, root)
end

--[[
; match against :root and variables inside of root
((stylesheet
   (rule_set
    (selectors (pseudo_class_selector (class_name) @class))
    (block
     (declaration
       (property_name) @name))))
 (#match? @class "root")
 (#match? @name "^--"))

The harder question is how to keep track of state
as we are progresing through variables other blocks.

Probably need some env table, default look ups, etc
Then we can eval against it and add children to the list. etc.

Then we just thread that through all the evaluation stuff.

Other alternative is a run of pre-processing, where we find all the `var` calls and
then just put them directly into the string.

  Probably OK to just add a `var` handler though for css functions in eval.
--]]

return vars
