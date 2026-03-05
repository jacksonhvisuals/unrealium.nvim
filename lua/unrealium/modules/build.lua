--- :UE build — Build the Unreal project.

local M = {}

local log = require("unrealium.core.log").get("build")
local platform = require("unrealium.core.platform")
local config = require("unrealium.core.config")
local event = require("unrealium.core.event")

M.name = "build"

M.commands = {
	build = {
		handler = function(opts)
			M.execute(opts.args[1])
		end,
		desc = "Build the project",
		args = {
			{ name = "type", complete = { "Development", "Debug" } },
		},
	},
}

--- Execute a build.
---@param type? string "Debug"|"Development" (defaults to "Development")
function M.execute(type)
	type = type or "Development"

	local cfg = config.get()
	if not cfg then
		log.error("Config not available")
		return
	end

	log.info("Building %s in %s mode", cfg.Project.Name, type)
	event.emit(event.BUILD_START, { type = type })

	local cmd = platform.build_command(cfg, type)
	if not cmd then
		log.error("Failed to build command for platform %s", cfg.PlatformName)
		return
	end

	-- Use lcd (window-local) to avoid changing global cwd
	vim.cmd("lcd " .. vim.fn.fnameescape(cmd.cwd))
	log.info("Running: %s", cmd.command)
	vim.cmd(cmd.command)
end

return M
