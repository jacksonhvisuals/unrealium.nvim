--- :UE run — Launch the Unreal Editor.

local M = {}

local log = require("unrealium.core.log").get("run")
local platform = require("unrealium.core.platform")
local config = require("unrealium.core.config")

M.name = "run"

M.commands = {
	run = {
		handler = function(opts)
			M.execute(opts.args[1])
		end,
		desc = "Run Unreal Editor",
		args = {
			{ name = "type", complete = { "Development", "Debug" } },
		},
	},
}

--- Launch Unreal Editor.
---@param type? string "Debug"|"Development" (defaults to "Development")
function M.execute(type)
	type = type or "Development"

	local cfg = config.get()
	if not cfg then
		log.error("Config not available")
		return
	end

	log.info("Launching UnrealEditor in %s mode", type)
	local cmd = platform.run_command(cfg, type)
	log.info("Running: %s", cmd.command)
	vim.cmd(cmd.command)
end

return M
