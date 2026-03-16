--- Hierarchical configuration: defaults → user → project file → runtime.
--- Lazy-loaded on first get() call. Module-local storage (no _G).

local M = {}

local log = require("unrealium.core.log").get("config")
local finder = require("unrealium.core.finder")

---@type UnrealiumConfig|nil
local _config = nil

---@type table
local _defaults = {
	logging = { level = "info" },
	ui = { picker = { prefer = { "snacks", "telescope", "fzf_lua", "native" } } },
	build = {
		configurations = { "Development", "DebugGame", "Debug", "Shipping", "Test" },
		presets = {},
		output_mode = "terminal",
		progress = true,
		completion_ttl = 5,
		default_preset = nil,
		extra_args = {},
	},
	run = {
		default_type = "Development",
		extra_args = {},
	},
	search = {
		exclude_patterns = { "**/*.po", "**/*.archive", "**/*.gen.h", "**/Intermediate/Build/**" },
	},
	intel = {
		clangd = {
			enabled = true,
			exclusive = false,
			cmd = nil,
			extra_flags = {},
			auto_start = true,
			generate_config = true,
			config_gen = {
				exclude_paths = { "ThirdParty", "Intermediate" },
				extra_compile_flags = {},
			},
		},
	},
	lint = {
		default_analyzer = nil,
	},
	generate = {
		default_clang_scope = nil,
	},
	editor_lock = {
		extra_paths = {},
	},
	debug = {
		adapter = "codelldb",
		default_preset = nil,
		extra_init_commands = {},
		extra_args = {},
	},
}

---@type table
local _user_overrides = {}

---@type table
local _runtime_overrides = {}

---@type table<string, table>
local _sub_defaults = {}

--- Deep merge tables (right into left, non-destructive).
---@param base table
---@param override table
---@return table
local function deep_merge(base, override)
	local result = vim.deepcopy(base)
	for k, v in pairs(override) do
		if type(v) == "table" and type(result[k]) == "table" then
			result[k] = deep_merge(result[k], v)
		else
			result[k] = v
		end
	end
	return result
end

--- Initialize config with user-provided setup options.
---@param user_config? UnrealiumUserConfig
function M.init(user_config)
	_user_overrides = user_config or {}
	-- Reset cached config so next get() rebuilds it
	_config = nil
end

--- Register defaults for a sub-module namespace.
---@param namespace string e.g. "uep"
---@param defaults table
function M.register_defaults(namespace, defaults)
	_sub_defaults[namespace] = defaults
end

--- Set a runtime override.
---@param key string dot-separated path, e.g. "logging.level"
---@param value any
function M.set(key, value)
	local schema = require("unrealium.core.schema")
	local warning = schema.validate_key(key, value)
	if warning then
		log.warn("config.set: %s", warning)
	end

	local parts = vim.split(key, ".", { plain = true })
	local tbl = _runtime_overrides
	for i = 1, #parts - 1 do
		if not tbl[parts[i]] then
			tbl[parts[i]] = {}
		end
		tbl = tbl[parts[i]]
	end
	tbl[parts[#parts]] = value
	-- Invalidate cache
	_config = nil
end

--- Build the full UnrealiumConfig by discovering project and merging config layers.
---@return UnrealiumConfig|nil
function M.get()
	if _config then
		return _config
	end

	local project = finder.find_project()
	if not project then
		log.debug("No Unreal project found from current directory")
		return nil
	end

	local raw_config = finder.read_project_config(project.root)

	local engine_data = finder.resolve_engine_config(raw_config, project.uproject_path)
	local engine_folder = finder.validate_engine_path(engine_data.folder)
	if not engine_folder then
		log.error(
			"Could not resolve engine path. Set engine.folder in unrealium.json or check your .uproject EngineAssociation."
		)
		return nil
	end

	local platform_name = finder.get_platform_name()

	-- Build merged settings from layers
	local settings = vim.deepcopy(_defaults)
	-- Merge sub-module defaults
	for ns, defs in pairs(_sub_defaults) do
		settings[ns] = deep_merge(settings[ns] or {}, defs)
	end
	-- Merge user overrides (from setup())
	settings = deep_merge(settings, _user_overrides)
	-- Merge project file settings (new format keys only)
	if raw_config.logging then
		settings = deep_merge(settings, { logging = raw_config.logging })
	end
	if raw_config.ui then
		settings = deep_merge(settings, { ui = raw_config.ui })
	end
	if raw_config.build then
		settings = deep_merge(settings, { build = raw_config.build })
	end
	if raw_config.run then
		settings = deep_merge(settings, { run = raw_config.run })
	end
	if raw_config.search then
		settings = deep_merge(settings, { search = raw_config.search })
	end
	if raw_config.intel then
		settings = deep_merge(settings, { intel = raw_config.intel })
	end
	if raw_config.lint then
		settings = deep_merge(settings, { lint = raw_config.lint })
	end
	if raw_config.generate then
		settings = deep_merge(settings, { generate = raw_config.generate })
	end
	if raw_config.editor_lock then
		settings = deep_merge(settings, { editor_lock = raw_config.editor_lock })
	end
	if raw_config.debug then
		settings = deep_merge(settings, { debug = raw_config.debug })
	end
	-- Merge runtime overrides
	settings = deep_merge(settings, _runtime_overrides)

	-- Validate and sanitize merged settings
	local schema = require("unrealium.core.schema")
	local ext_namespaces = vim.tbl_keys(_sub_defaults)
	settings = schema.validate_and_sanitize(settings, _user_overrides, raw_config, ext_namespaces, _defaults)

	-- Apply log level from merged settings
	require("unrealium.core.log").set_level(settings.logging.level)

	---@type UnrealiumConfig
	_config = {
		Project = {
			Folder = project.root,
			FullPath = project.uproject_path,
			Name = project.name,
		},
		Engine = {
			Folder = engine_folder,
			Scripts = finder.get_script_paths(engine_folder, platform_name),
			AllowEngineModifications = engine_data.allow_modifications,
		},
		PlatformName = platform_name,
		settings = settings,
	}

	log.info("Config loaded for project: %s", project.name)
	return _config
end

--- Force a config reload on next get() call.
function M.invalidate()
	_config = nil
end

if _TEST then
	M._deep_merge = deep_merge
	M._defaults = _defaults
	M._sub_defaults = _sub_defaults
	M._reset = function()
		_config = nil
		_user_overrides = {}
		_runtime_overrides = {}
		_sub_defaults = {}
	end
end

return M
