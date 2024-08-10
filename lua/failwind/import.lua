local eval = require "failwind.eval"

local util = require "failwind.utils"
local get_capture_idx = require("failwind.utils").get_capture_idx
local get_text = require("failwind.utils").get_text

---@class failwind.ImportSpec
---@field name string
---@field repo string
---@field dir string
---@field file string
---@field filter function()

local import = {}

local import_directory = vim.fn.stdpath "data" .. "/failwind/imports"
vim.fn.mkdir(import_directory, "p")

local import_query = vim.treesitter.query.parse(
  "css",
  [[  (import_statement
        [(call_expression
           (function_name)
           (arguments
             .
             (string_value) @url
             (string_value)? @file))
          
         (string_value) @url]
        [(keyword_query) @keyword
         (feature_query) @feature]?) @import ]]
)

--- Get the repo directory path
---@param name string
---@return string
local make_repo_directory = function(name)
  name = name:gsub("/", "__")
  return vim.fs.joinpath(import_directory, name)
end

---comment
---@param spec failwind.ImportSpec
import.get_repository = function(spec)
  if vim.uv.fs_stat(spec.dir) then
    return true
  end

  local job = vim.system({ "git", "clone", spec.repo, spec.dir }):wait()
  return job.code == 0
end

local matching_tags_query = vim.treesitter.query.parse(
  "css",
  [[
  (stylesheet
    (rule_set
      (selectors (tag_name) @tag)
      (block) @block) @ruleset)
  ]]
)

--- Read an import spec
---@param spec failwind.ImportSpec
import.read = function(spec)
  if not import.get_repository(spec) then
    error("Unable to clone repository: " .. spec.repo)
  end

  local file_path = vim.fs.joinpath(spec.dir, spec.file)
  local text = util.fix_stupid_treesitter_brace(vim.fn.readfile(file_path))
  if spec.filter then
    local spec_ctx = require("failwind.context").new(text)

    local result = {}

    local tag_idx = get_capture_idx(matching_tags_query.captures, "tag")
    local block_idx = get_capture_idx(matching_tags_query.captures, "block")
    local ruleset_idx = get_capture_idx(matching_tags_query.captures, "ruleset")
    for _, match, _ in spec_ctx:iter(matching_tags_query) do
      local tag_name = get_text(spec_ctx, match[tag_idx][1])
      local filtered = spec.filter(spec_ctx, tag_name, match[ruleset_idx][1], match[block_idx][1])
      if filtered ~= nil then
        table.insert(result, filtered)
      end
      -- if tag_name == spec.filter then
      --   table.insert(matching_nodes, get_text(text), )
      -- end
    end

    return util.fix_stupid_treesitter_brace(result)
  else
    return text
  end
end

--- Makes an import spec
---@param url string
---@param file string
---@return failwind.ImportSpec
import.make_spec = function(url, file, filter)
  local spec = {}
  if not vim.startswith(url, "https://github.com/") then
    spec.name = url
    spec.url = "https://github.com/" .. url
  else
    error "didn't write links yet"
  end

  spec.dir = make_repo_directory(spec.name)
  spec.file = file
  spec.filter = filter

  return spec
end

local feature_query_strings = vim.treesitter.query.parse(
  "css",
  [[ (feature_query
      (feature_name) @feature_name
      [(_ (string_value) @string)
       (string_value) @string
       (_ (plain_value) @tag)
       (plain_value) @tag]) ]]
)

import._make_feature_filter = function(ctx, feature_node)
  local format_plugin_query_string = [[
((rule_set
  (selectors (tag_name) @_tag)
  (block
   (rule_set
     (selectors
       (pseudo_class_selector
         (class_name)
         (arguments (string_value) @class)))) @result)) 
 (#eq? @_tag "plugins")
 (#eq? @class "\"%s\""))
  ]]

  local format_plugin_query_string_tag = [[
((rule_set
  (selectors (tag_name) @_tag)
  (block
   (rule_set
     (selectors (tag_name) @tag)
     (block)) @result))
 (#eq? @_tag "plugins")
 (#eq? @tag "%s"))
  ]]

  local plugin_queries = {}

  local string_idx = get_capture_idx(feature_query_strings.captures, "string")
  local tag_idx = get_capture_idx(feature_query_strings.captures, "tag")
  local feature_name_idx = get_capture_idx(feature_query_strings.captures, "feature_name")
  for _, match, _ in ctx:iter(feature_query_strings, feature_node) do
    local feature_name = get_text(ctx, match[feature_name_idx][1])

    if feature_name == "plugins" then
      if match[string_idx] then
        local plugin_name = eval.css_value(ctx, match[string_idx][1])
        local formatted_query = string.format(format_plugin_query_string, plugin_name)
        local query = vim.treesitter.query.parse("css", formatted_query)
        table.insert(plugin_queries, query)
      elseif match[tag_idx] then
        local plugin_name = get_text(ctx, match[tag_idx][1])
        local formatted_query = string.format(format_plugin_query_string_tag, plugin_name)
        local query = vim.treesitter.query.parse("css", formatted_query)
        table.insert(plugin_queries, query)
      else
        error "UNKNOWN MATCH TIME"
      end
    else
      error("Unsupported feature filter:" .. feature_name .. vim.inspect(match))
    end
  end

  --[[ (feature_query ; [9, 39] - [11, 2]
        (feature_name) ; [9, 40] - [9, 47]
        (grid_value ; [9, 49] - [11, 1]
          (string_value))) --]]
  return function(matched_ctx, tagname, ruleset_node)
    if tagname == "plugins" then
      local matches = {}
      for _, query in ipairs(plugin_queries) do
        local result_idx = get_capture_idx(query.captures, "result")
        for _, match in matched_ctx:iter(query, ruleset_node) do
          local result = get_text(matched_ctx, match[result_idx][1])
          table.insert(matches, string.format("\n/* start */\nplugins {\n%s\n}\n", result))
        end
      end

      return table.concat(matches, "\n")
    else
      return nil
    end
  end
end

--- Get the specs from a file
---@param ctx failwind.Context
---@return TSNode
---@return failwind.ImportSpec?
import.evaluate = function(ctx)
  local url_idx = get_capture_idx(import_query.captures, "url")
  local file_idx = get_capture_idx(import_query.captures, "file")
  local keyword_idx = get_capture_idx(import_query.captures, "keyword")
  local feature_idx = get_capture_idx(import_query.captures, "feature")
  local import_idx = get_capture_idx(import_query.captures, "import")

  for _, match, _ in ctx:iter(import_query) do
    local import_node = match[import_idx][1]
    local url = eval.css_value(ctx, match[url_idx][1]) --[[@as string]]
    local file = "init.css"
    if match[file_idx] then
      file = eval.css_value(ctx, match[file_idx][1]) --[[@as string]]
    end

    local filter
    local keyword_node = (match[keyword_idx] or {})[1]
    if keyword_node then
      local keyword = get_text(ctx, keyword_node)
      filter = function(matched_ctx, tagname, ruleset_node)
        if keyword == tagname then
          return get_text(matched_ctx, ruleset_node)
        end

        return nil
      end
    end

    local feature_node = (match[feature_idx] or {})[1]
    if feature_node then
      filter = import._make_feature_filter(ctx, feature_node)
    end

    return import_node, import.make_spec(url, file, filter)
  end
end

return import
