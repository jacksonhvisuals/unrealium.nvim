--- :UE lint — Static analysis via UBT.

local M = {}

local log = require("unrealium.core.log").get("lint")
local platform = require("unrealium.core.platform")
local config = require("unrealium.core.config")
local job = require("unrealium.core.job")
local progress = require("unrealium.core.progress")

M.name = "lint"

--- Execute static analysis.
---@param lint_type? string e.g. "PVS-Studio"
function M.execute(lint_type)
	local cfg = config.get()
	if not cfg then
		log.error("Config not available")
		return
	end

	if job.is_running() then
		log.error("A job is already running.")
		return
	end

	-- Use last build preset or find a default editor preset
	local build_mod = require("unrealium.modules.build")
	local preset = build_mod.last_preset()
	if not preset then
		local presets = build_mod.get_presets()
		local ubt_plat = platform.ubt_platform(cfg.PlatformName)
		for _, p in ipairs(presets) do
			if p.is_editor and p.configuration == "Development" and p.platform == ubt_plat then
				preset = p
				break
			end
		end
	end

	if not preset then
		log.error("No build preset available for lint. Run a build first or ensure *.Target.cs files exist.")
		return
	end

	local cmd_data = platform.ubt_lint_command(cfg, preset, lint_type)
	if not cmd_data then
		log.error("Failed to assemble lint command")
		return
	end

	log.info("Running static analysis: %s", lint_type or "default")
	progress.begin("Lint: " .. preset.name)

	job.start({
		cmd = cmd_data.cmd,
		cwd = cmd_data.cwd,
		preset = preset,
		on_complete = function(handle)
			vim.schedule(function()
				local items = {}
				for _, diag in ipairs(handle.errors) do
					table.insert(items, {
						filename = diag.file,
						lnum = diag.lnum,
						col = diag.col or 0,
						text = diag.text,
						type = "E",
					})
				end
				for _, diag in ipairs(handle.warnings) do
					table.insert(items, {
						filename = diag.file,
						lnum = diag.lnum,
						col = diag.col or 0,
						text = diag.text,
						type = "W",
					})
				end

				vim.fn.setqflist(items, "r")
				local status = handle.exit_code == 0 and "completed" or "failed"
				local msg = string.format(
					"Lint %s: %d errors, %d warnings",
					status,
					#handle.errors,
					#handle.warnings
				)
				progress.finish(msg, handle.exit_code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR)
				log.info(msg)

				if #items > 0 then
					vim.cmd("copen")
				end
			end)
		end,
	})
end

M.commands = {
	lint = {
		handler = function(opts)
			M.execute(opts.args[1])
		end,
		desc = "Run static analysis",
		args = {
			{ name = "type", complete = { "PVS-Studio" } },
		},
	},
}

return M
