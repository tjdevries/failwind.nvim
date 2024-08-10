local ctx = {}

---@class failwind.Context
---@field source string
---@field parser vim.treesitter.LanguageTree
---@field tree TSTree
---@field root TSNode
---@field scopes table[]

---@class failwind.Context
local FailwindContext = {}
FailwindContext.__index = FailwindContext

function FailwindContext:__tostring()
  return "<FailwindContext>"
end

function FailwindContext:update(source)
  self.source = source
  self.parser = vim.treesitter.get_string_parser(source, "css")
  self.tree = self.parser:parse()[1]
  self.root = self.tree:root()
end

--- Create iterator over all matches of a query, optionally over some sub node
---@param query vim.treesitter.Query
---@param node TSNode?
---@return function
function FailwindContext:iter(query, node)
  return query:iter_matches(node or self.root, self.source, 0, -1, { all = true })
end

--- Create a new context
---@param source string
---@return failwind.Context
ctx.new = function(source)
  local self = setmetatable({
    source = source,
    scopes = {},
  }, FailwindContext)

  self:update(source)
  return self
end

return ctx
