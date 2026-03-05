--- :UE search — Search project/engine files with picker.

local M = {}

local log = require("unrealium.core.log").get("search")
local platform = require("unrealium.core.platform")
local config = require("unrealium.core.config")
local ui = require("unrealium.core.ui")

M.name = "search"

M.commands = {
	search = {
		handler = function(opts)
			M.execute(opts.args[1], opts.args[2], opts.args[3])
		end,
		desc = "Search project/engine files",
		args = {
			{ name = "type", complete = { "grep", "files" } },
			{ name = "scope", complete = { "Engine", "Project", "All" } },
		},
	},
}

--- Execute a search.
---@param search_type? string "grep"|"files"
---@param scope? string "Engine"|"Project"|"All"
---@param search_term? string
function M.execute(search_type, scope, search_term)
	search_type = search_type or "grep"
	scope = scope or "All"

	local cfg = config.get()
	if not cfg then
		log.error("Config not available")
		return
	end

	local dirs = {}
	if scope == "Engine" then
		dirs = { cfg.Engine.Folder }
	elseif scope == "Project" then
		dirs = { cfg.Project.Folder }
	else
		dirs = { cfg.Engine.Folder, cfg.Project.Folder }
	end

	log.info("Searching (%s) in %s", search_type, scope)

	ui.pick({
		mode = search_type,
		dirs = dirs,
		search = search_term,
		exclude = platform.get_exclude_globs(),
		title = "UE Search: " .. scope,
	})
end

return M
