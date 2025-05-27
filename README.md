# unrealium.nvim

A lightweight Neovim plugin for Unreal Engine projects for the Editor.

---

## Features

- Detects and initializes automatically inside Unreal project directories
- Makes Engine files read-only to avoid triggering recompiles.
- Adds convenient user commands for building, running, and searching code
- Integrates with [Telescope](https://github.com/nvim-telescope/telescope.nvim) and [vim-dispatch](https://github.com/tpope/vim-dispatch)
- Currently tested on Linux. MacOS would be a nice-to-have. Windows support is... unlikely.
---

## Installation

Unrealium depends on both Telescope and Vim-Dispatch (via the Neovim shim).

**Lazy.nvim** config:

```lua
{
  'jacksonhvisuals/unrealium.nvim',
  dependencies = {
    {
      'nvim-telescope/telescope.nvim',
      dependencies = { 'nvim-lua/plenary.nvim' },
    },
    {
      'radenling/vim-dispatch-neovim',
      dependencies = { 'tpope/vim-dispatch' },
    },
  },
}
```

---

## Project Configuration
In an effort to provide per-project flexibility, unrealium.nvim depends on there being a `.unrealium` file in the root folder of your Unreal Project. While it *could* support some sort of magical Unreal Engine detection through other config files, PATH, etc, you often want to be building against a very particular engine anyway. 

```json
{
  "EnginePath": "Path/To/Unreal/Install/Dir",
  "allowEngineModifications": false,
}
```
`EnginePath` should be the root Engine install directory, not it's Engine subfolder.
`allowEngineModifications` is optional, and defaults to false.

---

## Available User Commands

Unrealium automatically activates when the current working directory is inside an Unreal Engine project.

| Command | Args | Description |
|---------------------|--------|---------------------------------------------------|
| `:UBuild` | `<target> (Development / Debug)` | Build the Unreal project using `make` against either Dev/Debug targets |
| `:URun` | `<target> (Development / Debug)` | Launch Unreal Editor built against Dev/Debug via `Dispatch` |
| `:UGenProjectFiles` | N/A | Generate Makefile and compile_commands.json for the project    |
| `:USearch` | `<search_type> (search_files / live_grep) <context> (Project / Engine / All)` | Use Telescope to search in Project, Engine, or both |

---

## Extensibility
In an effort to make Unrealium extensible with your own preferences and vim settings, you can create an autocommand to fire off for the UnrealiumStart pattern.

```lua
vim.api.nvim_create_autocmd('User', {
  pattern = 'UnrealiumStart',
  group = vim.api.nvim_create_augroup('mygroup', { clear = true }),
  callback = function()
    print("Do fancy Unreal development-specific stuff here!")
  end,
})
```
