# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Plugin Does

unrealium.nvim is a Neovim plugin for Unreal Engine 5 project development. It auto-detects UE projects (via `.uproject` files), registers user commands for building/running/searching, enforces Engine file read-only status, manages clangd with UE-optimized settings, and integrates with multiple picker backends (Snacks, Telescope, fzf-lua, native).

## Commands

**Primary command:** `:UE <subcommand>` (e.g., `:UE build Development`, `:UE search grep Engine`)

**Legacy aliases:** `UBuild`, `URun`, `USearch`, `UGenProjectFiles`, `UGenClangDatabase`

**Run tests:**
```bash
./scripts/test
# Equivalent: nvim -l lua/tests/minit.lua --minitest
```

**Formatting:** The project uses stylua. Run via the CI/release GitHub Actions workflows (folke's reusable workflows).

## Architecture

### Directory Structure

```
plugin/unrealium.lua                     -- Entry point: version guard, re-init guard
lua/unrealium/
  init.lua                               -- Setup orchestrator + module registration + extension API
  types.lua                              -- Shared @class type annotations
  core/                                  -- Infrastructure modules
    config.lua                           -- Hierarchical config (defaults → user → project file → runtime)
    log.lua                              -- Per-module logger factory (file + notify writers)
    event.lua                            -- Pub/sub event bus + vim User autocmd bridge
    finder.lua                           -- .uproject discovery, ancestor traversal, engine path resolution
    platform.lua                         -- OS detection, pure command assembly (no side effects)
    command.lua                          -- Declarative command builder (:UE subcommands + completion)
    provider.lua                         -- Capability registry (register/resolve pattern)
    job.lua                              -- Async job runner (UBT builds, shell commands)
    target.lua                           -- .Target.cs discovery and parsing
    progress.lua                         -- Build progress notifications (fidget/notify)
    ui/
      init.lua                           -- UI dispatch
      picker.lua                         -- Multi-backend picker (Snacks → Telescope → fzf-lua → native)
    lsp/
      init.lua                           -- clangd lifecycle management (start/stop/restart/auto-start)
      config_gen.lua                     -- .clangd YAML generation with UE-optimized settings
  modules/                               -- Feature modules (self-contained, standard interface)
    build.lua                            -- :UE build (preset-based async builds)
    run.lua                              -- :UE run
    search.lua                           -- :UE search
    generate.lua                         -- :UE generate project-files / clang-database
    editor_lock.lua                      -- BufReadPost engine file read-only enforcement
    lint.lua                             -- :UE lint (static analysis via UBT)
    diagnostics.lua                      -- :UE diagnostics (build error parsing)
    intel.lua                            -- :UE intel (clangd optimization, .clangd config gen)
```

### Initialization Flow

```
plugin/unrealium.lua       -- Version guard (0.10.0+), re-init guard, auto-setup fallback
  └─> lua/unrealium/init.lua M.setup(user_config)
        ├─> config.init(user_config)
        ├─> log.init()
        └─> VimEnter autocmd (once) → init()
              ├─> config.get() → discovers project, loads config
              ├─> loads built-in modules, collects command specs
              ├─> command.create() → registers :UE with subcommands
              ├─> registers legacy aliases (UBuild, URun, USearch, etc.)
              └─> events.emit("unrealium.plugin_ready")
```

### Module Responsibilities

| Module | Role |
|--------|------|
| `core/config.lua` | 4-layer hierarchical config: defaults → user → project file → runtime. Lazy-loaded, module-local. |
| `core/log.lua` | Named logger factory with async file writer + vim.notify for errors/warnings |
| `core/event.lua` | Pub/sub event bus. Each emit() also fires a vim User autocmd. |
| `core/finder.lua` | Ancestor directory traversal, .uproject discovery, engine path validation |
| `core/platform.lua` | Pure command assembly per platform — returns data, never mutates state |
| `core/command.lua` | Declarative command builder: defines :UE with nested subcommands and tab completion |
| `core/provider.lua` | Capability registry for extension points (register/resolve by name with priority) |
| `core/ui/picker.lua` | Multi-backend picker abstraction (Snacks → Telescope → fzf-lua → native) |
| `core/job.lua` | Async job runner for UBT builds and shell commands via vim.uv |
| `core/target.lua` | Discovers and parses .Target.cs files for build target enumeration |
| `core/progress.lua` | Build progress display via fidget.nvim or vim.notify fallback |
| `core/lsp/init.lua` | clangd lifecycle: start/stop/restart with optimized flags, auto-start on first C++ buffer |
| `core/lsp/config_gen.lua` | Generates .clangd config excluding ThirdParty/Intermediate from indexing |

### Configuration

Config is hierarchical (4 layers merged):
1. **Defaults** — hardcoded in `core/config.lua`
2. **User overrides** — passed via `require("unrealium").setup({ ... })`
3. **Project file** — `.unrealium.json` (new) or `.unrealium` (legacy) near `.uproject`
4. **Runtime overrides** — `config.set(key, value)`

**New `.unrealium.json` format:**
```json
{
  "engine": { "folder": "/path/to/UE5", "allow_modifications": false },
  "logging": { "level": "info" },
  "ui": { "picker": { "prefer": ["snacks", "telescope", "native"] } },
  "build": { "configurations": ["Development", "DebugGame"], "output_mode": "terminal", "extra_args": [] },
  "run": { "extra_args": ["-norelativemousemode"] },
  "intel": { "clangd": { "enabled": true, "auto_start": true, "generate_config": true } }
}
```

**Legacy `.unrealium` format (still supported):**
```json
{ "EnginePath": "Path/To/Unreal/Install/Dir", "allowEngineModifications": false }
```

### Feature Module Interface

Each module follows this shape:
```lua
local M = {}
M.name = "build"
M.commands = {
  build = { handler = function(opts) ... end, desc = "...", args = { ... } },
}
function M.execute(type) ... end
function M.setup(config) ... end  -- optional
return M
```

### Extension API

External plugins integrate via:
```lua
local unrealium = require("unrealium")
unrealium.register_config("uep", defaults_table)
unrealium.register_commands("uep", { files = { ... } })
unrealium.register_provider("class_introspection", { name = "scanner", impl = ... })
```

### Testing Pattern

Tests use the Busted framework via minitest. The `_TEST` global flag gates private function exposure:
```lua
if _TEST then M._privateFunction = privateFunction end
```

### Logging

- Named loggers: `require("unrealium.core.log").get("module_name")`
- Log file: `vim.fn.stdpath("data") .. "/unrealium.log"`
- Level controlled via config (`logging.level`) or legacy `vim.g.unrealium_loglevel`
- Async writes via `vim.uv` (libuv)

### Platform Support

Only Linux is fully implemented. Mac uses `xcodebuild` (stub, untested). Windows returns an error from build commands.
