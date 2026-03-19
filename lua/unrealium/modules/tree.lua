--- :UE tree — Multi-root file tree (Project + Engine).

local M = {}

local log = require("unrealium.core.log").get("tree")
local config = require("unrealium.core.config")

M.name = "tree"

--- Resolve the engine root path for the tree.
--- Uses engine_dirs config to determine which subdirectories to show.
---@param cfg UnrealiumConfig
---@return string|nil engine_root
local function resolve_engine_root(cfg)
	if not cfg.Engine or not cfg.Engine.Folder then
		log.warn("No engine path configured; tree will show project only")
		return nil
	end

	local engine_folder = cfg.Engine.Folder
	local tree_settings = cfg.settings.tree

	-- If engine_dirs has a single entry, point directly to that subdir
	if tree_settings.engine_dirs and #tree_settings.engine_dirs == 1 then
		local subdir = vim.fs.joinpath(engine_folder, "Engine", tree_settings.engine_dirs[1])
		if vim.fn.isdirectory(subdir) == 1 then
			return subdir
		end
	end

	-- Otherwise use the engine root itself
	local engine_root = vim.fs.joinpath(engine_folder, "Engine")
	if vim.fn.isdirectory(engine_root) == 1 then
		return engine_root
	end

	-- Fallback to the engine folder directly
	if vim.fn.isdirectory(engine_folder) == 1 then
		return engine_folder
	end

	log.warn("Engine directory does not exist: %s", engine_folder)
	return nil
end

--- Execute the tree command.
---@param action? string "toggle"|"open"|"close"|"focus"|"reveal"
function M.execute(action)
	action = action or "toggle"

	local cfg = config.get()
	if not cfg then
		log.error("No Unreal project found")
		return
	end

	local project_root = cfg.Project.Folder
	local engine_root = resolve_engine_root(cfg)
	local allow_engine_mods = cfg.Engine.AllowEngineModifications or false
	local tree_opts = cfg.settings.tree

	local tree_ui = require("unrealium.core.ui.tree")
	tree_ui.execute(action, project_root, engine_root, allow_engine_mods, tree_opts)
end

M.commands = {
	tree = {
		handler = function(opts)
			M.execute(opts.args[1])
		end,
		desc = "Multi-root file tree (Project + Engine)",
		args = {
			{ name = "action", complete = { "toggle", "open", "close", "focus", "reveal" } },
		},
	},
}

if _TEST then
	M._resolve_engine_root = resolve_engine_root
end

return M
