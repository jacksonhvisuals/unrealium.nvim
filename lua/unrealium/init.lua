--- Unrealium.nvim — Setup orchestrator + module registration.

local M = {}

local config = require("unrealium.core.config")
local log_mod = require("unrealium.core.log")
local event = require("unrealium.core.event")
local command = require("unrealium.core.command")

---@type table<string, UnrealiumCommandSpec>
local _subcommands = {}

--- Built-in module list.
local BUILTIN_MODULES = { "build", "run", "search", "generate", "editor_lock", "lint", "diagnostics", "intel", "debug" }

--- Register commands from a module into the subcommand tree.
---@param mod_commands table<string, UnrealiumCommandSpec>
local function register_module_commands(mod_commands)
	for name, spec in pairs(mod_commands) do
		_subcommands[name] = spec
	end
end

--- Core initialization: discover project, load modules, register commands.
local function init()
	local cfg = config.get()
	if not cfg then
		-- Not in an Unreal project — silently skip
		return
	end

	-- Load built-in modules
	for _, name in ipairs(BUILTIN_MODULES) do
		local ok, mod = pcall(require, "unrealium.modules." .. name)
		if ok then
			if mod.commands then
				register_module_commands(mod.commands)
			end
			if mod.setup then
				mod.setup(cfg)
			end
		else
			log_mod.get("init").error("Failed to load module %s: %s", name, mod)
		end
	end

	-- Create :UE command
	command.create({ name = "UE", subcommands = _subcommands })

	-- Legacy aliases
	vim.api.nvim_create_user_command("UBuild", function(opts)
		require("unrealium.modules.build").execute(opts.fargs[1], opts.bang)
	end, {
		nargs = "*",
		bang = true,
		complete = function(_, line)
			return filter_complete(line, { "Development", "Debug", "DebugGame", "Shipping", "Test" })
		end,
	})

	vim.api.nvim_create_user_command("URun", function(opts)
		require("unrealium.modules.run").execute(unpack(opts.fargs))
	end, {
		nargs = "*",
		complete = function(_, line)
			return filter_complete(line, { "Development", "Debug" })
		end,
	})

	vim.api.nvim_create_user_command("USearch", function(opts)
		require("unrealium.modules.search").execute(unpack(opts.fargs))
	end, {
		nargs = "*",
		complete = function(_, line)
			local parts = vim.split(line, "%s+")
			local n = #parts - 2
			if n == 0 then
				return filter_partial(parts[#parts], { "grep", "files" })
			elseif n == 1 then
				return filter_partial(parts[#parts], { "Engine", "Project", "All" })
			end
		end,
	})

	vim.api.nvim_create_user_command("UGenProjectFiles", function(_)
		require("unrealium.modules.generate").project_files()
	end, {})

	vim.api.nvim_create_user_command("UGenClangDatabase", function(opts)
		require("unrealium.modules.generate").clang_database(unpack(opts.fargs))
	end, {
		nargs = "*",
		complete = function(_, line)
			return filter_complete(line, { "Project", "Engine" })
		end,
	})

	-- Emit ready event (also fires User autocmd for backward compat)
	event.emit(event.PLUGIN_READY, { config = cfg })
	-- Fire legacy autocmd pattern too
	pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "UnrealiumStart" })
end

--- Filter completions by partial match (used by legacy commands).
---@param partial string
---@param candidates string[]
---@return string[]
function filter_partial(partial, candidates)
	return vim.tbl_filter(function(v)
		return vim.startswith(v, partial or "")
	end, candidates)
end

--- Simple completion: filter first arg from candidates.
---@param line string
---@param candidates string[]
---@return string[]
function filter_complete(line, candidates)
	local parts = vim.split(line, "%s+")
	local partial = parts[#parts] or ""
	if #parts <= 2 then
		return filter_partial(partial, candidates)
	end
	return {}
end

--- Plugin entry point. Called by plugin/unrealium.lua or lazy.nvim setup.
---@param user_config? UnrealiumUserConfig
function M.setup(user_config)
	vim.g.unrealium_setup_called = true
	config.init(user_config)
	log_mod.init(user_config and user_config.logging or nil)

	local augroup = vim.api.nvim_create_augroup("Unrealium", { clear = true })
	vim.api.nvim_create_autocmd("VimEnter", {
		group = augroup,
		desc = "Configures basic mechanisms for Unrealium.",
		once = true,
		callback = init,
	})
end

--- Extension API: register config defaults for a sub-module.
---@param namespace string
---@param defaults table
function M.register_config(namespace, defaults)
	config.register_defaults(namespace, defaults)
end

--- Extension API: register commands under a namespace.
---@param namespace string
---@param commands table<string, UnrealiumCommandSpec>
function M.register_commands(namespace, commands)
	command.add_subcommands(_subcommands, namespace, commands)
end

--- Extension API: register a capability provider.
---@param capability string
---@param provider { name: string, impl: any, priority?: number }
function M.register_provider(capability, provider)
	require("unrealium.core.provider").register(capability, provider)
end

if _TEST then
	M._init = init
	M._subcommands = function()
		return _subcommands
	end
end

return M
