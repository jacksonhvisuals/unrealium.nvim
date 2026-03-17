--- :UE intel — Code intelligence management (clangd / UnrealISense).

local M = {}

local log = require("unrealium.core.log").get("intel")
local config = require("unrealium.core.config")
local lsp = require("unrealium.core.lsp")
local clangd_config_gen = require("unrealium.core.lsp.config_gen")
local unrealisense_config_gen = require("unrealium.core.lsp.unrealisense_config_gen")

M.name = "intel"

--- Get the configured server name.
---@return string
local function get_server_name()
	local cfg = config.get()
	return cfg and cfg.settings and cfg.settings.intel and cfg.settings.intel.server or "clangd"
end

--- Get server-specific settings from config.
---@param server? string override server name
---@return table
local function server_settings(server)
	server = server or get_server_name()
	local cfg = config.get()
	return cfg and cfg.settings and cfg.settings.intel and cfg.settings.intel[server] or {}
end

--- Generate config and start clangd.
function M.setup_clangd()
	local cfg = config.get()
	if not cfg then
		log.error("Config not available")
		return
	end

	local settings = server_settings("clangd")

	if settings.generate_config ~= false then
		clangd_config_gen.generate(cfg, true)
	end

	lsp.start(cfg, settings, "clangd")
end

--- Generate config and start unrealisense.
function M.setup_unrealisense()
	local cfg = config.get()
	if not cfg then
		log.error("Config not available")
		return
	end

	local settings = server_settings("unrealisense")

	if settings.generate_config ~= false then
		unrealisense_config_gen.generate(cfg, true)
	end

	lsp.start(cfg, settings, "unrealisense")
end

--- Setup the configured server (generic entry point).
function M.setup_server()
	local server = get_server_name()
	if server == "unrealisense" then
		M.setup_unrealisense()
	else
		M.setup_clangd()
	end
end

--- Show LSP status.
function M.show_status()
	local status = lsp.status()
	local server = status.server or get_server_name()
	if status.running then
		vim.notify(
			string.format("[unrealium.intel] %s running (client %d)", server, status.client_id),
			vim.log.levels.INFO
		)
	else
		vim.notify(string.format("[unrealium.intel] %s not running", server), vim.log.levels.INFO)
	end
end

--- Restart the active server.
function M.restart_server()
	local cfg = config.get()
	if not cfg then
		log.error("Config not available")
		return
	end

	local server = get_server_name()
	lsp.restart(cfg, server_settings(server), server)
end

M.commands = {
	intel = {
		desc = "Code intelligence management",
		subcommands = {
			["setup"] = {
				handler = function(_)
					M.setup_server()
				end,
				desc = "Generate config and start the configured LSP server",
			},
			["setup-clangd"] = {
				handler = function(_)
					M.setup_clangd()
				end,
				desc = "Generate optimized .clangd config and start clangd",
			},
			["setup-unrealisense"] = {
				handler = function(_)
					M.setup_unrealisense()
				end,
				desc = "Generate .unrealisense.toml and start UnrealISense",
			},
			["status"] = {
				handler = function(_)
					M.show_status()
				end,
				desc = "Show LSP server status",
			},
			["stop"] = {
				handler = function(_)
					lsp.stop()
				end,
				desc = "Stop the active LSP server",
			},
			["restart"] = {
				handler = function(_)
					M.restart_server()
				end,
				desc = "Restart the active LSP server",
			},
		},
	},
}

--- Module setup hook — register auto-start if enabled.
---@param cfg UnrealiumConfig
function M.setup(cfg)
	local server = cfg.settings and cfg.settings.intel and cfg.settings.intel.server or "clangd"
	local settings = cfg.settings and cfg.settings.intel and cfg.settings.intel[server] or {}

	-- For clangd, respect the legacy `enabled` flag
	if server == "clangd" and settings.enabled == false then
		return
	end

	if server == "clangd" then
		if settings.generate_config ~= false then
			clangd_config_gen.generate(cfg)
		end
	elseif server == "unrealisense" then
		if settings.generate_config ~= false then
			unrealisense_config_gen.generate(cfg)
		end
	end

	if settings.auto_start ~= false then
		lsp.register_auto_start(cfg, settings, server)
	end
end

if _TEST then
	M._get_server_name = get_server_name
	M._server_settings = server_settings
end

return M
