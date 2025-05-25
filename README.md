# unrealium.nvim

A lightweight Neovim plugin for Unreal Engine projects for the Editor.

---

## Features

- Detects and initializes automatically inside Unreal project directories
- Makes Engine files read-only to avoid triggering recompiles.
- Adds convenient user commands for building, running, and searching code
- Integrates with [Telescope](https://github.com/nvim-telescope/telescope.nvim) and [vim-dispatch](https://github.com/tpope/vim-dispatch)
- Currently tested on Linux, MacOS should work. Windows support... unlikely.

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
In an effort to provide flexibility, all configuration happens in an `.unrealium` file that lives in the root folder of your Unreal Project.

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
