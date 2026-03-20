# unrealium.nvim

A Neovim plugin for Unreal Engine 5 project development.

---

## Features

- Auto-detects UE projects via `.uproject` files
- Engine file read-only enforcement to prevent accidental recompiles
- Unified `:UE` command with subcommands (build, run, search, generate, intel, lint, diagnostics, debug, switch, tree)
- UE5 snippet completions via [blink.cmp](https://github.com/Saghen/blink.cmp) (ULOG, ULOGFMT, UENUM, USTRUCT, UCLASS, UINTERFACE, UCAST, UFUNCTION, UPROPERTY) with smart log category and MODULE_API discovery
- Multi-backend picker support (Snacks, Telescope, fzf-lua, native fallback)
- LSP integration: clangd and [UnrealISense](https://github.com/jacksonhvisuals/unrealisense) with auto-start and config generation
- Build progress notifications via [fidget.nvim](https://github.com/j-hui/fidget.nvim)
- Event bus for extensibility with vim autocmd bridge
- Extension API for external plugins
- Platform support: Linux (full), macOS (partial)

---

## Installation

No hard dependencies. Picker backends and fidget.nvim are optional.

**Lazy.nvim:**

```lua
{
  'jacksonhvisuals/unrealium.nvim',
  opts = {},
  -- Optional dependencies for enhanced UI:
  -- { 'folke/snacks.nvim' }       -- Snacks picker
  -- { 'nvim-telescope/telescope.nvim' }  -- Telescope picker
  -- { 'ibhagwan/fzf-lua' }        -- fzf-lua picker
  -- { 'j-hui/fidget.nvim' }       -- Build progress display
}
```

---

## Setup

```lua
require("unrealium").setup({
  logging = { level = "info" },                -- "debug", "info", "warn", "error"
  ui = {
    picker = {
      prefer = { "snacks", "telescope", "fzf_lua", "native" },  -- priority order
    },
  },
  build = {
    configurations = { "Development", "DebugGame", "Debug", "Shipping", "Test" },
    presets = {},              -- named build presets
    output_mode = "terminal",
    progress = true,
    default_preset = nil,      -- preset name to use when no arg and no last preset
    auto_open_quickfix = true, -- auto-open quickfix window on build errors
    extra_args = {},           -- extra args passed to UBT
  },
  run = {
    default_type = "Development",  -- "Development" or "Debug"
    build_first = false,           -- when true, :UE run builds before launching
    split_height = 0.33,           -- terminal split height (0-1 = fraction, >= 1 = lines)
    show_log = true,               -- auto-show terminal split on run (false = background)
    extra_args = {},               -- extra args passed to the editor
  },
  search = {
    exclude_patterns = { "**/*.po", "**/*.archive", "**/*.gen.h", "**/Intermediate/Build/**" },
  },
  intel = {
    server = "clangd",         -- "clangd" or "unrealisense"
    clangd = {
      enabled = true,
      exclusive = false,       -- stop external clangd clients when unrealium starts its own
      cmd = nil,               -- custom clangd binary path
      extra_flags = {},        -- additional clangd flags, e.g. { "--query-driver=/path/to/clang++" }
      auto_start = true,       -- start clangd on first C++ buffer
      generate_config = true,  -- generate optimized .clangd file
      config_gen = {
        exclude_paths = { "ThirdParty", "Intermediate" },  -- paths to skip indexing
        extra_compile_flags = {},                           -- additional compile flags
      },
    },
    unrealisense = {
      cmd = nil,               -- custom binary path (default: "unrealisense" from PATH)
      engine_path = nil,       -- override engine path; defaults to engine.folder
      extra_args = {},         -- extra CLI args passed to unrealisense
      auto_start = true,       -- start on first C++ buffer
      generate_config = true,  -- generate .unrealisense.toml
    },
  },
  lint = {
    default_analyzer = nil,    -- e.g. "PVS-Studio"
  },
  generate = {
    default_clang_scope = nil, -- "Project" or "Engine"
  },
  editor_lock = {
    extra_paths = {},          -- additional paths to enforce read-only
  },
  debug = {
    adapter = "codelldb",        -- DAP adapter name
    default_preset = nil,        -- preset name to use by default
    extra_init_commands = {},     -- additional LLDB init commands
    extra_args = {},             -- extra args passed to the editor binary
  },
  tree = {
    default_view = "solution",   -- "solution" (dev-focused) or "files" (flat filesystem)
    engine_dirs = { "Source" },  -- engine subdirs to show (single entry points directly to that subdir)
    reveal_on_open = true,       -- expand and jump to current buffer's file when tree opens
    follow_file = true,          -- auto-reveal current buffer as you switch files
    show_hidden = false,         -- show hidden (dot) files
    show_ignored = false,        -- show gitignored files
  },
  snippets = {
    enabled = true,              -- enable UE5 snippet completions (ULOG, UENUM, UCLASS, etc.)
  },
})
```

All keys are optional — defaults are shown above. Calling `setup({})` with an empty table uses all defaults.

---

## Project Configuration

unrealium.nvim auto-detects your Unreal Engine installation by reading the `EngineAssociation` field from your `.uproject` file and resolving it via the Epic launcher's install registry.

For custom engine paths (e.g. source builds), create a config file next to your `.uproject`:

### `unrealium.json`

```json
{
  "engine": { "folder": "/path/to/UE5", "allow_modifications": false },
  "logging": { "level": "info" },
  "ui": { "picker": { "prefer": ["snacks", "telescope", "native"] } },
  "build": {
    "configurations": ["Development", "DebugGame"],
    "default_preset": "MyProjectEditor Linux Development",
    "output_mode": "terminal",
    "extra_args": []
  },
  "run": { "default_type": "Development", "split_height": 0.33, "show_log": true, "extra_args": ["-norelativemousemode"] },
  "search": { "exclude_patterns": ["**/*.po", "**/*.archive", "**/MyCustomExclude/**"] },
  "intel": {
    "server": "clangd",
    "clangd": {
      "enabled": true,
      "auto_start": true,
      "extra_flags": ["--query-driver=/usr/bin/clang++"],
      "generate_config": true,
      "config_gen": { "exclude_paths": ["ThirdParty", "Intermediate"], "extra_compile_flags": [] }
    },
    "unrealisense": {
      "auto_start": true,
      "generate_config": true
    }
  },
  "lint": { "default_analyzer": "PVS-Studio" },
  "generate": { "default_clang_scope": "Project" },
  "editor_lock": { "extra_paths": ["/path/to/shared/plugins"] }
}
```

Configuration is hierarchical (4 layers merged in order):

1. **Defaults** — hardcoded
2. **User overrides** — passed via `setup()`
3. **Project file** — `unrealium.json`
4. **Runtime overrides** — `config.set(key, value)`

---

## Commands

The primary command is `:UE <subcommand>`. Tab completion is available for all subcommands and their arguments.

### `:UE build [preset] [extra-args]`

Build the project. Use `:UE build!` to open a preset picker.

- `:UE build` — build with last/default preset (configurable via `build.default_preset`)
- `:UE build Development` — build a specific configuration
- `:UE build stop` — cancel the running build

### `:UE run [type] [extra-args]`

Launch the Unreal Editor.

- `:UE run` — run with default type (configurable via `run.default_type`)
- `:UE run Debug` — run with Debug configuration
- `:UE run log` — toggle the run terminal split (show/hide)

When `run.build_first = true`, `:UE run` automatically triggers a build first and only launches the editor on success.

When `run.show_log = false`, the editor process starts in the background without opening a terminal split. Use `:UE run log` to view the output.

### `:UE build-run [preset]`

Build the project then launch the editor on success. Always builds first regardless of `run.build_first` config. Accepts the same preset arguments as `:UE build`.

- `:UE build-run` — build with default preset, then run
- `:UE build-run MyProjectEditor Linux Development` — build specific preset, then run

### `:UE search [type] [scope] [search-term]`

Search project and engine files using the configured picker backend.

- `:UE search grep Project` — grep within project files
- `:UE search files Engine` — search filenames in engine
- `:UE search grep All` — grep across project and engine

Types: `grep`, `files`. Scopes: `Project`, `Engine`, `All` (default).

### `:UE generate <subcommand>`

| Subcommand | Description |
|---|---|
| `project-files` | Generate Makefile and compile_commands.json |
| `clang-database [scope]` | Regenerate compile_commands.json (scope: `Project`, `Engine`) |
| `header [manifest]` | Run UnrealHeaderTool (UHT) for code generation |

### `:UE intel <subcommand>`

| Subcommand | Description |
|---|---|
| `setup` | Generate config and start the configured LSP server (`intel.server`) |
| `setup-clangd` | Generate optimized `.clangd` config and start clangd |
| `setup-unrealisense` | Generate `.unrealisense.toml` and start UnrealISense |
| `status` | Show LSP server status |
| `stop` | Stop the active LSP server |
| `restart` | Restart the active LSP server |

### `:UE lint [type]`

Run static analysis. Type: `PVS-Studio`.

### `:UE diagnostics [filter]`

Browse build diagnostics. Filter: `errors`, `warnings`, `all` (default).

### `:UE debug [preset]`

Debug the project via nvim-dap. Use `:UE debug!` to open a preset picker.

- `:UE debug` — launch with default/last preset (Editor DebugGame)
- `:UE debug attach` — attach debugger to a running editor process
- `:UE debug!` — pick a debug preset interactively

Requires [nvim-dap](https://github.com/mfussenegger/nvim-dap). Automatically loads Epic's LLDB data formatters from the engine.

### `:UE switch [mode]`

Switch between header and source files with UE Public/Private directory awareness.

- `:UE switch` — open companion in current window
- `:UE switch split` — open in horizontal split
- `:UE switch vsplit` — open in vertical split

### `:UE tree [action]`

Multi-root file tree showing both the project and engine source as sibling roots in a sidebar. Requires [snacks.nvim](https://github.com/folke/snacks.nvim) for the full tree experience; falls back to `vim.ui.select` without it.

- `:UE tree` — toggle the tree sidebar (default view mode)
- `:UE tree solution` — toggle solution view (dev-focused hierarchy)
- `:UE tree files` — toggle filesystem view (flat dual-root)
- `:UE tree open` — open the tree sidebar
- `:UE tree close` — close the tree sidebar
- `:UE tree focus` — focus the tree sidebar (opens it if closed)
- `:UE tree reveal` — reveal the current buffer's file in the tree

**View modes:**

- **Solution** (default): Reorganizes the tree into a development-focused hierarchy. A master root node shows the project name, with `Project` and `Engine` as children. The Project node shows `Config/`, `Source/`, `Plugins/`, and the `.uproject` file. Within `Plugins/`, build artifact directories (`Intermediate`, `Binaries`) are filtered out.
- **Files**: Shows the raw filesystem tree with a master root node (project name) containing `Project` and `Engine` as children.

When toggling with a different view mode than the currently open tree, the tree closes and reopens with the new view.

The project root starts expanded and the engine root starts collapsed to avoid scanning the large engine directory on startup. Mutation actions (add, delete, rename, move, copy, paste) on engine files are blocked when `engine.allow_modifications` is `false` (the default).

### Snippets (blink.cmp)

unrealium.nvim provides UE5 snippet completions via a [blink.cmp](https://github.com/Saghen/blink.cmp) custom source.

| Snippet | Expands To | Smart Features |
|---|---|---|
| `ULOG` | `UE_LOG(Category, Verbosity, TEXT("..."))` | Log categories ranked by frequency from buffer + sibling files |
| `ULOGFMT` | `UE_LOGFMT(Category, Verbosity, "...")` | Same category discovery as ULOG |
| `UENUM` | `UENUM(BlueprintType) enum class ...` | Base type choice list (uint8, uint16, uint32, int32) |
| `USTRUCT` | `USTRUCT(BlueprintType) struct ...` | Modern `GENERATED_BODY()`, includes UPROPERTY member |
| `UCLASS` | `UCLASS() class MODULE_API ...` | MODULE_API from `*.Build.cs`, parent class choices, mirrored constructor |
| `UINTERFACE` | `UINTERFACE() class U.../I...` | MODULE_API from `*.Build.cs`, mirrored U-prefix/I-prefix names |
| `UCAST` | `Cast<Type>(Source)` | Type name mirrored into Cast template parameter |
| `UFUNCTION` | `UFUNCTION(Specifier)` | Common specifier choices (BlueprintCallable, Server, Client, etc.) |
| `UPROPERTY` | `UPROPERTY(Visibility, Access, Category)` | 3-stop: visibility, Blueprint access, category name |

**Smart discovery:**

- **Log categories**: Scans the current buffer and sibling C++ files for `UE_LOG`/`UE_LOGFMT` calls, ranks by frequency, falls back to `LogTemp`
- **MODULE_API**: Walks up directories from the current file looking for `*.Build.cs` (e.g., `MyModule.Build.cs` → `MYMODULE_API`). Falls back to scanning sibling files for `_API` patterns, then to `PROJECTNAME_API` placeholder

**blink.cmp setup:**

```lua
require("blink.cmp").setup({
  sources = {
    default = { "lsp", "path", "buffer", "unrealium" },
    providers = {
      unrealium = {
        name = "unrealium",
        module = "unrealium.integrations.blink",
      },
    },
  },
})
```

The source is only active in `cpp` / `c` filetype buffers within a detected UE project. Disable with `snippets = { enabled = false }` in your config.

### Legacy Aliases

These aliases are registered for backward compatibility:

| Alias | Equivalent |
|---|---|
| `:UBuild [config]` | `:UE build [config]` |
| `:URun [config]` | `:UE run [config]` |
| `:USearch [type] [scope]` | `:UE search [type] [scope]` |
| `:UGenProjectFiles` | `:UE generate project-files` |
| `:UGenClangDatabase [scope]` | `:UE generate clang-database [scope]` |

---

## Events

unrealium.nvim includes a pub/sub event bus. Each event also fires a vim `User` autocmd (dots replaced with underscores).

### Available Events

| Event | Autocmd Pattern | Description |
|---|---|---|
| `unrealium.plugin_ready` | `unrealium_plugin_ready` | Plugin initialized, all modules loaded |
| `unrealium.build_start` | `unrealium_build_start` | Build started |
| `unrealium.build_end` | `unrealium_build_end` | Build finished |
| `unrealium.build_progress` | `unrealium_build_progress` | Build progress update |
| `unrealium.config_loaded` | `unrealium_config_loaded` | Configuration loaded |
| `unrealium.job_start` | `unrealium_job_start` | Async job started |
| `unrealium.job_finish` | `unrealium_job_finish` | Async job finished |
| `unrealium.lsp_ready` | `unrealium_lsp_ready` | clangd started |
| `unrealium.lsp_indexed` | `unrealium_lsp_indexed` | clangd indexing complete |

The legacy `UnrealiumStart` autocmd pattern is still fired alongside `unrealium_plugin_ready`.

### Subscribing via Lua

```lua
local event = require("unrealium.core.event")

local unsub = event.on(event.BUILD_END, function(data)
  vim.notify("Build finished!")
end)

-- Later: unsub() to remove the listener
```

### Subscribing via autocmd

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "unrealium_plugin_ready",
  callback = function()
    -- Plugin is ready, do your thing
  end,
})
```

---

## Extension API

External plugins can integrate with unrealium.nvim:

```lua
local unrealium = require("unrealium")

-- Register config defaults for your namespace
unrealium.register_config("my_plugin", {
  some_setting = true,
})

-- Register commands under :UE
unrealium.register_commands("my_plugin", {
  my_cmd = {
    handler = function(opts) end,
    desc = "My custom command",
  },
})

-- Register a capability provider
unrealium.register_provider("class_introspection", {
  name = "scanner",
  impl = my_scanner,
  priority = 10,
})
```

---

## Codebase Structure

```
plugin/unrealium.lua                     -- Entry point: version guard, re-init guard
lua/unrealium/
  init.lua                               -- Setup orchestrator + module registration + extension API
  types.lua                              -- Shared type annotations
  core/
    config.lua                           -- Hierarchical config (defaults -> user -> project -> runtime)
    log.lua                              -- Per-module logger factory (file + notify writers)
    event.lua                            -- Pub/sub event bus + vim User autocmd bridge
    finder.lua                           -- .uproject discovery, engine path resolution
    platform.lua                         -- OS detection, pure command assembly
    command.lua                          -- Declarative command builder (:UE subcommands + completion)
    provider.lua                         -- Capability registry (register/resolve pattern)
    job.lua                              -- Async job runner via vim.uv
    target.lua                           -- .Target.cs discovery and parsing
    progress.lua                         -- Build progress (fidget/notify)
    ui/
      init.lua                           -- UI dispatch
      picker.lua                         -- Multi-backend picker abstraction
      tree.lua                           -- Multi-root file tree (Snacks + fallback)
    lsp/
      init.lua                           -- LSP lifecycle (start/stop/restart/buf_attach/auto-start)
      config_gen.lua                     -- .clangd YAML generation with UE-optimized settings
      unrealisense_config_gen.lua        -- .unrealisense.toml generation
      backends/
        clangd.lua                       -- clangd backend (binary resolution, command building)
        unrealisense.lua                 -- UnrealISense backend
  modules/
    build.lua                            -- :UE build
    run.lua                              -- :UE run
    search.lua                           -- :UE search
    generate.lua                         -- :UE generate
    editor_lock.lua                      -- Engine file read-only enforcement
    lint.lua                             -- :UE lint
    diagnostics.lua                      -- :UE diagnostics
    intel.lua                            -- :UE intel (clangd / UnrealISense management)
    debug.lua                            -- :UE debug (nvim-dap integration)
    switch.lua                           -- :UE switch (header/source switching)
    tree.lua                             -- :UE tree (multi-root file tree)
    snippets.lua                         -- UE5 snippet builders (ULOG, UENUM, UCLASS, etc.) + MODULE_API discovery
  integrations/
    blink.lua                            -- blink.cmp custom source for UE5 snippets
```
