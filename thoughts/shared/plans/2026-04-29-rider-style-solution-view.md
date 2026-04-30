# Rider-style Solution View Implementation Plan

## Overview

Bring `:UE tree solution` in line with Rider's Solution tab: curated Project and Engine subtrees, hoisted `.Target.cs` files, plugin-internals allow-list, JSON-style icons for `.uproject`/`.uplugin`, and a fixed master-root hierarchy. Counts and a tab-strip toggle are explicitly out of scope.

The companion research is at `~/.claude/plans/given-this-research-users-jhayes-claude-clever-sketch.md`. It catalogues every divergence; this plan addresses the ones the user signed off on (decisions captured in §"Decisions" below).

## Current State Analysis

- `lua/unrealium/core/ui/tree.lua:232-453` — `make_solution_finder` is the focal function. It yields a master root (synthetic) and two real roots (Project, Engine), then walks each with `Snacks.explorer.tree.Tree:get` and yields nodes via a callback.
- The master root and the Project root **both set `file`/`text` to `project_root`**, so Snacks dedupes them in its internal items table — that is why the user observes "Project and Engine aren't proper children of {ProjectName}". The same bug exists in `make_finder` (Files view) at lines 122-217.
- The default Snacks file formatter renders `vim.fs.basename(item.text)` (because `formatters.file = { filename_only = true }`). With `label = "Project"` and `text = "/path/to/MyProject"`, the user sees the label *plus* the path basename appended — the second user-reported symptom.
- Engine root is resolved by `lua/unrealium/modules/tree.lua:18-48` `resolve_engine_root`, which uses `tree.engine_dirs` (default `{ "Source" }`). With the default, the engine root resolves to `<engine>/Engine/Source/` for *both* Solution and Files views.
- `.Target.cs` discovery already exists at `lua/unrealium/core/target.lua` (`M.discover(project_folder)`).
- Plugin discovery exists at `lua/unrealium/core/finder.lua:332-342` (`M.discover_plugins`), but is only used by the fallback picker.
- Tree config defaults at `lua/unrealium/core/config.lua:73-80` — no view-specific scoping today.
- No existing tree tests; `lua/tests/core/target_spec.lua` and `lua/tests/core/finder_spec.lua` are the closest analogues for test patterns.

## Desired End State

After this plan:

- `:UE tree solution` renders a clean three-level hierarchy:
  ```
  {ProjectName}                       (master root, expanded)
  ├── Project                         (curated)
  │   ├── Plugins/                    (Intermediate/Binaries hidden; plugin internals curated)
  │   ├── Source/                     (.Target.cs files removed from this walk)
  │   ├── Config/
  │   ├── {Name}.uproject             (JSON brace icon)
  │   └── {Name}{Editor}.Target.cs    (hoisted virtual children)
  └── Engine                          (collapsed by default)
      ├── Platforms/
      ├── Plugins/
      ├── Source/
      ├── Config/
      └── Shaders/
  ```
- The Project and Engine root labels render as plain `Project` / `Engine` with no path basename suffix.
- Master root renders as plain `{ProjectName}` with Project/Engine as proper children.
- `:UE tree files` is unaffected in scope but shares the master-root rendering fix (no path suffix; proper hierarchy).
- `tree.engine_dirs` no longer affects Solution view; Files view continues to honor it.

### Verification:
- Open a UE project with a source-build engine and a plugin → confirm structure matches the diagram above.
- Set `tree.engine_dirs = { "Source" }` (default) → Solution view still shows Engine as `Platforms/Plugins/Source/Config/Shaders` (decoupled). Files view still scopes Engine to `Source/`.
- All new `tree_spec.lua` tests pass under `./scripts/test`.

### Key Discoveries:
- The master-root path collision (`virtual_root.file == project_item.file`) is the root cause of the broken hierarchy at `lua/unrealium/core/ui/tree.lua:125-132`, `:212`, `:328-335`, `:415` — Snacks keys items by `text`/`file` and collapses duplicates.
- `Snacks.picker(...)` accepts a `format` field as either a string (builtin name) or a function `(item, picker) → segments[]`. The current picker uses `formatters.file = { filename_only = true }` which configures the builtin file formatter (`tree.lua:578-580`). To inject custom rendering we either dispatch via a top-level `format = function(...)` callback or add a discriminator field on items and continue using the builtin.
- `target.discover()` returns `{name, file, type}` records — the `file` is an absolute path under `Source/`. To hoist, we yield with `parent = project_item` and skip `.Target.cs` in the `Source/` walk.
- `Tree:get(root, cb, filter_opts)` walks lazily based on `node.open`. Items are yielded in tree-walk order; Snacks orders siblings using the `sort` field on items (the picker is configured with `sort = { fields = { "sort" } }` at `tree.lua:564`). Domain ordering is achieved by setting an explicit `sort` prefix on the immediate children of the Project label.

## Decisions (locked)

| # | Decision |
|---|----------|
| 1 | Solution view always points Engine to `<engine>/Engine/` and applies the curated allow-list. `tree.engine_dirs` is ignored in Solution view and continues to drive Files view only. |
| 2 | No counts (no master-root total, no per-category counts). |
| 3 | `.Target.cs` files are hoisted as virtual children of the Project label and excluded from the `Source/` walk to avoid duplicates. |
| 4 | Plugin internals allow-list: `Source/`, `Config/`, `Resources/`, `*.uplugin`, `Content/Python/`, `Source/Python/`. Everything else under a plugin is hidden. |
| 5 | `.uproject` and `.uplugin` get a JSON brace icon via a picker-scoped formatter override. No global devicons / mini.icons registration. `.Target.cs` and `.Build.cs` keep devicons' `.cs` glyph (no Rider external-link decoration). No UE controller icon for the game project. |
| 6 | No tab-strip toggle; existing `:UE tree solution|files|symbols` keyword switch is sufficient. |
| 7 | Domain sort within Project: `Plugins` → `Source` → `Config` → `*.uproject` → `*.Target.cs`. |
| 8 | Master root labelled `{ProjectName}`; immediate children labelled exactly `Project` and `Engine` (no path basename suffix); fix the collision so Project and Engine are real children of the master root. |

## What We're NOT Doing

- No project counts (master-root total or per-category).
- No tab UI for switching views in-pane.
- No global icon registration via mini.icons or nvim-web-devicons.
- No external-link arrow on `.Target.cs` (no Nerd Font glyph for it).
- No UE-controller game-project icon.
- No changes to symbols view (`make_symbols_finder`) or to `make_actions`.
- No changes to the `vim.ui.select` fallback path beyond what bleeds through naturally (it does not render labels).
- No new config keys unless required to express a decision (we expect none).

## Implementation Approach

Five phases, each independently testable. Phase 1 is foundational and shared by Files and Solution views. Phases 2–4 are Solution-view-only behavioral changes layered on top. Phase 5 closes out docs and tests.

---

## Phase 1: Master-root rendering & hierarchy fixes

### Overview

Eliminate the `virtual_root` ↔ project-item path collision and stop Snacks from rendering a path basename next to root labels. Same bug, same fix, applied in both `make_finder` and `make_solution_finder`.

### Changes Required:

#### 1. Synthetic ID for the virtual master root
**File**: `lua/unrealium/core/ui/tree.lua`
**Locations**: `make_finder` (`:122-133`), `make_solution_finder` (`:325-336`)

Give the virtual master root a unique non-filesystem `text`/`file` so it cannot collide with any real path Snacks tracks.

```lua
-- Before:
local virtual_root = {
    file = project_root,
    dir = true,
    open = true,
    text = project_root,
    sort = "",
    label = project_name,
}

-- After:
local virtual_root_id = "ue:tree:root:" .. project_root
local virtual_root = {
    file = virtual_root_id,         -- synthetic; won't be opened, no fs_stat collision
    dir = true,
    open = true,
    text = virtual_root_id,
    sort = "",
    label = project_name,
    is_ue_root_label = true,        -- flag for the formatter
}
```

The Project and Engine root items keep their real `file`/`text` (so opening them still works). They already declare `parent = virtual_root` (`:161, :366`), and now that `virtual_root.text` is unique, Snacks will render them as children rather than collapsing.

Also stamp `is_ue_root_label = true` on the items returned from `yield_root` / `make_root_item` for `Project` and `Engine` so the formatter can recognise them.

#### 2. Custom `format` function on the `ue_tree` picker
**File**: `lua/unrealium/core/ui/tree.lua`
**Location**: `M.open_snacks` Snacks picker config (`:560-621`)

Replace the `formatters.file = { filename_only = true }` configuration with a top-level `format` callback that dispatches by item kind. The callback returns Snacks segment arrays (`{ {text, hl}, ... }`).

```lua
local default_file_format = require("snacks.picker.format").file

local function format_item(item, picker)
    -- Root label items: render the label only (no path basename, no icon).
    if item.is_ue_root_label then
        return { { item.label or "", "SnacksPickerDir" } }
    end
    -- Phase 4 hook: special icons for .uproject / .uplugin land here.
    -- For now defer everything else to Snacks' default file formatter so
    -- filename_only behaviour (basename) is preserved for the rest of the tree.
    return default_file_format(item, picker)
end
```

Wire it into the picker config:

```lua
Snacks.picker({
    ...
    format = format_item,
    formatters = {
        file = { filename_only = true },   -- still used by default_file_format
        severity = { pos = "right" },
    },
    ...
})
```

> Implementation note: the exact `require()` path for the default file formatter (e.g. `snacks.picker.format`) should be confirmed against the installed Snacks version during implementation. If the API differs, the fallback is to inline a `vim.fs.basename(item.text)` rendering — only the root-label special case is load-bearing for this phase.

### Success Criteria:

#### Automated Verification:
- [x] Existing test suite passes: `./scripts/test`
- [x] Stylua passes: `stylua --check lua/`
- [x] No new Lua diagnostics from `:checkhealth` after reload.

#### Manual Verification:
- [x] `:UE tree solution` shows `{ProjectName}` as the top node with `Project` and `Engine` rendered indented underneath it (proper hierarchy).
- [x] `Project` and `Engine` render with no trailing path basename ("Project" not "Project MyProjectFolder").
- [x] Expanding `Project` still shows the curated children (current behaviour preserved at this phase).
- [x] `:UE tree files` master-root rendering matches: same fix, same correctness.
- [x] Reveal-on-open still finds the current buffer's file in the tree.

**Implementation Note**: Pause here for manual confirmation that the master-root hierarchy and labels render correctly before proceeding to Phase 2.

---

## Phase 2: Engine subtree decoupling & curation

### Overview

Make Solution view's Engine root always resolve to `<engine>/Engine/` independently of `tree.engine_dirs`, then filter children to a curated allow-list. Files view's behavior is preserved.

### Changes Required:

#### 1. View-aware engine root resolution
**File**: `lua/unrealium/modules/tree.lua`
**Location**: `resolve_engine_root` (`:18-48`) and call site (`:82`)

Take the view as input; for `solution`, always return `<engine>/Engine/` (or fall back as before). For `files`, keep the current `engine_dirs`-based resolution.

```lua
---@param cfg UnrealiumConfig
---@param view string "solution"|"files"
---@return string|nil engine_root
local function resolve_engine_root(cfg, view)
    if not cfg.Engine or not cfg.Engine.Folder then
        log.warn("No engine path configured; tree will show project only")
        return nil
    end

    local engine_folder = cfg.Engine.Folder
    local engine_root = vim.fs.joinpath(engine_folder, "Engine")

    if view == "solution" then
        if vim.fn.isdirectory(engine_root) == 1 then
            return engine_root
        end
        if vim.fn.isdirectory(engine_folder) == 1 then
            return engine_folder
        end
        log.warn("Engine directory does not exist: %s", engine_folder)
        return nil
    end

    -- files view: existing engine_dirs-based resolution
    local tree_settings = cfg.settings.tree
    if tree_settings.engine_dirs and #tree_settings.engine_dirs == 1 then
        local subdir = vim.fs.joinpath(engine_folder, "Engine", tree_settings.engine_dirs[1])
        if vim.fn.isdirectory(subdir) == 1 then
            return subdir
        end
    end
    if vim.fn.isdirectory(engine_root) == 1 then
        return engine_root
    end
    if vim.fn.isdirectory(engine_folder) == 1 then
        return engine_folder
    end
    log.warn("Engine directory does not exist: %s", engine_folder)
    return nil
end
```

Update the call site at `:82` to pass `view`.

#### 2. Engine allow-list filter in Solution finder
**File**: `lua/unrealium/core/ui/tree.lua`
**Location**: `make_solution_finder` engine walk (`:441-451`)

Allow only `Platforms`, `Plugins`, `Source`, `Config`, `Shaders` as the top-level entries under the engine root. Their children pass through unfiltered (i.e. the user can drill into `Engine/Source/Runtime/Core/...` as today).

```lua
local ENGINE_ALLOW = { Platforms = true, Plugins = true, Source = true, Config = true, Shaders = true }

if engine_root then
    local engine_item = make_root_item(engine_root, "Engine", true, false)

    Tree:get(engine_root, function(node)
        if node.path == engine_root then
            return
        end
        local rel = node.path:sub(#engine_root + 2)
        local top_dir = rel:match("^([^/]+)")
        if not top_dir or not ENGINE_ALLOW[top_dir] then
            return
        end
        yield_node(node, engine_item)
    end, filter_opts)
end
```

### Success Criteria:

#### Automated Verification:
- [ ] `./scripts/test` passes (no regressions).
- [ ] Stylua: `stylua --check lua/`
- [ ] New unit assertions added in Phase 5 for the Engine allow-list pass when wired up.

#### Manual Verification:
- [ ] On a source-build engine, `:UE tree solution` → expand `Engine` shows exactly five top-level entries: `Platforms`, `Plugins`, `Source`, `Config`, `Shaders`. No `Binaries`, `Build`, `DerivedDataCache`, `Saved`, `Documentation`, `Programs`, `Extras`.
- [ ] Drilling into `Engine > Source > Runtime > Core` still works (children unfiltered below the top level).
- [ ] `:lua require("unrealium.core.config").set("tree.engine_dirs", { "Source" })` then `:UE tree solution` → Engine still shows the curated five entries (decoupled).
- [ ] `:UE tree files` still scopes Engine to `Source/` with `engine_dirs = { "Source" }` (unchanged behaviour).

**Implementation Note**: Pause for manual confirmation before proceeding to Phase 3.

---

## Phase 3: Project-root curation

### Overview

Hoist `.Target.cs` files to the Project label level, exclude them from the `Source/` walk, expand the plugin allow-list to preserve Python directories, and enforce Rider-style domain order at the project-root level.

### Changes Required:

#### 1. `.Target.cs` hoisting
**File**: `lua/unrealium/core/ui/tree.lua`
**Location**: `make_solution_finder` project walk (`:417-439`)

After the project walk, discover `.Target.cs` files via `core/target.lua` and yield each one as a virtual child of the Project label item. Update the in-walk filter to skip nodes whose path ends in `.Target.cs` so they don't appear under `Source/`.

```lua
-- Inside the project walk, near the existing Source check:
if top_dir == "Source" then
    if node.path:match("%.Target%.cs$") then
        return  -- hoisted separately below; don't render under Source/
    end
    yield_node(node, project_item)
end

-- After the Tree:get walk completes, hoist .Target.cs files:
local target_mod = require("unrealium.core.target")
for _, t in ipairs(target_mod.discover(project_root)) do
    local item = {
        file = t.file,
        dir = false,
        text = t.file,
        parent = project_item,
        last = true,
        type = "file",
        sort = "5_" .. vim.fs.basename(t.file),  -- domain sort: after .uproject
    }
    cb(item)
end
```

The `sort` prefix `5_` is part of the Phase 3.3 domain-order scheme.

#### 2. Plugin internals allow-list
**File**: `lua/unrealium/core/ui/tree.lua`
**Location**: `make_solution_finder` (`:427-434`)

Replace the `Intermediate`/`Binaries` exclusion with an explicit allow-list of plugin-internal top-level dirs/files. Preserve `Content/Python/` and `Source/Python/` (decision §4).

```lua
local PLUGIN_ALLOW_DIR = { Source = true, Config = true, Resources = true }
-- Specific subpaths to keep even when their top-level dir is otherwise filtered:
-- e.g. Content/Python/, Source/Python/

elseif top_dir == "Plugins" then
    -- rel is like: "Plugins/<PluginName>/<sub>/..."
    local segments = vim.split(rel, "/", { plain = true })
    -- segments[1] == "Plugins", segments[2] == <PluginName>
    if #segments == 1 then
        yield_node(node, project_item)              -- "Plugins" itself
    elseif #segments == 2 then
        yield_node(node, project_item)              -- each plugin folder
    else
        local plugin_top = segments[3]              -- first dir/file inside the plugin
        if PLUGIN_ALLOW_DIR[plugin_top] then
            yield_node(node, project_item)
        elseif plugin_top == "Content" and segments[4] == "Python" then
            yield_node(node, project_item)
        elseif #segments == 3 and plugin_top:match("%.uplugin$") then
            yield_node(node, project_item)
        end
        -- everything else under a plugin is hidden (Intermediate, Binaries, Docs,
        -- Tests, top-level READMEs, etc.)
    end
end
```

> Note: `Source/Python/` is automatically covered because `Source` is in the allow-list and we don't filter below it. `Content/Python/` is the explicit exception that needs the dedicated branch.

#### 3. Domain sort within Project
**File**: `lua/unrealium/core/ui/tree.lua`
**Location**: `make_solution_finder` `yield_node` and project-walk callback

For root-level children of the Project label, set an explicit `sort` prefix to enforce: `Plugins (1)` → `Source (2)` → `Config (3)` → `*.uproject (4)` → `*.Target.cs (5)`. Children below the top level inherit Snacks' default ordering.

Add a small helper inside the project walk:

```lua
local PROJECT_TOP_SORT = {
    Plugins = "1",
    Source = "2",
    Config = "3",
}

-- In the walk callback, when yielding a node whose parent is the project root,
-- set item.sort using the helper:
local function project_sort(rel, top_dir, basename)
    if #vim.split(rel, "/", { plain = true }) == 1 then
        if top_dir == "Plugins" or top_dir == "Source" or top_dir == "Config" then
            return PROJECT_TOP_SORT[top_dir] .. "_" .. top_dir
        elseif basename:match("%.uproject$") then
            return "4_" .. basename
        end
    end
    return nil  -- inherit default for grandchildren
end
```

In `yield_node` (or inline at each call site), set `item.sort = project_sort(rel, top_dir, vim.fs.basename(node.path))` when the parent is the project label. The hoisted `.Target.cs` items already get `sort = "5_..."` from change 3.1.

> Snacks may sort items globally by `sort` field — verify during implementation that scoping works (children of different parents shouldn't interleave). If they do, prefix with the parent sort to maintain hierarchy: e.g. `project_item.sort .. "/" .. PROJECT_TOP_SORT[top_dir]`.

### Success Criteria:

#### Automated Verification:
- [ ] `./scripts/test` passes including new tests added in Phase 5.
- [ ] Stylua: `stylua --check lua/`

#### Manual Verification:
- [ ] On a project with `Source/<Name>Editor.Target.cs`, `:UE tree solution` shows `<Name>Editor.Target.cs` as a sibling of `<Name>.uproject` under the Project label.
- [ ] The same `.Target.cs` file does NOT appear under `Source/` (no duplicate).
- [ ] On a plugin with arbitrary loose files (`Docs/`, `Tests/`, top-level `README.md`), they are hidden.
- [ ] On a plugin with `Content/Python/foo.py`, `Content/` is hidden EXCEPT the `Python/` subtree which is visible.
- [ ] On a plugin with `Source/Python/bar.py`, the file is visible (covered by `Source` being in the allow-list).
- [ ] Project-label children render in the order `Plugins`, `Source`, `Config`, `<Name>.uproject`, `<Name>{Editor}.Target.cs`.

**Implementation Note**: Pause for manual confirmation before Phase 4.

---

## Phase 4: Custom icons (picker-scoped)

### Overview

JSON brace icon for `.uproject` and `.uplugin`. Scoped to the `ue_tree` picker via the format function from Phase 1 — no global devicons / mini.icons registration.

### Changes Required:

#### 1. Extend the format function with file-extension dispatch
**File**: `lua/unrealium/core/ui/tree.lua`
**Location**: `format_item` (added in Phase 1)

```lua
local JSON_BRACE_ICON = ""        -- nf-md-code_json (verify glyph in implementation)
local JSON_BRACE_HL = "SnacksPickerIcon"

local function format_item(item, picker)
    if item.is_ue_root_label then
        return { { item.label or "", "SnacksPickerDir" } }
    end

    if item.file and not item.dir then
        local name = vim.fs.basename(item.file)
        if name:match("%.uproject$") or name:match("%.uplugin$") then
            -- Render: indent + json icon + filename, mimicking the default file formatter shape.
            local segments = default_file_format(item, picker)
            -- Replace the icon segment(s) with our JSON brace.
            -- Strategy: scan segments for the first {text, hl} whose hl matches an icon group,
            -- swap text/hl. If we can't identify it reliably, just prepend.
            return swap_or_prepend_icon(segments, JSON_BRACE_ICON, JSON_BRACE_HL)
        end
    end

    return default_file_format(item, picker)
end
```

> Implementation note: the safest path is to **prepend** the JSON icon as a leading segment after any tree-indent segments, rather than try to swap an existing devicon segment whose position is internal to Snacks. If duplication is visible, fall back to authoring our own segment list (indent + icon + name + status) and bypass `default_file_format` for the `.uproject`/`.uplugin` case.

> Glyph: prefer the Nerd Font `nf-md-code_json` (`󰘦`) or `nf-cod-json` (``) — pick whichever renders cleanly in the user's terminal during implementation. The exact codepoint is finalised by visual check, not spec.

### Success Criteria:

#### Automated Verification:
- [ ] `./scripts/test` passes.
- [ ] Stylua: `stylua --check lua/`

#### Manual Verification:
- [ ] `<Name>.uproject` at the Project label renders with a JSON brace icon (distinct from a generic file glyph).
- [ ] `<PluginName>.uplugin` inside each plugin folder renders with the same JSON brace icon.
- [ ] `.Target.cs` and `.Build.cs` files render with devicons' `.cs` glyph (no decoration / no arrow).
- [ ] Other file types (`.cpp`, `.h`, `.ini`, `.py`, etc.) render with their normal devicons — no regressions.
- [ ] No global devicons / mini.icons changes leak outside the `ue_tree` picker (other pickers and statuslines still show the original `.uproject`/`.uplugin` icon).

**Implementation Note**: Pause for manual confirmation before Phase 5.

---

## Phase 5: Documentation & tests

### Overview

Update README to reflect the new Solution view contract and `engine_dirs` scope; add `lua/tests/core/tree_spec.lua` covering the testable layers (filter predicates, sort assignment, target hoisting set, engine allow-list).

### Changes Required:

#### 1. README updates
**File**: `README.md`
**Locations**: lines 277 (view-modes paragraph) and lines 108-111 (config block)

Rewrite the Solution paragraph to describe:
- Curated Engine subtree (`Platforms / Plugins / Source / Config / Shaders`) regardless of `engine_dirs`.
- `.Target.cs` files appearing at the Project level next to `.uproject`.
- Plugin internals limited to `Source / Config / Resources / *.uplugin / Content/Python / Source/Python`.
- JSON brace icon for `.uproject` and `.uplugin`.
- Domain sort order at the Project level.

Add a clarifying note in the config-block annotation that `engine_dirs` applies only to the **Files** view.

#### 2. New test file
**File**: `lua/tests/core/tree_spec.lua` (new)

Test the predicate / pure-data parts of the implementation. Snacks integration is out of scope for unit tests (no harness); we cover:

- **Project-root filter**: given a list of relative paths, the filter accepts/rejects the right set:
  - Accept: `Plugins/...`, `Source/<file>` (non-`.Target.cs`), `Config/...`, `<Name>.uproject`.
  - Reject: `Content/...`, `Saved/...`, `Intermediate/...`, `Source/<Name>.Target.cs`, top-level miscellany.
- **Plugin-internal filter**: under `Plugins/X/`, accept `Source/...`, `Config/...`, `Resources/...`, `X.uplugin`, `Content/Python/foo.py`, `Source/Python/bar.py`. Reject `Intermediate/...`, `Binaries/...`, `Docs/...`, `Tests/...`, top-level `README.md`, `Content/foo.uasset`.
- **Engine allow-list filter**: top-level `Platforms`, `Plugins`, `Source`, `Config`, `Shaders` accepted; `Binaries`, `Build`, `DerivedDataCache`, `Saved`, `Documentation`, `Programs`, `Extras` rejected; grandchildren of accepted dirs always pass.
- **Domain sort prefixes**: `project_sort` returns `"1_..."` for Plugins, `"2_..."` for Source, `"3_..."` for Config, `"4_..."` for `.uproject`, and Target.cs hoisted items use `"5_..."`.
- **`.Target.cs` hoist set**: stub `target.discover` to return two records and verify the finder yields exactly those two virtual children with `parent == project_item`.

Expose the predicate functions via `_TEST` in `tree.lua` so the spec can call them in isolation:

```lua
if _TEST then
    M._project_filter = project_filter
    M._plugin_filter = plugin_filter
    M._engine_filter = engine_filter
    M._project_sort = project_sort
end
```

> Pattern reference: `lua/tests/core/target_spec.lua` (`_classify_target`, `_scan_directory`) and `lua/tests/core/finder_spec.lua` for `_TEST`-gated private exposure.

### Success Criteria:

#### Automated Verification:
- [ ] `./scripts/test` passes including new tree_spec.lua.
- [ ] Stylua: `stylua --check lua/`
- [ ] `tree_spec.lua` covers all four predicate sets and the sort scheme.

#### Manual Verification:
- [ ] README diagrams / behaviour text matches what `:UE tree solution` and `:UE tree files` actually do on a real project.
- [ ] No stale references to `engine_dirs` controlling Solution view remain in README, CLAUDE.md, or inline comments.

---

## Testing Strategy

### Unit Tests (in `tree_spec.lua`):
- Pure predicate functions (project filter, plugin filter, engine filter).
- Sort prefix assignment (`project_sort`).
- `.Target.cs` hoist by stubbing `target.discover` and verifying the yielded items.

### Integration Tests:
None automated. The Snacks picker is interactive and there is no headless harness in this repo. All UI-shape assertions are in the Manual Verification checklists per phase.

### Manual Testing Steps:
The four phase-end manual checklists collectively cover the end-to-end UX:
1. Open a project with a source-build engine + at least one plugin (e.g. plugin_dev with OhSnap).
2. `:UE tree solution` → walk the structure described in Desired End State.
3. `:UE tree files` → confirm unchanged scope behavior.
4. Toggle `tree.engine_dirs` at runtime via `:lua require("unrealium.core.config").set(...)` to confirm decoupling.
5. Open a `.uproject` and a `.uplugin` from the tree → confirm files open.
6. Test with reveal_on_open: open a deep file, then `:UE tree solution` → confirm reveal still works.

## Performance Considerations

- The Engine allow-list filter is evaluated once per yielded node during the lazy `Tree:get` walk — comparable cost to the existing `top_dir` check, no measurable change.
- `.Target.cs` hoisting calls `target.discover(project_root)` once per finder invocation. `target.discover` uses `vim.fs.find` over `Source/` only, with `limit = math.huge`. This is bounded by the size of `Source/`, which is small (game projects rarely have more than a few hundred files in `Source/`). Acceptable.
- The plugin-internals allow-list shifts a few string comparisons per node; same order of magnitude as today.
- No new I/O at picker-open time. No counts, no recursive scans of the engine.

## Migration Notes

`tree.engine_dirs` semantics narrow: from "applies to both views" to "applies to Files view only". Users who set `engine_dirs` to scope their Solution view down to `Source/` will see Solution view widen to `Engine/Platforms/Plugins/Source/Config/Shaders`. This is the intended behavior change per decision §1. Surface this in:
- README config-block annotation.
- The release commit message (this maps to a `feat!` Conventional Commit since it changes user-visible behavior).

## References

- Research file: `~/.claude/plans/given-this-research-users-jhayes-claude-clever-sketch.md`
- Prior research: `~/.claude/plans/research-how-the-custom-inherited-crescent.md`
- Solution finder: `lua/unrealium/core/ui/tree.lua:232-453`
- Files finder (sister): `lua/unrealium/core/ui/tree.lua:25-219`
- Engine root resolver: `lua/unrealium/modules/tree.lua:18-48`
- Target discovery: `lua/unrealium/core/target.lua`
- Plugin discovery: `lua/unrealium/core/finder.lua:332-342`
- Tree config defaults: `lua/unrealium/core/config.lua:73-80`
- Test pattern reference: `lua/tests/core/target_spec.lua`, `lua/tests/core/finder_spec.lua`
