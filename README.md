# `failwind.nvim`

Failwind.nvim is not ready for production. You shouldn't even be LOOKING at this repo, but diabloproject was nice enough to gift some subs.

So... here it is :)

The goal of `failwind.nvim` is to allow you to write neovim config in a declarative way using CSS.
As we all know, css is a very powerful and beautiful language, and we thought that more software should use it.
## Installation
### Step 0: Install neovim
nightly or stable > 0.11.0 is recommended
### Step 1: Install nvim-treesitter & css parser
You will need nvim-treesitter for failwind to work becuase
it relies on tresitter queries to parse your `init.css` file.
Most distributions and configs have it out of the box, but if your does not, refer to [nvim-treesitter docs](https://github.com/nvim-treesitter/nvim-treesitter).
Then run `:TSInstall css` or add css to `ensure_installed`.
### Step 2: Add `failwind.nvim` as a dependency
Install failwind using your favorite package manager.
E.g. with Lazy:
```lua
{
	"tjdevries/failwind.nvim",
	init = function()
		require('failwind').evaluate('<your-init-css-file>')
	end,
	-- This ensures that nvim-treesitter is installed and loaded **before** failwind.
	dependencies = {"nvim-treesitter"}
}
```
## `init.css` file
You can look at the examples/kickstart.css for some inspiration.

### Basic operations
#### `lua("lua-expression")`
Calls lua expression. For example: `lua("vim.diagnostic.setloclist()")`
#### `vim-fn-stdpath("path")`
Calls vim function `vim.fn.stdpath("path")`
You can call any lua function with this syntax.

Failwind expects your init.css file to contain following sections:
 - `options`
 - `keymaps`
 - `plugins`
 - `highlight`
 - `autocmds`

### `options` section
This section is used to set global options for Neovim.
Do your usual `vim.opt` calls here.

### `keymaps` section
This section is used to define keymaps.
for each vim mode (normal, visual, etc.) it can have a ruleset with keymaps for that mode.
Each keymap is a table with pseudoclass `key("key")`and the following fields:
 - `command`: string with the name of the command to call.
   Use this field to set specific command to execute.
   For example: `"Telescope find_files"`
 - `action`: string or call expression to execute.
   For example: `lua("vim.diagnostic.setloclist()")` (lua call) or `<C-\><C-n>` (literally key presses)
 - `desc`: Description of the keymap.
   For example: `"Search Neovim Files"`
### `plugins` section
This section is used to define plugins.
It is a ruleset with `:repo("repo-name")` pseudoclasses as keys.
Inside each ruleset you can define the following things:
 - `setup`: array of strings with names of plugins to setup from this repo.
   For example: `"mason" "mason-lspconfig"`
 - `:setup("plugin-name")` pseudoclasses to set up plugins from this repo. The ruleset provided will be used as plugin options to setup function.
 - `depends`: array of strings with names of plugins to be installed/loaded prior to the target plugin.
   For example: `"nvim-treesitter" "nvim-treesitter-textobjects"`
 - `keymaps`: See `keymaps` section.
All other fields will be directly passed to plugin's table
