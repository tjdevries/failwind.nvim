local get_capture_idx = require("failwind.utils").get_capture_idx
local get_text = require("failwind.utils").get_text

local eval = require "failwind.eval"

local highlight = {}

local highlight_block_query = vim.treesitter.query.parse(
  "css",
  [[ ((rule_set
       (selectors (tag_name) @tag)
       (block) @block)
     (#eq? @tag "highlight")) ]]
)

local class_selector_query = vim.treesitter.query.parse(
  "css",
  [[ (block
      (rule_set
       (selectors
        (class_selector (class_name) @name))
       (block) @configuration)) ]]
)

local tag_selector_query = vim.treesitter.query.parse(
  "css",
  [[ (block
      (rule_set
       (selectors (tag_name) @name)
       (block) @configuration) @ruleset) @block ]]
)

local evaluate_configuration_node = function(parser, source, node)
  -- TODO: The rest of these fields
  -- link: (No direct equivalent, would use CSS classes for grouping styles)
  --
  -- blend: (No direct equivalent, usually related to transparency or blending modes)
  -- standout: (No direct equivalent, context-specific styling needed)
  -- reverse: (No direct equivalent, could be context-specific like filter: invert(1))
  -- nocombine: (No direct equivalent, might require custom CSS)
  -- default: (No direct equivalent, use CSS specificity and inheritance rules)
  -- ctermfg: (No direct equivalent in CSS, term-specific)
  -- ctermbg: (No direct equivalent in CSS, term-specific)
  -- cterm: (No direct equivalent in CSS, term-specific)
  -- force: (No direct equivalent in CSS, handled by CSS specificity)
  local config = {}

  local property_to_nvim = {
    ["color"] = "fg",
    ["background"] = "bg",
    ["background-color"] = "bg",
    ["border-color"] = "sp",
    ["font-weight"] = function(child)
      local value = eval.css_value(parser, source, assert(child:named_child(1)), { plain_value_as_string = true })
      if value == "bold" then
        return "bold", true
      else
        return "bold", false
      end
    end,
    ["font-style"] = function(child)
      local value = eval.css_value(parser, source, assert(child:named_child(1)), { plain_value_as_string = true })
      if value == "italic" then
        return "italic", true
      else
        return "italic", false
      end
    end,

    -- underline: text-decoration: underline
    -- undercurl: (No direct equivalent, custom text-decoration needed)
    -- underdouble: text-decoration: underline double
    -- underdotted: text-decoration: underline dotted
    -- underdashed: text-decoration: underline dashed
    -- strikethrough: text-decoration: line-through
    ["text-decoration"] = function(child)
      local values = {}
      for idx = 1, child:named_child_count() - 1 do
        local value_node = assert(child:named_child(idx), "must have value")
        table.insert(values, eval.css_value(parser, source, value_node, { plain_value_as_string = true }))
      end

      if #values == 2 then
        if values[2] == "underline" then
          local one, two = unpack(values)
          values[1] = two
          values[2] = one
        end
      end

      if values[1] == "underline" then
        if #values == 1 then
          return "underline", true
        elseif values[2] == "double" then
          return "underdouble", true
        elseif values[2] == "dotted" then
          return "underdotted", true
        elseif values[2] == "dashed" then
          return "underdashed", true
        end
      elseif values[1] == "undercurl" then
        return "undercurl", true
      elseif values[1] == "strikethrough" then
        return "strikethrough", true
      else
        error(string.format("Unknown text-decoration %s", table.concat(values, " ")))
      end
    end,
  }

  for _, child in ipairs(node:named_children()) do
    local ty = child:type()
    if ty == "comment" then
      -- pass
    elseif ty == "declaration" then
      local property_name = assert(child:named_child(0), "all declaration have property_name")
      local property = get_text(property_name, source)

      local transform = property_to_nvim[property]
      if type(transform) == "function" then
        local name, value = transform(child)
        config[name] = value
      elseif type(transform) == "string" then
        local value = eval.css_value(parser, source, assert(child:named_child(1)), { plain_value_as_string = true })
        config[transform] = value
      elseif transform == nil then
      else
        error "unknown property"
      end
    end
  end

  if vim.tbl_isempty(config) then
    return nil
  end

  return config
end

local process_class_selectors = function(parser, source, root, result)
  local name_idx = get_capture_idx(class_selector_query.captures, "name")
  local configuration_idx = get_capture_idx(class_selector_query.captures, "configuration")

  for _, match, _ in class_selector_query:iter_matches(root, source, 0, -1, { all = true }) do
    local name = get_text(match[name_idx][1], source)
    local configuration_node = match[configuration_idx][1]
    result[name] = evaluate_configuration_node(parser, source, configuration_node)
  end
end

local process_tag_selectors = function(parser, source, root, result)
  local configuration_idx = get_capture_idx(tag_selector_query.captures, "configuration")
  local block_idx = get_capture_idx(tag_selector_query.captures, "block")
  local ruleset_idx = get_capture_idx(tag_selector_query.captures, "ruleset")

  for _, match, _ in tag_selector_query:iter_matches(root, source, 0, -1, { all = true }) do
    -- Get the parent tags

    ---@type TSNode[]
    local config_nodes = {}
    local block = match[block_idx][1]
    while block do
      local prev_sibling = block:prev_named_sibling()
      if prev_sibling and prev_sibling:type() == "selectors" then
        table.insert(config_nodes, 1, block:parent())
      end

      ---@diagnostic disable-next-line: cast-local-type
      block = block:parent()
    end

    -- Remove the highlight table
    table.remove(config_nodes, 1)

    -- Add the matched node
    table.insert(config_nodes, match[ruleset_idx][1])

    local cascaded = {}
    local names = {}
    for _, n in ipairs(config_nodes) do
      table.insert(names, get_text(n:named_child(0), source))
      local configuration_node = n:named_child(1)

      for k, v in pairs(evaluate_configuration_node(parser, source, configuration_node) or {}) do
        cascaded[k] = v
      end
    end

    result["@" .. table.concat(names, ".")] = cascaded
  end
end

highlight.evaluate_highlight_blocks = function(parser, source, root)
  local result = {}

  local block_idx = get_capture_idx(highlight_block_query.captures, "block")

  for _, highlight_match, _ in highlight_block_query:iter_matches(root, source, 0, -1, { all = true }) do
    local block_node = highlight_match[block_idx][1]
    process_class_selectors(parser, source, block_node, result)
    process_tag_selectors(parser, source, block_node, result)
  end

  return result
end

return highlight
