# unrealium.nvim

A lightweight Neovim plugin for Unreal Engine projects for the Editor.

---

## Features

- Detects and initializes automatically inside Unreal project directories
- Makes Engine files read-only to avoid triggering recompiles.
- Adds convenient user commands for building, running, and searching code
- Integrates with [Snacks picker](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md) and [vim-dispatch](https://github.com/tpope/vim-dispatch)
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
      'radenling/vim-dispatch-neovim',
      dependencies = { 'tpope/vim-dispatch' },
    },
    {
        'folke/snacks.nvim'
    }
  },
}
```

---

## Project Configuration

unrealium.nvim automatically detects your Unreal Engine installation by reading the `EngineAssociation` field from your `.uproject` file and resolving it via the Epic launcher's install registry.

If you need to override the engine path (e.g. a source build not registered with the launcher), create a `unrealium.json` file in the root folder of your Unreal Project:

```json
{
  "EnginePath": "/Path/To/Unreal/Install/Dir"
}
```

`EnginePath` should be the root Engine install directory, not its Engine subfolder. This is optional — only needed when automatic detection doesn't work.

Engine files are always read-only by default to prevent accidental recompiles.

---

## Available User Commands

Unrealium automatically activates when the current working directory is inside an Unreal Engine project.

| Command | Args | Description |
|---------------------|--------|---------------------------------------------------|
| `:UBuild` | `<target> (Development / Debug)` | Build the Unreal project using `make` against either Dev/Debug targets |
| `:URun` | `<target> (Development / Debug)` | Launch Unreal Editor built against Dev/Debug via `Dispatch` |
| `:UGenProjectFiles` | N/A | Generate Makefile and compile_commands.json for the project    |
| `:UGenerateClangDatabase` | `<target> (Project / Engine)` | Regenerate the compile_commands file |
| `:USearch` | `<search_type> (grep / file_search) <context> (Project / Engine / All)` | Search in Project, Engine, or both using Snacks picker |

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
