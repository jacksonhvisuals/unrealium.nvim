--- :UE run — Launch the Unreal Editor.

local M = {}

local log = require("unrealium.core.log").get("run")
local platform = require("unrealium.core.platform")
local config = require("unrealium.core.config")

M.name = "run"

M.commands = {
	run = {
		handler = function(opts)
			M.execute(opts.args[1], { unpack(opts.args, 2) })
		end,
		desc = "Run Unreal Editor",
		args = {
			{ name = "type", complete = { "Development", "Debug" } },
		},
	},
}

--- Launch Unreal Editor.
---@param type? string "Debug"|"Development" (defaults to "Development")
---@param extra_args? string[] additional CLI arguments
function M.execute(type, extra_args)
	type = type or "Development"

	local cfg = config.get()
	if not cfg then
		log.error("Config not available")
		return
	end

	-- Merge config-level extra_args with dynamic extra_args
	local merged_args = {}
	local config_args = cfg.settings and cfg.settings.run and cfg.settings.run.extra_args
	if config_args then
		for _, arg in ipairs(config_args) do
			table.insert(merged_args, arg)
		end
	end
	if extra_args then
		for _, arg in ipairs(extra_args) do
			table.insert(merged_args, arg)
		end
	end

	log.info("Launching UnrealEditor in %s mode", type)
	local cmd = platform.run_command(cfg, type, #merged_args > 0 and merged_args or nil)
	log.info("Running: %s", cmd.command)
	vim.cmd(cmd.command)
end

return M
