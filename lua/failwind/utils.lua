local M = {}

M.get_capture_idx = function(captures, name)
  for i, capture in ipairs(captures) do
    if capture == name then
      return i
    end
  end
  error(string.format("capture not found: %s // %s", name, vim.inspect(captures)))
end

M.get_text = function(node, source, opts)
  local text = vim.treesitter.get_node_text(node, source, opts)
  text = text:gsub("FAILWIND_UNICODE_OPENING_BRACE", "{")

  return text
end

return M
