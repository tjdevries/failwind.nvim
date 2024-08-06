;; extends

((call_expression
   (function_name) @_name
   (arguments (string_value) @injection.content))
 (#eq? @_name "lua")
 (#offset! @injection.content 0 1 0 -1)
 (#set! injection.language lua))
