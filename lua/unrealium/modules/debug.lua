--- :UE debug — Launch debugging via nvim-dap with UE formatter injection.

local M = {}

local log = require("unrealium.core.log").get("debug")
local config = require("unrealium.core.config")
local platform = require("unrealium.core.platform")
local target = require("unrealium.core.target")

M.name = "debug"

---@type string|nil
local _last_preset_name = nil

--- Check if nvim-dap is available.
---@return table|nil dap module or nil
local function get_dap()
	local ok, dap = pcall(require, "dap")
	if not ok then
		log.error("nvim-dap is required for debugging. Install mfussenegger/nvim-dap.")
		return nil
	end
	return dap
end

--- Resolve the path to Epic's LLDB data formatters.
---@param engine_folder string
---@return string|nil formatter_path
local function find_epic_formatters(engine_folder)
	local variants = { "UEDataFormatters_2ByteChars.py", "UEDataFormatters.py" }
	local base = vim.fs.joinpath(engine_folder, "Engine", "Extras", "LLDBDataFormatters")

	for _, variant in ipairs(variants) do
		local path = vim.fs.joinpath(base, variant)
		if vim.fn.filereadable(path) == 1 then
			return path
		end
	end
	return nil
end

--- Resolve the path to unrealium's extended formatters.
---@return string|nil
local function find_extended_formatters()
	-- Find the plugin's extras/lldb directory
	local info = debug.getinfo(1, "S")
	if not info or not info.source then
		return nil
	end
	local source_path = info.source:gsub("^@", "")
	-- modules/debug.lua -> go up to plugin root
	local plugin_root = vim.fn.fnamemodify(source_path, ":h:h:h:h")
	local path = vim.fs.joinpath(plugin_root, "extras", "lldb", "ue_extended_formatters.py")
	if vim.fn.filereadable(path) == 1 then
		return path
	end
	return nil
end

--- Build the LLDB init commands that load UE formatters.
---@param cfg UnrealiumConfig
---@return string[]
local function build_init_commands(cfg)
	local commands = {
		"settings set target.inline-breakpoint-strategy always",
	}

	local epic_path = find_epic_formatters(cfg.Engine.Folder)
	if epic_path then
		table.insert(commands, string.format('command script import "%s"', epic_path))
		log.info("Will load Epic LLDB formatters from: %s", epic_path)
	else
		log.warn("Epic LLDB formatters not found in engine at: %s", cfg.Engine.Folder)
	end

	local extended_path = find_extended_formatters()
	if extended_path then
		table.insert(commands, string.format('command script import "%s"', extended_path))
		log.info("Will load extended LLDB formatters from: %s", extended_path)
	end

	-- Merge user extra_init_commands
	local debug_settings = cfg.settings and cfg.settings.debug
	if debug_settings and debug_settings.extra_init_commands then
		for _, cmd in ipairs(debug_settings.extra_init_commands) do
			table.insert(commands, cmd)
		end
	end

	return commands
end

--- Resolve the binary path for a debug preset.
---@param cfg UnrealiumConfig
---@param preset UnrealiumDebugPreset
---@return string|nil binary_path
local function resolve_binary_path(cfg, preset)
	local editor_base = cfg.Engine.Scripts.EditorBase
	if not editor_base then
		log.error("EditorBase path not configured")
		return nil
	end

	local suffix = ""
	if preset.target_type == "Game" then
		-- Game targets use the project binary
		local binaries_dir = vim.fs.joinpath(
			cfg.Project.Folder,
			"Binaries",
			platform.ubt_platform(cfg.PlatformName)
		)
		local binary = vim.fs.joinpath(binaries_dir, cfg.Project.Name)
		if preset.configuration == "Debug" or preset.configuration == "DebugGame" then
			binary = binary .. "-" .. platform.ubt_platform(cfg.PlatformName) .. "-" .. preset.configuration
		end
		return binary
	end

	-- Editor targets use UnrealEditor binary
	if preset.configuration == "Debug" or preset.configuration == "DebugGame" then
		suffix = "-" .. platform.ubt_platform(cfg.PlatformName) .. "-" .. preset.configuration
	end

	return editor_base .. suffix
end

--- Generate debug presets from discovered targets.
---@param cfg UnrealiumConfig
---@return UnrealiumDebugPreset[]
local function generate_debug_presets(cfg)
	local targets = target.discover(cfg.Project.Folder)
	local configurations = { "DebugGame", "Debug", "Development" }
	local presets = {}

	for _, tgt in ipairs(targets) do
		for _, conf in ipairs(configurations) do
			local name = string.format("%s (%s)", tgt.name, conf)
			table.insert(presets, {
				name = name,
				target_name = tgt.name,
				target_type = tgt.type,
				configuration = conf,
			})
		end
	end

	return presets
end

--- Get preset names for completion.
---@param cfg UnrealiumConfig
---@return string[]
local function preset_names(cfg)
	local presets = generate_debug_presets(cfg)
	local names = {}
	for _, p in ipairs(presets) do
		table.insert(names, p.name)
	end
	return names
end

--- Find a preset by name.
---@param presets UnrealiumDebugPreset[]
---@param name string
---@return UnrealiumDebugPreset|nil
local function find_preset(presets, name)
	for _, p in ipairs(presets) do
		if p.name == name then
			return p
		end
	end
	return nil
end

--- Find a default debug preset (first Editor + DebugGame).
---@param presets UnrealiumDebugPreset[]
---@return UnrealiumDebugPreset|nil
local function default_preset(presets)
	-- Prefer Editor + DebugGame
	for _, p in ipairs(presets) do
		if p.target_type == "Editor" and p.configuration == "DebugGame" then
			return p
		end
	end
	-- Fall back to first preset
	return presets[1]
end

--- Build the DAP launch configuration.
---@param cfg UnrealiumConfig
---@param preset UnrealiumDebugPreset
---@return table|nil dap_config
local function build_dap_config(cfg, preset)
	local binary = resolve_binary_path(cfg, preset)
	if not binary then
		return nil
	end

	local adapter = cfg.settings and cfg.settings.debug and cfg.settings.debug.adapter or "codelldb"
	local init_commands = build_init_commands(cfg)

	local args = { cfg.Project.FullPath }

	-- Merge user extra args
	local debug_settings = cfg.settings and cfg.settings.debug
	if debug_settings and debug_settings.extra_args then
		for _, arg in ipairs(debug_settings.extra_args) do
			table.insert(args, arg)
		end
	end

	return {
		name = "UE: " .. preset.name,
		type = adapter,
		request = "launch",
		program = binary,
		args = args,
		cwd = cfg.Project.Folder,
		initCommands = init_commands,
		stopOnEntry = false,
	}
end

--- Build a DAP attach configuration.
---@param cfg UnrealiumConfig
---@return table dap_config
local function build_attach_config(cfg)
	local adapter = cfg.settings and cfg.settings.debug and cfg.settings.debug.adapter or "codelldb"
	local init_commands = build_init_commands(cfg)

	return {
		name = "UE: Attach to Editor",
		type = adapter,
		request = "attach",
		pid = "${command:pickProcess}",
		initCommands = init_commands,
		stopOnEntry = false,
	}
end

--- Launch a debug session with the given preset.
---@param preset UnrealiumDebugPreset
local function launch_debug(preset)
	local dap = get_dap()
	if not dap then
		return
	end

	local cfg = config.get()
	if not cfg then
		log.error("Config not available")
		return
	end

	local dap_config = build_dap_config(cfg, preset)
	if not dap_config then
		log.error("Failed to build DAP configuration")
		return
	end

	_last_preset_name = preset.name
	log.info("Launching debug session: %s", preset.name)
	dap.run(dap_config)
end

--- Open a picker to choose a debug preset.
local function pick_preset()
	local cfg = config.get()
	if not cfg then
		log.error("Config not available")
		return
	end

	local presets = generate_debug_presets(cfg)
	if #presets == 0 then
		log.error("No debug presets available. Are there *.Target.cs files in Source/?")
		return
	end

	local names = {}
	for _, p in ipairs(presets) do
		table.insert(names, p.name)
	end

	vim.ui.select(names, { prompt = "Select debug preset:" }, function(choice)
		if not choice then
			return
		end
		local preset = find_preset(presets, choice)
		if preset then
			launch_debug(preset)
		end
	end)
end

--- Execute a debug session.
---@param arg? string preset name or "attach"
---@param bang? boolean if true, open preset picker
function M.execute(arg, bang)
	if bang then
		pick_preset()
		return
	end

	if arg == "attach" then
		local dap = get_dap()
		if not dap then
			return
		end
		local cfg = config.get()
		if not cfg then
			log.error("Config not available")
			return
		end
		log.info("Attaching debugger to running process")
		dap.run(build_attach_config(cfg))
		return
	end

	local cfg = config.get()
	if not cfg then
		log.error("Config not available")
		return
	end

	local presets = generate_debug_presets(cfg)
	if #presets == 0 then
		log.error("No debug presets available. Are there *.Target.cs files in Source/?")
		return
	end

	local preset

	if arg and arg ~= "" then
		preset = find_preset(presets, arg)
		if not preset then
			log.error("Unknown debug preset: %s", arg)
			return
		end
	else
		-- Use last preset or default
		if _last_preset_name then
			preset = find_preset(presets, _last_preset_name)
		end
		if not preset then
			-- Check config for default_preset
			local debug_settings = cfg.settings and cfg.settings.debug
			if debug_settings and debug_settings.default_preset then
				preset = find_preset(presets, debug_settings.default_preset)
			end
		end
		if not preset then
			preset = default_preset(presets)
		end
		if not preset then
			log.error("No debug presets available")
			return
		end
	end

	launch_debug(preset)
end

M.commands = {
	debug = {
		handler = function(opts)
			M.execute(opts.args[1], opts.bang)
		end,
		desc = "Debug the project (use ! to pick preset)",
		args = {
			{
				name = "preset",
				complete = function()
					local cfg = config.get()
					if not cfg then
						return { "attach" }
					end
					local names = preset_names(cfg)
					table.insert(names, 1, "attach")
					return names
				end,
			},
		},
	},
}

--- Get the last used preset name.
---@return string|nil
function M.last_preset_name()
	return _last_preset_name
end

if _TEST then
	M._find_epic_formatters = find_epic_formatters
	M._find_extended_formatters = find_extended_formatters
	M._build_init_commands = build_init_commands
	M._resolve_binary_path = resolve_binary_path
	M._generate_debug_presets = generate_debug_presets
	M._build_dap_config = build_dap_config
	M._build_attach_config = build_attach_config
	M._default_preset = default_preset
	M._reset = function()
		_last_preset_name = nil
	end
end

return M
