local get_capture_idx = require("failwind.utils").get_capture_idx
local get_text = require("failwind.utils").get_text

local eval = require "failwind.eval"

local au = {}

local autocmd_query = vim.treesitter.query.parse(
  "css",
  [[ ((rule_set
        (selectors (tag_name) @tag)
        (block
          (rule_set
            (selectors
              [(tag_name) @event
               (pseudo_class_selector
                 (tag_name) @event
                 (class_name) @func
                 (arguments) @arg)
               (descendant_selector
                 (tag_name) @event
                 (pseudo_class_selector
                   (class_name) @func
                    (arguments) @arg))])
            (block) @block)))
       (#eq? @tag "autocmds")) ]]
)

--- Evaluate the autocmds in the given context.
---@param ctx failwind.Context
au.evaluate = function(ctx)
  local event_idx = get_capture_idx(autocmd_query.captures, "event")
  local func_idx = get_capture_idx(autocmd_query.captures, "func")
  local arg_idx = get_capture_idx(autocmd_query.captures, "arg")
  local block_idx = get_capture_idx(autocmd_query.captures, "block")

  local result = {}
  for _, match in ctx:iter(autocmd_query) do
    local event = get_text(ctx, match[event_idx][1])
    local block_node = match[block_idx][1]

    local func_node = match[func_idx]
    if func_node then
      local arguments = match[arg_idx][1] ---[[@as TSNode]]
      local pattern = {}
      for _, arg in ipairs(arguments:named_children()) do
        table.insert(pattern, eval.css_value(ctx, arg))
      end

      local opts = eval.block_as_table(ctx, block_node)
      opts.pattern = pattern
      table.insert(result, { event = event, opts = opts })
    else
      local opts = eval.block_as_table(ctx, block_node)
      table.insert(result, { event = event, opts = opts })
    end
  end

  return result
end

return au
