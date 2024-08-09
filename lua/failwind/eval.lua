local get_text = require("failwind.utils").get_text
local get_capture_idx = require("failwind.utils").get_capture_idx

local eval_lua_query = vim.treesitter.query.parse(
  "css",
  [[ ((call_expression
      (function_name) @_name
      (arguments (string_value) @value))
     (#eq? @_name "lua")) ]]
)

local function convertPercentageStringToNumber(str)
  -- Remove any leading or trailing whitespace
  str = str:match "^%s*(.-)%s*$"

  -- Check if the string ends with a percentage sign
  local isPercentage = str:match "%%$"

  -- Remove the percentage sign if it exists
  if isPercentage then
    str = str:sub(1, -2)
  end

  -- Convert the remaining string to a number
  local number = tonumber(str)

  -- If it was a percentage, divide by 100
  if isPercentage and number then
    number = number / 100
  end

  return number
end

local css_functions
css_functions = {
  rgb = function(r, g, b)
    return string.format("#%02x%02x%02x", r, g, b):upper()
  end,

  rgba = function(r, g, b, _)
    return css_functions.rgb(r, g, b)
  end,

  -- Function to convert HSL to RGB
  hsl = function(h, s, l)
    local function hueToRgb(p, q, t)
      if t < 0 then
        t = t + 1
      end
      if t > 1 then
        t = t - 1
      end
      if t < 1 / 6 then
        return p + (q - p) * 6 * t
      end
      if t < 1 / 2 then
        return q
      end
      if t < 2 / 3 then
        return p + (q - p) * (2 / 3 - t) * 6
      end
      return p
    end

    h = h / 360
    if s > 1 then
      s = s / 100
    end

    if l > 1 then
      l = l / 100
    end

    if s == 0 then
      local r = l * 255
      return r, r, r
    end

    local q = l < 0.5 and l * (1 + s) or l + s - l * s
    local p = 2 * l - q

    local r = hueToRgb(p, q, h + 1 / 3) * 255
    local g = hueToRgb(p, q, h) * 255
    local b = hueToRgb(p, q, h - 1 / 3) * 255

    return css_functions.rgb(math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5))
  end,

  hsla = function(h, s, l, _)
    return css_functions.hsl(h, s, l)
  end,

  var = function(name, default)
    local result = require("failwind.variables").eval(name)
    if result ~= nil then
      return result
    end

    return default
  end,
}

local eval = {}

---@class failwind.eval.ValueOpts

--- Evaluate stuff RECURSIVELY
---@param parser vim.treesitter.LanguageTree
---@param source string
---@param node TSNode
eval.css_value = function(parser, source, node)
  local ty = node:type()
  local text = get_text(node, source)
  if ty == "plain_value" then
    if text == "true" then
      return true
    elseif text == "false" then
      return false
    end

    return text
  elseif ty == "string_value" then
    return string.sub(text, 2, -2)
  elseif ty == "color_value" then
    return text
  elseif ty == "integer_value" then
    return convertPercentageStringToNumber(text)
  elseif ty == "float_value" then
    return convertPercentageStringToNumber(text)
  elseif ty == "property_name" then
    return text
  elseif ty == "call_expression" then
    local function_node = assert(node:child(0), "all call_expression have function_node")
    local function_name = get_text(function_node, source)
    if function_name == "lua" then
      local value_idx = get_capture_idx(eval_lua_query.captures, "value")
      local values = {}
      for _, call, _ in eval_lua_query:iter_matches(node, source, 0, -1, { all = true }) do
        table.insert(values, eval.css_value(parser, source, call[value_idx][1]))
      end

      local code = table.concat(values, "\n")
      return loadstring(code)
    elseif function_name == "function" then
      local arguments = {}
      local arguments_node = assert(node:child(1), "all call_expression have arguments")
      for _, arg in ipairs(arguments_node:named_children()) do
        assert(arg:type() == "string_value", "all arguments must be string_values")
        table.insert(arguments, eval.css_value(parser, source, arg))
      end

      local body = table.concat(arguments, ";\n")

      local function_ref = assert(
        loadstring(string.format(
          [[ return function()
             %s
           end ]],
          body
        )),
        "must load a valid function_reference"
      )

      return function_ref
    else
      function_name = function_name:gsub("-", ".")
      local function_ref
      if css_functions[function_name] then
        function_ref = css_functions[function_name]
      else
        function_ref = loadstring("return " .. function_name)()
      end

      local arguments = {}
      local arguments_node = assert(node:child(1), "all call_expression have arguments")
      for _, arg in ipairs(arguments_node:named_children()) do
        table.insert(arguments, eval.css_value(parser, source, arg))
      end

      return function_ref(unpack(arguments))
    end
  elseif ty == "grid_value" then
    local values = {}
    for _, child in ipairs(node:named_children()) do
      table.insert(values, eval.css_value(parser, source, child))
    end

    return values
  elseif ty == "selectors" then
    -- TODO: This seems questionable?
    return get_text(node, source)
  elseif ty == "postcss_statement" then
    local child = assert(node:named_child(0), "must have a child")
    local keyword = get_text(child, source)
    error(string.format("unknown postcss_statement: %s", keyword))
  else
    error(string.format("Unknown css_value %s / %s", ty, source))
  end
end

return eval
