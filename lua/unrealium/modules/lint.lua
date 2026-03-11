--- :UE lint — Static analysis via UBT.

local M = {}

local log = require("unrealium.core.log").get("lint")
local platform = require("unrealium.core.platform")
local config = require("unrealium.core.config")
local job = require("unrealium.core.job")
local progress = require("unrealium.core.progress")
local output = require("unrealium.core.output")

M.name = "lint"

local OUTPUT_BUF_NAME = "lint"

--- Execute static analysis.
---@param lint_type? string e.g. "PVS-Studio"
function M.execute(lint_type)
	local cfg = config.get()
	if not cfg then
		log.error("Config not available")
		return
	end

	if not lint_type then
		lint_type = cfg.settings and cfg.settings.lint and cfg.settings.lint.default_analyzer
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

	local term_buf = output.get_or_create_buf(OUTPUT_BUF_NAME)
	output.clear(term_buf, "--- Lint: " .. preset.name .. " ---")

	log.info("Running static analysis: %s", lint_type or "default")
	progress.begin("Lint: " .. preset.name)

	job.start({
		cmd = cmd_data.cmd,
		cwd = cmd_data.cwd,
		preset = preset,
		on_line = function(line)
			output.append(term_buf, line)
		end,
		on_complete = function(handle)
			vim.schedule(function()
				local cancelled = handle.exit_code ~= 0 and handle.exit_code ~= nil and #handle.errors == 0
				local level, status
				if handle.exit_code == 0 then
					level = vim.log.levels.INFO
					status = "completed"
				elseif cancelled then
					level = vim.log.levels.WARN
					status = "cancelled"
				else
					level = vim.log.levels.ERROR
					status = "failed"
				end

				local msg = string.format("Lint %s: %d errors, %d warnings", status, #handle.errors, #handle.warnings)
				progress.finish(msg, level)
				log.info(msg)

				if handle.exit_code ~= 0 and not cancelled then
					output.quickfix(handle)
				end

				if handle.exit_code == 0 and #handle.errors == 0 and #handle.warnings == 0 then
					output.delete_buf(OUTPUT_BUF_NAME)
				end
			end)
		end,
	})
end

M.commands = {
	lint = {
		handler = function(opts)
			if opts.args[1] == "log" then
				if not output.toggle(OUTPUT_BUF_NAME) then
					log.info("No lint output available")
				end
				return
			end
			M.execute(opts.args[1])
		end,
		desc = "Run static analysis",
		args = {
			{
				name = "type",
				complete = function()
					return { "log", "PVS-Studio" }
				end,
			},
		},
	},
}

return M
