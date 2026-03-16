--- :UE run — Launch the Unreal Editor.
--- :UE build-run — Build then launch the Unreal Editor.

local M = {}

local log = require("unrealium.core.log").get("run")
local platform = require("unrealium.core.platform")
local config = require("unrealium.core.config")
local event = require("unrealium.core.event")
local job = require("unrealium.core.job")

M.name = "run"

--- Build first, then launch the editor on success.
---@param build_arg? string preset name or configuration to pass to build.execute
---@param run_type? string "Debug"|"Development"
---@param run_extra_args? string[] additional CLI arguments for the editor
local function build_then_run(build_arg, run_type, run_extra_args)
	if job.is_running() then
		log.error("A build is already running. Wait for it to finish or stop it first.")
		return
	end

	local build = require("unrealium.modules.build")

	local unsub
	unsub = event.on(event.BUILD_END, function(data)
		unsub()
		if data and data.exit_code == 0 then
			log.info("Build succeeded, launching editor")
			M.execute(run_type, run_extra_args, true)
		else
			log.error("Build failed (exit code %s), not launching editor", tostring(data and data.exit_code or "?"))
		end
	end)

	build.execute(build_arg, false)
end

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
	["build-run"] = {
		handler = function(opts)
			if #opts.args == 0 then
				build_then_run(nil, nil, nil)
				return
			end

			-- Try longest match for preset name (same pattern as build command)
			local build = require("unrealium.modules.build")
			local presets = build.get_presets()
			local preset_set = {}
			for _, p in ipairs(presets) do
				preset_set[p.name] = true
			end
			for i = #opts.args, 1, -1 do
				local candidate = table.concat(opts.args, " ", 1, i)
				if preset_set[candidate] then
					build_then_run(candidate, nil, nil)
					return
				end
			end
			-- Fall through with full arg as preset/configuration name
			build_then_run(table.concat(opts.args, " "), nil, nil)
		end,
		desc = "Build then run Unreal Editor",
		args = {
			{
				name = "preset",
				complete = function()
					local build = require("unrealium.modules.build")
					local presets = build.get_presets()
					local names = {}
					for _, p in ipairs(presets) do
						table.insert(names, p.name)
					end
					return names
				end,
			},
		},
	},
}

--- Launch Unreal Editor.
---@param type? string "Debug"|"Development" (defaults to config run.default_type)
---@param extra_args? string[] additional CLI arguments
---@param _skip_build? boolean internal flag to skip build_first check (prevents recursion)
function M.execute(type, extra_args, _skip_build)
	local cfg = config.get()
	if not cfg then
		log.error("Config not available")
		return
	end

	-- If build_first is enabled and we weren't called from build_then_run, build first
	if not _skip_build then
		local build_first = cfg.settings and cfg.settings.run and cfg.settings.run.build_first
		if build_first then
			build_then_run(nil, type, extra_args)
			return
		end
	end

	if not type then
		local build = require("unrealium.modules.build")
		local last = build.last_preset()
		if last and last.is_editor then
			type = last.configuration == "Debug" and "Debug" or "Development"
		else
			type = cfg.settings and cfg.settings.run and cfg.settings.run.default_type or "Development"
		end
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

if _TEST then
	M._build_then_run = build_then_run
end

return M
