--- Multi-root file tree: Snacks explorer backend + vim.ui.select fallback.
--- Shows Project and Engine as sibling roots in a unified sidebar.
--- Supports "files" (flat dual-root) and "solution" (development-focused) view modes.

local M = {}

local log = require("unrealium.core.log").get("tree")

local VIRTUAL_ROOT_PREFIX = "ue:tree:root:"

--- Top-level entries kept under the Engine root in solution view.
--- Everything else (Binaries, Build, DerivedDataCache, Saved, Documentation,
--- Programs, Extras, etc.) is hidden.
local ENGINE_ALLOW = {
	Platforms = true,
	Plugins = true,
	Source = true,
	Config = true,
	Shaders = true,
}

--- Plugin-internal directories shown under each plugin root in solution view.
--- Other top-level dirs (Intermediate, Binaries, Docs, Tests, etc.) are hidden.
--- `Content/Python/` is the only path under `Content/` that is preserved.
local PLUGIN_ALLOW_DIR = { Source = true, Config = true, Resources = true }

--- Sort prefixes for top-level Project children (Rider-style domain order).
--- `.uproject` uses prefix "4_", hoisted `.Target.cs` use "5_".
local PROJECT_TOP_SORT = { Plugins = "1", Source = "2", Config = "3" }

--- Decide whether a node directly under the project root (excluding `Plugins/`)
--- should be rendered in solution view. `.Target.cs` files under `Source/` are
--- excluded because they are hoisted as virtual children of the Project label.
---@param segments string[] path segments relative to project root
---@param basename string basename of the node
---@return boolean keep
local function project_top_filter(segments, basename)
	local top = segments[1]
	if not top or top == "" then
		return false
	end

	if top == "Source" then
		if #segments == 2 and segments[2]:match("%.Target%.cs$") then
			return false
		end
		return true
	end

	if top == "Config" then
		return true
	end

	if #segments == 1 and basename:match("%.uproject$") then
		return true
	end

	return false
end

--- Decide whether a path inside a plugin's root should be shown.
--- `sub_segments` is the path relative to the plugin's root directory.
---@param sub_segments string[]
---@return boolean keep
local function plugin_internal_filter(sub_segments)
	if #sub_segments == 0 then
		return false
	end
	local top = sub_segments[1]
	if PLUGIN_ALLOW_DIR[top] then
		return true
	end
	if top == "Content" and sub_segments[2] == "Python" then
		return true
	end
	if #sub_segments == 1 and top:match("%.uplugin$") then
		return true
	end
	return false
end

--- Decide whether a node under the engine root should be shown in solution view.
--- Only the top-level segment is checked; descendants of an allowed top-level
--- entry pass through unfiltered (so users can still drill into `Source/Runtime`).
---@param segments string[] path segments relative to engine root
---@return boolean keep
local function engine_top_filter(segments)
	local top = segments[1]
	if not top or top == "" then
		return false
	end
	return ENGINE_ALLOW[top] == true
end

--- Compute the explicit sort prefix for a top-level Project child.
--- Grandchildren return `nil` and inherit Snacks' default sibling order.
---@param segments string[] path segments relative to project root
---@param basename string basename of the node
---@return string|nil sort_value
local function project_sort(segments, basename)
	if #segments ~= 1 then
		return nil
	end
	local top = segments[1]
	if PROJECT_TOP_SORT[top] then
		return PROJECT_TOP_SORT[top] .. "_" .. top
	end
	if basename:match("%.uproject$") then
		return "4_" .. basename
	end
	return nil
end

--- Check if Snacks picker is available.
---@return boolean
local function has_snacks()
	local ok = pcall(require, "snacks")
	return ok
end

-- ---------------------------------------------------------------------------
-- Snacks backend — files view (existing dual-root)
-- ---------------------------------------------------------------------------

--- Build a custom finder that yields items from both project and engine roots.
---@param project_root string
---@param engine_root string|nil
---@param tree_opts table tree config settings
---@return fun(opts: table, ctx: table): fun(cb: fun(item: table))
local function make_finder(project_root, engine_root, tree_opts)
	local Tree = require("snacks.explorer.tree")
	local ExplorerActions = require("snacks.explorer.actions")
	local first_call = true

	return function(opts, ctx)
		local state = require("snacks.picker.source.explorer").get_state(ctx.picker)

		ctx.picker.matcher.opts.keep_parents = false
		if state:setup(ctx) then
			ctx.picker.matcher.opts.keep_parents = true
			return require("snacks.picker.source.explorer").search(opts, ctx)
		end

		local on_find = state.on_find
		state.on_find = nil

		-- First call: dual-root setup and reveal_on_open
		if first_call then
			first_call = false

			-- State.new only refreshed picker:cwd(); also refresh the engine root
			if engine_root then
				Tree:refresh(engine_root)
			end

			if tree_opts.reveal_on_open then
				if not on_find then
					-- follow_file is false; create our own on_find for initial reveal
					local buf = vim.api.nvim_win_get_buf(ctx.picker.main)
					local buf_file = vim.fs.normalize(vim.api.nvim_buf_get_name(buf))
					if buf_file ~= "" and vim.uv.fs_stat(buf_file) then
						local in_root = vim.startswith(buf_file, project_root)
							or (engine_root and vim.startswith(buf_file, engine_root))
						if in_root then
							Tree:open(buf_file)
							local r = ctx.picker:ref()
							on_find = function()
								local p = r.value
								if p and not p.closed then
									ExplorerActions.update(p, { target = buf_file })
								end
							end
						end
					end
				end
				-- else: on_find from State.new already handles initial reveal
			else
				-- reveal_on_open is false: suppress any initial reveal from follow_file
				on_find = nil
			end
		end

		-- Git status for both roots
		if opts.git_status then
			local git = require("snacks.explorer.git")
			local function on_git_update()
				if ctx.picker.closed then
					return
				end
				ctx.picker.list:set_target()
				ctx.picker:find({ on_done = on_find })
			end
			git.update(project_root, {
				untracked = opts.git_untracked,
				on_update = on_git_update,
			})
			if engine_root then
				git.update(engine_root, {
					untracked = opts.git_untracked,
					on_update = on_git_update,
				})
			end
		end

		-- Diagnostics for both roots
		if opts.diagnostics then
			local diag = require("snacks.explorer.diagnostics")
			diag.update(project_root)
			if engine_root then
				diag.update(engine_root)
			end
		end

		local filter_opts = {
			hidden = tree_opts.show_hidden,
			ignored = tree_opts.show_ignored,
			exclude = opts.exclude,
			include = opts.include,
		}

		return function(cb)
			if on_find then
				assert(ctx.picker.matcher.task:running())
				ctx.picker.matcher.task:on("done", vim.schedule_wrap(on_find))
			end

			-- Master root: synthetic ID avoids path collision with the real
			-- project root item rendered as its child.
			local project_name = vim.fn.fnamemodify(project_root, ":t")
			local virtual_root_id = VIRTUAL_ROOT_PREFIX .. project_root
			---@type snacks.picker.explorer.Item
			local virtual_root = {
				file = virtual_root_id,
				dir = true,
				open = true,
				text = virtual_root_id,
				sort = "",
				label = project_name,
				is_ue_root_label = true,
			}
			cb(virtual_root)

			-- items lookup for parent chaining
			local items = {} ---@type table<string, snacks.picker.explorer.Item>
			local last = {} ---@type table<snacks.picker.explorer.Node, snacks.picker.explorer.Item>

			--- Yield a root label item and walk its tree.
			---@param root_path string
			---@param label string
			---@param is_last boolean
			---@param start_open boolean
			local function yield_root(root_path, label, is_last, start_open)
				-- Ensure the tree node exists and has the right open state
				local root_node = Tree:find(root_path)
				if not root_node then
					return
				end
				if start_open then
					root_node.open = true
				end

				-- Create the root label item
				---@type snacks.picker.explorer.Item
				local root_item = {
					file = root_path,
					dir = true,
					open = root_node.open,
					text = root_path,
					parent = virtual_root,
					last = is_last,
					sort = is_last and "#" .. label or "!" .. label,
					hidden = false,
					ignored = false,
					type = "directory",
					label = label,
					is_ue_root_label = true,
				}
				items[root_path] = root_item
				cb(root_item)

				-- Walk the tree from this root
				Tree:get(root_path, function(node)
					-- Skip the root node itself (already yielded as label)
					if node.path == root_path then
						return
					end

					local parent = node.parent and items[node.parent.path] or root_item
					local status = node.status
					if not status and parent and parent.dir_status then
						status = parent.dir_status
					end

					local item = {
						file = node.path,
						dir = node.dir,
						open = node.open,
						dir_status = node.dir_status or (parent and parent.dir_status),
						text = node.path,
						parent = parent,
						hidden = node.hidden,
						ignored = node.ignored,
						status = (not node.dir or not node.open or opts.git_status_open) and status or nil,
						last = true,
						type = node.type,
						severity = (not node.dir or not node.open or opts.diagnostics_open) and node.severity or nil,
					}

					if last[node.parent] then
						last[node.parent].last = false
					end
					last[node.parent] = item

					items[node.path] = item
					cb(item)
				end, filter_opts)
			end

			-- Project root: expanded by default
			yield_root(project_root, "Project", engine_root == nil, true)

			-- Engine root: collapsed by default (lazy expansion)
			if engine_root then
				yield_root(engine_root, "Engine", true, false)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Snacks backend — solution view
-- ---------------------------------------------------------------------------

--- Build a finder for solution view that reorganizes the tree into a
--- development-focused hierarchy: project shows Config/, Source/, Plugins/,
--- and .uproject; engine is shown as-is.
---@param project_root string
---@param engine_root string|nil
---@param tree_opts table tree config settings
---@return fun(opts: table, ctx: table): fun(cb: fun(item: table))
local function make_solution_finder(project_root, engine_root, tree_opts)
	local Tree = require("snacks.explorer.tree")
	local ExplorerActions = require("snacks.explorer.actions")
	local first_call = true

	return function(opts, ctx)
		local state = require("snacks.picker.source.explorer").get_state(ctx.picker)

		ctx.picker.matcher.opts.keep_parents = false
		if state:setup(ctx) then
			ctx.picker.matcher.opts.keep_parents = true
			return require("snacks.picker.source.explorer").search(opts, ctx)
		end

		local on_find = state.on_find
		state.on_find = nil

		-- First call: setup and reveal_on_open
		if first_call then
			first_call = false

			if engine_root then
				Tree:refresh(engine_root)
			end

			if tree_opts.reveal_on_open then
				if not on_find then
					local buf = vim.api.nvim_win_get_buf(ctx.picker.main)
					local buf_file = vim.fs.normalize(vim.api.nvim_buf_get_name(buf))
					if buf_file ~= "" and vim.uv.fs_stat(buf_file) then
						local in_root = vim.startswith(buf_file, project_root)
							or (engine_root and vim.startswith(buf_file, engine_root))
						if in_root then
							Tree:open(buf_file)
							local r = ctx.picker:ref()
							on_find = function()
								local p = r.value
								if p and not p.closed then
									ExplorerActions.update(p, { target = buf_file })
								end
							end
						end
					end
				end
			else
				on_find = nil
			end
		end

		-- Git status for all roots
		if opts.git_status then
			local git = require("snacks.explorer.git")
			local function on_git_update()
				if ctx.picker.closed then
					return
				end
				ctx.picker.list:set_target()
				ctx.picker:find({ on_done = on_find })
			end
			git.update(project_root, {
				untracked = opts.git_untracked,
				on_update = on_git_update,
			})
			if engine_root then
				git.update(engine_root, {
					untracked = opts.git_untracked,
					on_update = on_git_update,
				})
			end
		end

		-- Diagnostics
		if opts.diagnostics then
			local diag = require("snacks.explorer.diagnostics")
			diag.update(project_root)
			if engine_root then
				diag.update(engine_root)
			end
		end

		local filter_opts = {
			hidden = tree_opts.show_hidden,
			ignored = tree_opts.show_ignored,
			exclude = opts.exclude,
			include = opts.include,
		}

		return function(cb)
			if on_find then
				assert(ctx.picker.matcher.task:running())
				ctx.picker.matcher.task:on("done", vim.schedule_wrap(on_find))
			end

			-- Master root: synthetic ID avoids path collision with the real
			-- project root item rendered as its child.
			local project_name = vim.fn.fnamemodify(project_root, ":t")
			local virtual_root_id = VIRTUAL_ROOT_PREFIX .. project_root
			---@type snacks.picker.explorer.Item
			local virtual_root = {
				file = virtual_root_id,
				dir = true,
				open = true,
				text = virtual_root_id,
				sort = "",
				label = project_name,
				is_ue_root_label = true,
			}
			cb(virtual_root)

			local items = {} ---@type table<string, snacks.picker.explorer.Item>
			local last = {} ---@type table<snacks.picker.explorer.Node, snacks.picker.explorer.Item>

			-- Compute sort indices: project first, engine last
			local has_engine = engine_root ~= nil
			local root_idx = 0

			--- Helper: create a root-level label item.
			---@param root_path string
			---@param label string
			---@param is_last boolean
			---@param start_open boolean
			---@return snacks.picker.explorer.Item
			local function make_root_item(root_path, label, is_last, start_open)
				local root_node = Tree:find(root_path)
				if root_node and start_open then
					root_node.open = true
				end

				root_idx = root_idx + 1
				local sort_prefix = string.format("%04d", root_idx)

				---@type snacks.picker.explorer.Item
				local root_item = {
					file = root_path,
					dir = true,
					open = root_node and root_node.open or false,
					text = root_path,
					parent = virtual_root,
					last = is_last,
					sort = sort_prefix .. label,
					hidden = false,
					ignored = false,
					type = "directory",
					label = label,
					is_ue_root_label = true,
				}
				items[root_path] = root_item
				cb(root_item)
				return root_item
			end

			--- Helper: yield a tree node as an item under a given fallback parent.
			---@param node table snacks explorer tree node
			---@param fallback_parent snacks.picker.explorer.Item
			---@param sort_override string|nil explicit sort key (top-level project domain order)
			local function yield_node(node, fallback_parent, sort_override)
				local parent = node.parent and items[node.parent.path] or fallback_parent
				local status = node.status
				if not status and parent and parent.dir_status then
					status = parent.dir_status
				end

				local item = {
					file = node.path,
					dir = node.dir,
					open = node.open,
					dir_status = node.dir_status or (parent and parent.dir_status),
					text = node.path,
					parent = parent,
					hidden = node.hidden,
					ignored = node.ignored,
					status = (not node.dir or not node.open or opts.git_status_open) and status or nil,
					last = true,
					type = node.type,
					severity = (not node.dir or not node.open or opts.diagnostics_open) and node.severity or nil,
					sort = sort_override,
				}

				if last[node.parent] then
					last[node.parent].last = false
				end
				last[node.parent] = item

				items[node.path] = item
				cb(item)
			end

			-- 1. Project root (Config/, Source/, Plugins/, and .uproject shown)
			local project_is_last = not has_engine
			local project_item = make_root_item(project_root, "Project", project_is_last, true)

			-- Discover plugin roots once so the plugin filter is structure-aware
			-- (handles publisher-grouped layouts like Plugins/Epic/MyPlugin/).
			local plugins_dir = vim.fs.joinpath(project_root, "Plugins")
			local discover_plugins = require("unrealium.core.finder").discover_plugins
			local plugin_paths_array = {}
			local plugin_paths_set = {}
			for _, p in ipairs(discover_plugins(project_root)) do
				table.insert(plugin_paths_array, p.path)
				plugin_paths_set[p.path] = true
			end

			Tree:get(project_root, function(node)
				if node.path == project_root then
					return
				end

				local rel = node.path:sub(#project_root + 2) -- strip project_root + "/"
				local segments = vim.split(rel, "/", { plain = true })
				local top = segments[1]
				local basename = vim.fs.basename(node.path)

				if top == "Plugins" then
					-- The Plugins/ directory itself
					if node.path == plugins_dir then
						yield_node(node, project_item, project_sort(segments, basename))
						return
					end
					-- A plugin root (handles direct + nested publisher layouts)
					if plugin_paths_set[node.path] then
						yield_node(node, project_item)
						return
					end
					-- An ancestor of a plugin root (e.g. publisher group dir)
					for _, p in ipairs(plugin_paths_array) do
						if vim.startswith(p, node.path .. "/") then
							yield_node(node, project_item)
							return
						end
					end
					-- A path inside a plugin root: apply the internal allow-list
					for _, p in ipairs(plugin_paths_array) do
						if vim.startswith(node.path, p .. "/") then
							local sub_rel = node.path:sub(#p + 2)
							local sub_segments = vim.split(sub_rel, "/", { plain = true })
							if plugin_internal_filter(sub_segments) then
								yield_node(node, project_item)
							end
							return
						end
					end
					-- Orphan file under Plugins/ not inside any plugin: drop
					return
				end

				if project_top_filter(segments, basename) then
					yield_node(node, project_item, project_sort(segments, basename))
				end
			end, filter_opts)

			-- Hoist .Target.cs files under the Project label as virtual children.
			-- These are excluded from the Source/ walk above to avoid duplicates.
			local targets = require("unrealium.core.target").discover(project_root)
			for _, t in ipairs(targets) do
				local target_basename = vim.fs.basename(t.file)
				---@type snacks.picker.explorer.Item
				local target_item = {
					file = t.file,
					dir = false,
					text = t.file,
					parent = project_item,
					last = true,
					type = "file",
					sort = "5_" .. target_basename,
				}
				items[t.file] = target_item
				cb(target_item)
			end

			-- 2. Engine root: curated allow-list at the top level only.
			-- Children below the top level pass through unfiltered, so users
			-- can drill into Engine/Source/Runtime/Core/... as before.
			if engine_root then
				local engine_item = make_root_item(engine_root, "Engine", true, false)

				Tree:get(engine_root, function(node)
					if node.path == engine_root then
						return
					end
					local rel = node.path:sub(#engine_root + 2)
					local segments = vim.split(rel, "/", { plain = true })
					if not engine_top_filter(segments) then
						return
					end
					yield_node(node, engine_item)
				end, filter_opts)
			end
		end
	end
end

--- Build action overrides for the multi-root tree.
---@param project_root string
---@param engine_root string|nil
---@param allow_engine_mods boolean
---@return table<string, function>
local function make_actions(project_root, engine_root, allow_engine_mods)
	local Tree = require("snacks.explorer.tree")
	local ExplorerActions = require("snacks.explorer.actions")

	--- Guard that blocks mutation actions on engine files.
	---@param action_fn function
	---@return function
	local function engine_guard(action_fn)
		return function(picker, item, action)
			if not allow_engine_mods and item and item.file and engine_root then
				if vim.startswith(item.file, engine_root) then
					vim.notify(
						"[unrealium] Engine is read-only (set engine.allow_modifications = true)",
						vim.log.levels.WARN
					)
					return
				end
			end
			return action_fn(picker, item, action)
		end
	end

	local actions = {}

	-- explorer_up: no-op at virtual root level
	actions.explorer_up = function(picker)
		vim.notify("[unrealium] Already at top level", vim.log.levels.INFO)
	end

	-- explorer_focus: collapse all, expand only the root containing current item
	actions.explorer_focus = function(picker, item)
		if not item or not item.file or item.file == "" then
			return
		end
		-- Determine which root this item belongs to
		local target_root
		if vim.startswith(item.file, project_root) then
			target_root = project_root
		elseif engine_root and vim.startswith(item.file, engine_root) then
			target_root = engine_root
		end
		if target_root then
			-- Close all in both roots, then open target
			Tree:close_all(project_root)
			if engine_root then
				Tree:close_all(engine_root)
			end
			Tree:open(item.file)
			ExplorerActions.update(picker, { refresh = true })
		end
	end

	-- explorer_update: refresh both roots
	actions.explorer_update = function(picker)
		Tree:refresh(project_root)
		if engine_root then
			Tree:refresh(engine_root)
		end
		ExplorerActions.update(picker)
	end

	-- explorer_close_all: close all in both roots
	actions.explorer_close_all = function(picker)
		Tree:close_all(project_root)
		if engine_root then
			Tree:close_all(engine_root)
		end
		ExplorerActions.update(picker, { refresh = true })
	end

	-- Guard mutation actions on engine files
	actions.explorer_add = engine_guard(ExplorerActions.actions.explorer_add)
	actions.explorer_del = engine_guard(ExplorerActions.actions.explorer_del)
	actions.explorer_rename = engine_guard(ExplorerActions.actions.explorer_rename)
	actions.explorer_move = engine_guard(ExplorerActions.actions.explorer_move)
	actions.explorer_copy = engine_guard(ExplorerActions.actions.explorer_copy)
	actions.explorer_paste = engine_guard(ExplorerActions.actions.explorer_paste)

	return actions
end

--- JSON brace glyph (Nerd Font: nf-cod-json, U+EB0F) used for `.uproject` /
--- `.uplugin`. Encoded as raw UTF-8 bytes to survive copy/paste round-trips.
local JSON_BRACE_ICON = "\xee\xac\x8f"
local JSON_BRACE_HL = "SnacksPickerIcon"

--- Replace the icon segment in a Snacks `file` formatter result. The icon is
--- the first segment marked `virtual = true` whose text contains a non-space
--- character (Snacks adds the file glyph that way at `picker.format.filename`).
--- Width is preserved by re-aligning to the picker's `formatters.file.icon_width`.
---@param segments table[]
---@param glyph string
---@param hl string
---@param picker table
local function swap_icon_segment(segments, glyph, hl, picker)
	local picker_util = require("snacks.picker.util")
	local width = (picker.opts.formatters.file or {}).icon_width or 2
	for _, seg in ipairs(segments) do
		if seg.virtual and type(seg[1]) == "string" and seg[1]:match("%S") then
			seg[1] = picker_util.align(glyph, width)
			seg[2] = hl
			return
		end
	end
end

--- Build the tree picker's format callback. Renders root-label items as
--- their label only (no path basename, no icon); renders `.uproject` and
--- `.uplugin` files with a JSON brace icon (picker-scoped, no global devicon
--- registration); everything else uses Snacks' default file formatter.
---@return fun(item: table, picker: table): table[]
local function make_format_item()
	local snacks_format = require("snacks.picker.format")

	return function(item, picker)
		if item.is_ue_root_label then
			local ret = {}
			if item.parent then
				vim.list_extend(ret, snacks_format.tree(item, picker))
			end
			ret[#ret + 1] = { item.label or "", "SnacksPickerDir" }
			return ret
		end

		local segments = snacks_format.file(item, picker)

		if item.file and not item.dir then
			local name = vim.fs.basename(item.file)
			if name:match("%.uproject$") or name:match("%.uplugin$") then
				swap_icon_segment(segments, JSON_BRACE_ICON, JSON_BRACE_HL, picker)
			end
		end

		return segments
	end
end

--- Open the Snacks multi-root tree picker.
---@param project_root string
---@param engine_root string|nil
---@param allow_engine_mods boolean
---@param tree_opts table
function M.open_snacks(project_root, engine_root, allow_engine_mods, tree_opts)
	local Snacks = require("snacks")
	local ExplorerSource = require("snacks.picker.source.explorer")

	local view = tree_opts.view or "files"
	local finder
	if view == "solution" then
		finder = make_solution_finder(project_root, engine_root, tree_opts)
	else
		finder = make_finder(project_root, engine_root, tree_opts)
	end
	local actions = make_actions(project_root, engine_root, allow_engine_mods)

	local picker_instance = Snacks.picker({
		source = "ue_tree",
		title = "UE Tree",
		finder = finder,
		format = make_format_item(),
		sort = { fields = { "sort" } },
		supports_live = true,
		tree = true,
		watch = true,
		diagnostics = true,
		diagnostics_open = false,
		git_status = true,
		git_status_open = false,
		git_untracked = true,
		follow_file = tree_opts.follow_file,
		focus = "list",
		auto_close = false,
		jump = { close = false },
		layout = { preset = "sidebar", preview = false },
		formatters = {
			file = { filename_only = true },
			severity = { pos = "right" },
		},
		matcher = { sort_empty = false, fuzzy = false },
		config = function(opts)
			return ExplorerSource.setup(opts)
		end,
		actions = vim.tbl_extend("force", ExplorerSource.actions or {}, actions),
		win = {
			list = {
				keys = {
					["<BS>"] = "explorer_up",
					["l"] = "confirm",
					["h"] = "explorer_close",
					["a"] = "explorer_add",
					["d"] = "explorer_del",
					["r"] = "explorer_rename",
					["c"] = "explorer_copy",
					["m"] = "explorer_move",
					["o"] = "explorer_open",
					["P"] = "toggle_preview",
					["y"] = { "explorer_yank", mode = { "n", "x" } },
					["p"] = "explorer_paste",
					["u"] = "explorer_update",
					["<c-c>"] = "tcd",
					["<leader>/"] = "picker_grep",
					["<c-t>"] = "terminal",
					["."] = "explorer_focus",
					["I"] = "toggle_ignored",
					["H"] = "toggle_hidden",
					["Z"] = "explorer_close_all",
					["]g"] = "explorer_git_next",
					["[g"] = "explorer_git_prev",
					["]d"] = "explorer_diagnostic_next",
					["[d"] = "explorer_diagnostic_prev",
					["]w"] = "explorer_warn_next",
					["[w"] = "explorer_warn_prev",
					["]e"] = "explorer_error_next",
					["[e"] = "explorer_error_prev",
				},
			},
		},
	})

	-- Tag picker with view mode for toggle detection
	if picker_instance then
		picker_instance._ue_view = view
	end

	return picker_instance
end

--- Toggle the Snacks tree picker (open/close).
--- If an existing picker has a different view mode, close it and reopen with the new view.
---@param project_root string
---@param engine_root string|nil
---@param allow_engine_mods boolean
---@param tree_opts table
function M.toggle_snacks(project_root, engine_root, allow_engine_mods, tree_opts)
	local Snacks = require("snacks")

	-- Close any symbols picker when switching to file/solution view
	local symbols_pickers = Snacks.picker.get({ source = "ue_symbols" })
	for _, p in ipairs(symbols_pickers) do
		p:close()
	end

	local existing = Snacks.picker.get({ source = "ue_tree" })
	if #existing > 0 then
		local current_view = existing[1]._ue_view
		local requested_view = tree_opts.view or "files"
		if current_view ~= requested_view then
			-- Different view mode: close and reopen
			existing[1]:close()
			M.open_snacks(project_root, engine_root, allow_engine_mods, tree_opts)
		else
			-- Same view mode: normal toggle (close)
			existing[1]:close()
		end
	else
		M.open_snacks(project_root, engine_root, allow_engine_mods, tree_opts)
	end
end

--- Close any open Snacks tree or symbols picker.
function M.close_snacks()
	local ok, Snacks = pcall(require, "snacks")
	if not ok then
		return
	end
	for _, source in ipairs({ "ue_tree", "ue_symbols" }) do
		local existing = Snacks.picker.get({ source = source })
		for _, picker in ipairs(existing) do
			picker:close()
		end
	end
end

--- Focus the Snacks tree picker.
---@param project_root string
---@param engine_root string|nil
---@param allow_engine_mods boolean
---@param tree_opts table
function M.focus_snacks(project_root, engine_root, allow_engine_mods, tree_opts)
	local Snacks = require("snacks")

	-- Focus whichever UE picker is already open
	local tree_pickers = Snacks.picker.get({ source = "ue_tree" })
	if #tree_pickers > 0 then
		tree_pickers[1]:focus()
		return
	end
	local symbol_pickers = Snacks.picker.get({ source = "ue_symbols" })
	if #symbol_pickers > 0 then
		symbol_pickers[1]:focus()
		return
	end

	M.open_snacks(project_root, engine_root, allow_engine_mods, tree_opts)
end

--- Reveal the current buffer's file in the tree.
---@param project_root string
---@param engine_root string|nil
---@param allow_engine_mods boolean
---@param tree_opts table
function M.reveal_snacks(project_root, engine_root, allow_engine_mods, tree_opts)
	local Snacks = require("snacks")
	local ExplorerActions = require("snacks.explorer.actions")

	local existing = Snacks.picker.get({ source = "ue_tree" })
	local picker
	if #existing > 0 then
		picker = existing[1]
	else
		picker = M.open_snacks(project_root, engine_root, allow_engine_mods, tree_opts)
	end

	if picker then
		local file = vim.api.nvim_buf_get_name(0)
		if file ~= "" then
			ExplorerActions.update(picker, { target = file })
		end
	end
end

-- ---------------------------------------------------------------------------
-- Snacks backend — symbols view
-- ---------------------------------------------------------------------------

--- Convert a hierarchical symbol tree into flat items for the Snacks tree picker.
---@param symbols UnrealiumSymbol[]
---@param bufnr integer current buffer (default jump target)
---@return table[] items
local function flatten_symbols(symbols, bufnr)
	local items = {}

	local function flatten(syms, parent_item, depth)
		for i, sym in ipairs(syms) do
			local is_last = (i == #syms)
			local item = {
				text = sym.name,
				name = sym.name,
				kind = sym.kind,
				pos = sym.pos,
				end_pos = sym.end_pos,
				tree = true,
				depth = depth,
				parent = parent_item,
				last = is_last,
			}

			-- Jump target: companion file or current buffer
			if sym.source_file then
				item.file = sym.source_file
			else
				item.buf = bufnr
			end

			table.insert(items, item)

			if sym.children and #sym.children > 0 then
				flatten(sym.children, item, depth + 1)
			end
		end
	end

	flatten(symbols, nil, 0)
	return items
end

--- Build a finder function for the symbols picker.
---@param tree_opts table
---@return fun(opts: table, ctx: table): fun(cb: fun(item: table))
local function make_symbols_finder(tree_opts)
	return function(opts, ctx)
		local main_win = ctx.picker.main
		if not main_win or not vim.api.nvim_win_is_valid(main_win) then
			return function(cb) end
		end

		local bufnr = vim.api.nvim_win_get_buf(main_win)
		local ft = vim.bo[bufnr].filetype
		if ft ~= "cpp" and ft ~= "c" then
			return function(cb) end
		end

		local ts_symbols = require("unrealium.core.ts_symbols")
		local symbols = ts_symbols.get_symbols_for_buffer(bufnr)

		return function(cb)
			local items = flatten_symbols(symbols, bufnr)
			for _, item in ipairs(items) do
				cb(item)
			end
		end
	end
end

--- Open the Snacks symbols picker.
---@param tree_opts table
---@return table|nil picker
function M.open_symbols_snacks(tree_opts)
	local Snacks = require("snacks")

	local picker = Snacks.picker({
		source = "ue_symbols",
		title = "UE Symbols",
		finder = make_symbols_finder(tree_opts),
		format = "lsp_symbol",
		tree = true,
		focus = "list",
		auto_close = false,
		jump = { close = false },
		layout = { preset = "sidebar", preview = true },
		matcher = { sort_empty = false, fuzzy = false },
		win = {
			list = {
				keys = {
					["l"] = "confirm",
					["h"] = "close",
				},
			},
		},
	})

	if picker then
		picker._ue_view = "symbols"

		-- Auto-refresh on buffer switch and save
		local group = vim.api.nvim_create_augroup("unrealium_symbols_refresh", { clear = true })
		vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
			group = group,
			pattern = { "*.cpp", "*.h", "*.hpp", "*.c" },
			callback = function()
				if picker.closed then
					pcall(vim.api.nvim_del_augroup_by_id, group)
					return true
				end
				picker:find()
			end,
		})
	end

	return picker
end

--- Toggle the Snacks symbols picker.
--- Closes any file/solution tree picker when switching views.
---@param tree_opts table
function M.toggle_symbols_snacks(tree_opts)
	local Snacks = require("snacks")

	-- Close any existing file/solution tree (different view)
	local file_tree = Snacks.picker.get({ source = "ue_tree" })
	for _, p in ipairs(file_tree) do
		p:close()
	end

	-- Toggle symbols picker
	local existing = Snacks.picker.get({ source = "ue_symbols" })
	if #existing > 0 then
		existing[1]:close()
	else
		M.open_symbols_snacks(tree_opts)
	end
end

--- Focus the Snacks symbols picker, opening it if not already open.
---@param tree_opts table
function M.focus_symbols_snacks(tree_opts)
	local Snacks = require("snacks")
	local existing = Snacks.picker.get({ source = "ue_symbols" })
	if #existing > 0 then
		existing[1]:focus()
	else
		M.open_symbols_snacks(tree_opts)
	end
end

--- Open a symbols fallback using vim.ui.select.
---@param tree_opts table
function M.open_symbols_fallback(tree_opts)
	vim.notify("[unrealium] Install snacks.nvim for a richer symbols experience", vim.log.levels.INFO, { once = true })

	local bufnr = vim.api.nvim_get_current_buf()
	local ft = vim.bo[bufnr].filetype
	if ft ~= "cpp" and ft ~= "c" then
		vim.notify("[unrealium] Current buffer is not C/C++", vim.log.levels.WARN)
		return
	end

	local ts_symbols = require("unrealium.core.ts_symbols")
	local symbols = ts_symbols.get_symbols_for_buffer(bufnr)

	local entries = {}
	local function collect(syms, indent)
		for _, sym in ipairs(syms) do
			local prefix = string.rep("  ", indent)
			local label = prefix .. sym.kind .. ": " .. sym.name
			if sym.ue_macro then
				label = label .. " [" .. sym.ue_macro .. "]"
			end
			table.insert(entries, { label = label, sym = sym })
			if sym.children then
				collect(sym.children, indent + 1)
			end
		end
	end
	collect(symbols, 0)

	vim.ui.select(entries, {
		prompt = "UE Symbols",
		format_item = function(item)
			return item.label
		end,
	}, function(choice)
		if not choice then
			return
		end
		local sym = choice.sym
		if sym.source_file then
			vim.cmd("edit " .. vim.fn.fnameescape(sym.source_file))
		end
		vim.api.nvim_win_set_cursor(0, { sym.pos[1], sym.pos[2] })
	end)
end

-- ---------------------------------------------------------------------------
-- vim.ui.select fallback
-- ---------------------------------------------------------------------------

--- Recursive directory browser using vim.ui.select.
---@param dir string directory to browse
---@param label string display label
local function browse_dir(dir, label)
	local entries = {}
	local handle = vim.uv.fs_scandir(dir)
	if not handle then
		vim.notify("[unrealium] Cannot read directory: " .. dir, vim.log.levels.ERROR)
		return
	end

	local dirs_list = {}
	local files_list = {}

	while true do
		local name, typ = vim.uv.fs_scandir_next(handle)
		if not name then
			break
		end
		if typ == "directory" then
			table.insert(dirs_list, name .. "/")
		else
			table.insert(files_list, name)
		end
	end

	table.sort(dirs_list)
	table.sort(files_list)

	-- ".." to go up
	table.insert(entries, "..")
	vim.list_extend(entries, dirs_list)
	vim.list_extend(entries, files_list)

	vim.ui.select(entries, { prompt = label .. " > " }, function(choice)
		if not choice then
			return
		end
		if choice == ".." then
			local parent = vim.fn.fnamemodify(dir, ":h")
			if parent ~= dir then
				browse_dir(parent, label)
			end
		elseif choice:sub(-1) == "/" then
			browse_dir(vim.fs.joinpath(dir, choice:sub(1, -2)), label)
		else
			vim.cmd("edit " .. vim.fn.fnameescape(vim.fs.joinpath(dir, choice)))
		end
	end)
end

--- Open the fallback tree (vim.ui.select root picker).
---@param project_root string
---@param engine_root string|nil
---@param tree_opts? table
function M.open_fallback(project_root, engine_root, tree_opts)
	vim.notify(
		"[unrealium] Install snacks.nvim for a richer file tree experience",
		vim.log.levels.INFO,
		{ once = true }
	)

	local choices = { "Project: " .. vim.fn.fnamemodify(project_root, ":t") }
	local paths = { project_root }

	-- In solution mode with fallback, show plugins as separate choices
	if tree_opts and tree_opts.view == "solution" and tree_opts.plugins then
		for _, plugin in ipairs(tree_opts.plugins) do
			table.insert(choices, "Plugin: " .. plugin.name)
			table.insert(paths, plugin.path)
		end
	end

	if engine_root then
		table.insert(choices, "Engine: " .. engine_root)
		table.insert(paths, engine_root)
	end

	vim.ui.select(choices, { prompt = "Select root:" }, function(_, idx)
		if not idx then
			return
		end
		browse_dir(paths[idx], choices[idx])
	end)
end

-- ---------------------------------------------------------------------------
-- Public dispatch API
-- ---------------------------------------------------------------------------

--- Execute a tree action using the best available backend.
---@param action string "toggle"|"open"|"close"|"focus"|"reveal"
---@param project_root string
---@param engine_root string|nil
---@param allow_engine_mods boolean
---@param tree_opts table
function M.execute(action, project_root, engine_root, allow_engine_mods, tree_opts)
	local view = tree_opts and tree_opts.view or "files"

	-- Symbols view: separate picker, doesn't need project/engine roots
	if view == "symbols" then
		if has_snacks() then
			if action == "toggle" then
				M.toggle_symbols_snacks(tree_opts)
			elseif action == "open" then
				M.close_snacks()
				M.open_symbols_snacks(tree_opts)
			elseif action == "close" then
				M.close_snacks()
			elseif action == "focus" then
				M.focus_symbols_snacks(tree_opts)
			else
				log.warn("Unknown tree action: %s", action)
			end
		else
			if action == "close" then
				return
			end
			M.open_symbols_fallback(tree_opts)
		end
		return
	end

	-- File/solution views
	if has_snacks() then
		if action == "toggle" then
			M.toggle_snacks(project_root, engine_root, allow_engine_mods, tree_opts)
		elseif action == "open" then
			M.open_snacks(project_root, engine_root, allow_engine_mods, tree_opts)
		elseif action == "close" then
			M.close_snacks()
		elseif action == "focus" then
			M.focus_snacks(project_root, engine_root, allow_engine_mods, tree_opts)
		elseif action == "reveal" then
			M.reveal_snacks(project_root, engine_root, allow_engine_mods, tree_opts)
		else
			log.warn("Unknown tree action: %s", action)
		end
	else
		-- Fallback only supports open
		if action == "close" then
			return
		end
		M.open_fallback(project_root, engine_root, tree_opts)
	end
end

if _TEST then
	M._make_finder = make_finder
	M._make_solution_finder = make_solution_finder
	M._make_symbols_finder = make_symbols_finder
	M._make_actions = make_actions
	M._has_snacks = has_snacks
	M._browse_dir = browse_dir
	M._flatten_symbols = flatten_symbols
	M._project_top_filter = project_top_filter
	M._plugin_internal_filter = plugin_internal_filter
	M._engine_top_filter = engine_top_filter
	M._project_sort = project_sort
end

return M
