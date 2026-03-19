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

## CI/CD

The project uses [folke's reusable GitHub Actions workflows](https://github.com/folke/github) with release-please for automated releases.

**Workflows:**
- **CI** (`.github/workflows/ci.yml`) — Runs tests + stylua on pushes to any branch except `main`, and on all PRs
- **Release** (`.github/workflows/release.yml`) — Runs tests + release-please on pushes to `main`
- **PR** (`.github/workflows/pr.yml`) — Validates PR titles follow Conventional Commits format

**Release process:** Merging semantic commits to `main` triggers release-please, which maintains a Release PR with changelog and version bump. Merging that PR creates a GitHub Release with a git tag.

**Config files:**
- `.github/release-please-config.json` — release-please configuration (release type: `simple`)
- `.release-please-manifest.json` — tracks the current version

## Commit Convention

All commits must use [Conventional Commits](https://www.conventionalcommits.org/) format:

```
<type>[optional scope][!]: <description>
```

**Types:** `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `ci`, `perf`

**Breaking changes:** Use `!` suffix (e.g., `feat!: remove legacy config`) or add a `BREAKING CHANGE` footer.

This convention is enforced on PR titles via CI and drives release-please version bumps and changelog generation:
- `fix:` → patch bump (0.1.0 → 0.1.1)
- `feat:` → minor bump (0.1.0 → 0.2.0)
- `feat!:` / `BREAKING CHANGE` → major bump (0.1.0 → 1.0.0)

## Documentation

When adding new features, adjusting existing commands, removing functionality, or changing configuration options, update `README.md` to reflect those changes. Keep the README in sync with the current state of the plugin.

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
    finder.lua                           -- .uproject discovery, ancestor traversal, engine path resolution, plugin discovery
    platform.lua                         -- OS detection, pure command assembly (no side effects)
    command.lua                          -- Declarative command builder (:UE subcommands + completion)
    provider.lua                         -- Capability registry (register/resolve pattern)
    job.lua                              -- Async job runner (UBT builds, shell commands)
    target.lua                           -- .Target.cs discovery and parsing
    progress.lua                         -- Build progress notifications (fidget/notify)
    ui/
      init.lua                           -- UI dispatch
      picker.lua                         -- Multi-backend picker (Snacks → Telescope → fzf-lua → native)
      tree.lua                           -- Multi-root file tree (Snacks explorer + fallback, files + solution views)
    lsp/
      init.lua                           -- LSP lifecycle (start/stop/restart/buf_attach/auto-start)
      config_gen.lua                     -- .clangd YAML generation with UE-optimized settings
      unrealisense_config_gen.lua        -- .unrealisense.toml generation
      backends/
        clangd.lua                       -- clangd backend (binary resolution, command building)
        unrealisense.lua                 -- UnrealISense backend
  modules/                               -- Feature modules (self-contained, standard interface)
    build.lua                            -- :UE build (preset-based async builds)
    run.lua                              -- :UE run
    search.lua                           -- :UE search
    generate.lua                         -- :UE generate project-files / clang-database
    editor_lock.lua                      -- BufReadPost engine file read-only enforcement
    lint.lua                             -- :UE lint (static analysis via UBT)
    diagnostics.lua                      -- :UE diagnostics (build error parsing)
    intel.lua                            -- :UE intel (clangd / UnrealISense management)
    debug.lua                            -- :UE debug (nvim-dap launch/attach with UE LLDB formatters)
    switch.lua                           -- :UE switch (header/source switching, Public/Private aware)
    tree.lua                             -- :UE tree (multi-root file tree)
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
| `core/schema.lua` | Declarative config schema, type/enum validation, unknown-key detection |
| `core/log.lua` | Named logger factory with async file writer + vim.notify for errors/warnings |
| `core/event.lua` | Pub/sub event bus. Each emit() also fires a vim User autocmd. |
| `core/finder.lua` | Ancestor directory traversal, .uproject discovery, engine path validation, plugin discovery |
| `core/platform.lua` | Pure command assembly per platform — returns data, never mutates state |
| `core/command.lua` | Declarative command builder: defines :UE with nested subcommands and tab completion |
| `core/provider.lua` | Capability registry for extension points (register/resolve by name with priority) |
| `core/ui/picker.lua` | Multi-backend picker abstraction (Snacks → Telescope → fzf-lua → native) |
| `core/job.lua` | Async job runner for UBT builds and shell commands via vim.uv |
| `core/target.lua` | Discovers and parses .Target.cs files for build target enumeration |
| `core/progress.lua` | Build progress display via fidget.nvim or vim.notify fallback |
| `core/lsp/init.lua` | Backend-agnostic LSP lifecycle: start/stop/restart/buf_attach, auto-start on first C++ buffer |
| `core/lsp/config_gen.lua` | Generates .clangd config excluding ThirdParty/Intermediate from indexing |
| `core/lsp/unrealisense_config_gen.lua` | Generates .unrealisense.toml with engine path |
| `core/lsp/backends/clangd.lua` | clangd backend: binary resolution, command building with UE-optimized flags |
| `core/lsp/backends/unrealisense.lua` | UnrealISense backend: binary resolution, command building with --engine-path |
| `modules/debug.lua` | `:UE debug` — nvim-dap launch/attach with UE LLDB formatter injection |
| `modules/switch.lua` | `:UE switch` — Header/source switching with Public/Private awareness |
| `modules/tree.lua` | `:UE tree` — Multi-root file tree (Project + Engine sidebar) |
| `core/ui/tree.lua` | Snacks explorer backend for dual-root tree (files + solution views) + `vim.ui.select` fallback |

### Configuration

Config is hierarchical (4 layers merged):
1. **Defaults** — hardcoded in `core/config.lua`
2. **User overrides** — passed via `require("unrealium").setup({ ... })`
3. **Project file** — `unrealium.json` near `.uproject`
4. **Runtime overrides** — `config.set(key, value)`

**`unrealium.json` format:**
```json
{
  "engine": { "folder": "/path/to/UE5", "allow_modifications": false },
  "logging": { "level": "info" },
  "ui": { "picker": { "prefer": ["snacks", "telescope", "native"] } },
  "build": { "configurations": ["Development", "DebugGame"], "output_mode": "terminal", "extra_args": [] },
  "run": { "extra_args": ["-norelativemousemode"] },
  "intel": { "server": "clangd", "clangd": { "enabled": true, "auto_start": true, "generate_config": true } }
}
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
