local M = {}

M.get_capture_idx = function(captures, name)
  for i, capture in ipairs(captures) do
    if capture == name then
      return i
    end
  end
  error(string.format("capture not found: %s // %s", name, vim.inspect(captures)))
end

--- Get text for a node
---@param source string|number|failwind.Context
---@param node TSNode
---@return string
M.get_text = function(source, node)
  if type(source) == "table" then
    source = source.source
  end

  ---@diagnostic disable-next-line: param-type-mismatch
  local text = vim.treesitter.get_node_text(node, source)
  text = text:gsub("FAILWIND_UNICODE_OPENING_BRACE", "{")

  return text
end

M.read_file = function(filename)
  local lines = vim.fn.readfile(filename)
  return M.fix_stupid_treesitter_brace(lines)
end

--- Fix the dumb { problem in strings
---@param lines string[]|string
---@return string
M.fix_stupid_treesitter_brace = function(lines)
  if type(lines) == "string" then
    lines = vim.split(lines, "\n")
  end

  for i, line in ipairs(lines) do
    local newline = ""

    local inside_single_string = false
    local inside_double_string = false

    for idx = 1, #line do
      if inside_single_string then
        if line:sub(idx, idx) == "'" then
          inside_single_string = false
          newline = newline .. "'"
        elseif line:sub(idx, idx) == "{" then
          newline = newline .. [[FAILWIND_UNICODE_OPENING_BRACE]]
        else
          newline = newline .. line:sub(idx, idx)
        end
      elseif inside_double_string then
        if line:sub(idx, idx) == '"' then
          inside_double_string = false
          newline = newline .. '"'
        elseif line:sub(idx, idx) == "{" then
          newline = newline .. [[FAILWIND_UNICODE_OPENING_BRACE]]
        else
          newline = newline .. line:sub(idx, idx)
        end
      else
        if line:sub(idx, idx) == "'" then
          inside_single_string = true
          newline = newline .. "'"
        elseif line:sub(idx, idx) == '"' then
          inside_double_string = true
          newline = newline .. '"'
        else
          newline = newline .. line:sub(idx, idx)
        end
      end
    end

    lines[i] = newline
  end
  return table.concat(lines, "\n")
end

return M
