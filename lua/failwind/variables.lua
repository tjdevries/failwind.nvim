local get_capture_idx = require("failwind.utils").get_capture_idx
local get_text = require("failwind.utils").get_text

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

vars.globals = function(parser, source, root)
  print "... starting globals ..."
  -- print(vim.inspect(root_query), source)
  vim.fn.writefile(vim.split(source, "\n"), "/tmp/failwind.globals.css")
  local name_idx = get_capture_idx(root_query.captures, "name")
  local value_idx = get_capture_idx(root_query.captures, "value")
  for _, match, _ in root_query:iter_matches(root, source, 0, -1, { all = true }) do
    local name = get_text(match[name_idx][1], source)
    local value = get_text(match[value_idx][1], source)
    print("globals", name, value)
  end
  print "... globals done ..."
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
