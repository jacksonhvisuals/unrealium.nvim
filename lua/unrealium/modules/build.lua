--- :UE build — Preset-based async build system.

local M = {}

local log = require("unrealium.core.log").get("build")
local platform = require("unrealium.core.platform")
local config = require("unrealium.core.config")
local event = require("unrealium.core.event")
local job = require("unrealium.core.job")
local target = require("unrealium.core.target")
local progress = require("unrealium.core.progress")

M.name = "build"

---@type UnrealiumPreset|nil
local _last_preset = nil

--- Generate dynamic presets from discovered targets and config.
---@param cfg UnrealiumConfig
---@param targets UnrealiumBuildTarget[]
---@return UnrealiumPreset[]
local function generate_dynamic_presets(cfg, targets)
	local ubt_plat = platform.ubt_platform(cfg.PlatformName)
	local configurations = cfg.settings and cfg.settings.build and cfg.settings.build.configurations
		or { "Development", "DebugGame", "Debug", "Shipping", "Test" }

	local presets = {}
	for _, tgt in ipairs(targets) do
		for _, conf in ipairs(configurations) do
			table.insert(presets, {
				name = string.format("%s %s %s", tgt.name, ubt_plat, conf),
				target_name = tgt.name,
				platform = ubt_plat,
				configuration = conf,
				is_editor = tgt.type == "Editor",
			})
		end
	end
	return presets
end

--- Merge static and dynamic presets. Static wins on name collision.
---@param static UnrealiumPreset[]
---@param dynamic UnrealiumPreset[]
---@return UnrealiumPreset[]
local function merge_presets(static, dynamic)
	local by_name = {}
	local result = {}

	for _, p in ipairs(static) do
		by_name[p.name] = true
		table.insert(result, p)
	end

	for _, p in ipairs(dynamic) do
		if not by_name[p.name] then
			table.insert(result, p)
		end
	end

	return result
end

--- Get all available presets (static + dynamic).
---@return UnrealiumPreset[]
function M.get_presets()
	local cfg = config.get()
	if not cfg then
		return {}
	end

	local static = cfg.settings and cfg.settings.build and cfg.settings.build.presets or {}
	local targets = target.discover(cfg.Project.Folder)
	local dynamic = generate_dynamic_presets(cfg, targets)

	return merge_presets(static, dynamic)
end

--- Get preset names for completion.
---@return string[]
local function preset_names()
	local presets = M.get_presets()
	local names = {}
	for _, p in ipairs(presets) do
		table.insert(names, p.name)
	end
	return names
end

--- Find a preset by name.
---@param name string
---@return UnrealiumPreset|nil
local function find_preset(name)
	local presets = M.get_presets()
	for _, p in ipairs(presets) do
		if p.name == name then
			return p
		end
	end
	return nil
end

--- Find a default preset (first Editor + Development for current platform).
---@param cfg UnrealiumConfig
---@return UnrealiumPreset|nil
local function default_preset(cfg)
	local presets = M.get_presets()
	local ubt_plat = platform.ubt_platform(cfg.PlatformName)

	-- Prefer Editor + Development
	for _, p in ipairs(presets) do
		if p.is_editor and p.configuration == "Development" and p.platform == ubt_plat then
			return p
		end
	end

	-- Fall back to first preset
	return presets[1]
end

--- Resolve a preset from a configuration name for backward compat.
--- E.g. "Development" → Editor preset for that config on current platform.
---@param cfg UnrealiumConfig
---@param configuration string
---@return UnrealiumPreset|nil
local function preset_from_configuration(cfg, configuration)
	local presets = M.get_presets()
	local ubt_plat = platform.ubt_platform(cfg.PlatformName)

	for _, p in ipairs(presets) do
		if p.is_editor and p.configuration == configuration and p.platform == ubt_plat then
			return p
		end
	end
	return nil
end

--- Create the terminal output buffer.
---@return integer bufnr
local function get_or_create_terminal_buf()
	-- Look for existing buffer
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) then
			local name = vim.api.nvim_buf_get_name(buf)
			if name:match("%[unrealium:build%]$") then
				return buf
			end
		end
	end

	-- Create new buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, "[unrealium:build]")
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buf })
	return buf
end

--- Open the terminal buffer in a horizontal split.
---@param buf integer
local function open_terminal_split(buf)
	-- Check if buffer is already displayed
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(win) == buf then
			return
		end
	end

	vim.cmd("botright split")
	vim.api.nvim_win_set_buf(0, buf)
	vim.cmd("resize 15")
end

--- Append a line to the terminal buffer with auto-scroll.
---@param buf integer
---@param line string
local function append_to_terminal(buf, line)
	vim.schedule(function()
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end
		vim.api.nvim_buf_set_lines(buf, -1, -1, false, { line })

		-- Auto-scroll windows showing this buffer
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_get_buf(win) == buf then
				local line_count = vim.api.nvim_buf_line_count(buf)
				vim.api.nvim_win_set_cursor(win, { line_count, 0 })
			end
		end
	end)
end

--- Populate quickfix list from diagnostics.
---@param handle UnrealiumJobHandle
local function populate_quickfix(handle)
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
	if #handle.errors > 0 then
		vim.cmd("copen")
	end
end

--- Run a build with the given preset.
---@param preset UnrealiumPreset
---@param extra_args? string[] additional CLI arguments
local function run_build(preset, extra_args)
	local cfg = config.get()
	if not cfg then
		log.error("Config not available")
		return
	end

	if job.is_running() then
		log.error("A build is already running. Use :UE build stop to cancel it.")
		return
	end

	-- Merge config-level extra_args with dynamic extra_args
	local merged_args = {}
	local config_args = cfg.settings and cfg.settings.build and cfg.settings.build.extra_args
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

	local cmd_data = platform.ubt_build_command(cfg, preset, #merged_args > 0 and merged_args or nil)
	if not cmd_data then
		log.error("Failed to assemble build command")
		return
	end

	_last_preset = preset
	log.info("Building: %s", preset.name)
	event.emit(event.BUILD_START, { preset = preset })

	local output_mode = cfg.settings and cfg.settings.build and cfg.settings.build.output_mode or "terminal"
	local progress_enabled = cfg.settings and cfg.settings.build and cfg.settings.build.progress_enabled
	if progress_enabled == nil then
		progress_enabled = true
	end

	local term_buf
	if output_mode == "terminal" then
		term_buf = get_or_create_terminal_buf()
		-- Clear previous output
		vim.api.nvim_buf_set_lines(term_buf, 0, -1, false, { "--- Build: " .. preset.name .. " ---" })
		open_terminal_split(term_buf)
	end

	if progress_enabled then
		progress.begin("Building: " .. preset.name)
	end

	job.start({
		cmd = cmd_data.cmd,
		cwd = cmd_data.cwd,
		preset = preset,
		on_line = function(line)
			if output_mode == "terminal" and term_buf then
				append_to_terminal(term_buf, line)
			end
		end,
		on_complete = function(handle)
			vim.schedule(function()
				local level = handle.exit_code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR
				local status = handle.exit_code == 0 and "succeeded" or "failed"
				local msg = string.format(
					"Build %s: %s (%d errors, %d warnings)",
					status,
					preset.name,
					#handle.errors,
					#handle.warnings
				)

				if progress_enabled then
					progress.finish(msg, level)
				end

				if output_mode == "quickfix" then
					populate_quickfix(handle)
				end

				log.info(msg)
				event.emit(event.BUILD_END, { preset = preset, exit_code = handle.exit_code })
			end)
		end,
	})
end

--- Open a picker to choose a preset.
local function pick_preset()
	local presets = M.get_presets()
	if #presets == 0 then
		log.error("No build presets available. Are there *.Target.cs files in Source/?")
		return
	end

	local names = {}
	for _, p in ipairs(presets) do
		table.insert(names, p.name)
	end

	vim.ui.select(names, { prompt = "Select build preset:" }, function(choice)
		if not choice then
			return
		end
		local preset = find_preset(choice)
		if preset then
			run_build(preset)
		end
	end)
end

--- Execute a build.
---@param arg? string preset name, configuration name, or nil for default/last
---@param bang? boolean if true, open preset picker
---@param extra_args? string[] additional CLI arguments
function M.execute(arg, bang, extra_args)
	if bang then
		pick_preset()
		return
	end

	if arg == "stop" then
		job.stop()
		return
	end

	local cfg = config.get()
	if not cfg then
		log.error("Config not available")
		return
	end

	local preset

	if arg and arg ~= "" then
		-- Try as preset name first
		preset = find_preset(arg)

		-- Try as configuration name (backward compat)
		if not preset then
			preset = preset_from_configuration(cfg, arg)
		end

		if not preset then
			log.error("Unknown preset or configuration: %s", arg)
			return
		end
	else
		-- Use last preset, or default
		preset = _last_preset or default_preset(cfg)
		if not preset then
			log.error("No build presets available. Are there *.Target.cs files in Source/?")
			return
		end
	end

	run_build(preset, extra_args)
end

M.commands = {
	build = {
		handler = function(opts)
			if #opts.args == 0 then
				M.execute(nil, opts.bang)
				return
			end
			if opts.args[1] == "stop" then
				M.execute("stop", opts.bang)
				return
			end
			-- Try longest match first to support preset names with spaces
			local presets = M.get_presets()
			local preset_set = {}
			for _, p in ipairs(presets) do
				preset_set[p.name] = true
			end
			for i = #opts.args, 1, -1 do
				local candidate = table.concat(opts.args, " ", 1, i)
				if preset_set[candidate] then
					local extra = {}
					for j = i + 1, #opts.args do
						extra[#extra + 1] = opts.args[j]
					end
					M.execute(candidate, opts.bang, extra)
					return
				end
			end
			-- No preset matched — fall through to execute which will try
			-- single-word config name or show the error
			M.execute(table.concat(opts.args, " "), opts.bang)
		end,
		desc = "Build the project (use ! to pick preset)",
		args = {
			{ name = "preset", complete = preset_names },
		},
	},
}

--- Get the last used preset.
---@return UnrealiumPreset|nil
function M.last_preset()
	return _last_preset
end

if _TEST then
	M._generate_dynamic_presets = generate_dynamic_presets
	M._merge_presets = merge_presets
	M._preset_from_configuration = preset_from_configuration
	M._default_preset = default_preset
	M._run_build = run_build
	M._reset = function()
		_last_preset = nil
	end
end

return M
