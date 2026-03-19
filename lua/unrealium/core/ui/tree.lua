--- Multi-root file tree: Snacks explorer backend + vim.ui.select fallback.
--- Shows Project and Engine as sibling roots in a unified sidebar.

local M = {}

local log = require("unrealium.core.log").get("tree")

--- Check if Snacks picker is available.
---@return boolean
local function has_snacks()
	local ok = pcall(require, "snacks")
	return ok
end

-- ---------------------------------------------------------------------------
-- Snacks backend
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

			-- Virtual root that parents both project and engine
			---@type snacks.picker.explorer.Item
			local virtual_root = {
				file = "",
				dir = true,
				open = true,
				text = "",
				sort = "",
				internal = true,
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
			local project_name = vim.fn.fnamemodify(project_root, ":t")
			yield_root(project_root, project_name, engine_root == nil, true)

			-- Engine root: collapsed by default (lazy expansion)
			if engine_root then
				yield_root(engine_root, "Engine", true, false)
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

--- Open the Snacks multi-root tree picker.
---@param project_root string
---@param engine_root string|nil
---@param allow_engine_mods boolean
---@param tree_opts table
function M.open_snacks(project_root, engine_root, allow_engine_mods, tree_opts)
	local Snacks = require("snacks")
	local ExplorerSource = require("snacks.picker.source.explorer")

	local finder = make_finder(project_root, engine_root, tree_opts)
	local actions = make_actions(project_root, engine_root, allow_engine_mods)

	local picker_instance = Snacks.picker({
		source = "ue_tree",
		finder = finder,
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

	return picker_instance
end

--- Toggle the Snacks tree picker (open/close).
---@param project_root string
---@param engine_root string|nil
---@param allow_engine_mods boolean
---@param tree_opts table
function M.toggle_snacks(project_root, engine_root, allow_engine_mods, tree_opts)
	local Snacks = require("snacks")
	local existing = Snacks.picker.get({ source = "ue_tree" })
	if #existing > 0 then
		existing[1]:close()
	else
		M.open_snacks(project_root, engine_root, allow_engine_mods, tree_opts)
	end
end

--- Close any open Snacks tree picker.
function M.close_snacks()
	local ok, Snacks = pcall(require, "snacks")
	if not ok then
		return
	end
	local existing = Snacks.picker.get({ source = "ue_tree" })
	for _, picker in ipairs(existing) do
		picker:close()
	end
end

--- Focus the Snacks tree picker.
---@param project_root string
---@param engine_root string|nil
---@param allow_engine_mods boolean
---@param tree_opts table
function M.focus_snacks(project_root, engine_root, allow_engine_mods, tree_opts)
	local Snacks = require("snacks")
	local existing = Snacks.picker.get({ source = "ue_tree" })
	if #existing > 0 then
		existing[1]:focus()
	else
		M.open_snacks(project_root, engine_root, allow_engine_mods, tree_opts)
	end
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
function M.open_fallback(project_root, engine_root)
	vim.notify(
		"[unrealium] Install snacks.nvim for a richer file tree experience",
		vim.log.levels.INFO,
		{ once = true }
	)

	local choices = { "Project: " .. vim.fn.fnamemodify(project_root, ":t") }
	local paths = { project_root }

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
		M.open_fallback(project_root, engine_root)
	end
end

if _TEST then
	M._make_finder = make_finder
	M._make_actions = make_actions
	M._has_snacks = has_snacks
	M._browse_dir = browse_dir
end

return M
