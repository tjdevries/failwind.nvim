# `failwind.nvim`

Failwind.nvim is not ready for production. You shouldn't even be LOOKING at this repo, but diabloproject was nice enough to gift some subs.

So... here it is :)

## Usage

Requirements: You'll need nvim-treesitter installed and the CSS parser enabled.

```lua
-- This loads a css file, you can see the examples/init.css for some inspiration
require('failwind').evaluate('/path/to/file.css')
```
