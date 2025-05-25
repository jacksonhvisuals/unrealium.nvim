# Unrealium.nvim

🚀 A lightweight Neovim plugin for Unreal Engine projects. Provides seamless build, run, project generation, and code search tooling—all tailored to UE workflows.

---

## ✨ Features

- Detects and initializes automatically inside Unreal project directories
- Adds convenient user commands for building, running, and searching code
- Integrates with [Telescope](https://github.com/nvim-telescope/telescope.nvim) and [vim-dispatch](https://github.com/tpope/vim-dispatch)

---

## 📦 Installation

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

## ✅ Available User Commands

Unrealium automatically activates when the current working directory is inside an Unreal Engine project.

| Command             | Description                                               |
|---------------------|-----------------------------------------------------------|
| `:UBuild`           | Build the Unreal project using `make` in Dev/Debug mode   |
| `:URun`             | Launch Unreal Editor in Dev/Debug mode via `Dispatch`     |
| `:UGenProjectFiles` | Generate Makefile and compile_commands for the project    |
| `:USearch`          | Use Telescope to search in Project, Engine, or both       |
