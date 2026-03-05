--- :UE intel — Code intelligence management (clangd optimization).

local M = {}

local log = require("unrealium.core.log").get("intel")
local config = require("unrealium.core.config")
local lsp = require("unrealium.core.lsp")
local config_gen = require("unrealium.core.lsp.config_gen")

M.name = "intel"

--- Get intel settings from config.
---@return table
local function intel_settings()
	local cfg = config.get()
	return cfg and cfg.settings and cfg.settings.intel and cfg.settings.intel.clangd or {}
end

--- Generate .clangd config and start clangd.
function M.setup_clangd()
	local cfg = config.get()
	if not cfg then
		log.error("Config not available")
		return
	end

	local settings = intel_settings()

	if settings.generate_config ~= false then
		config_gen.generate(cfg, true)
	end

	lsp.start(cfg, settings)
end

--- Show clangd status.
function M.show_status()
	local status = lsp.status()
	if status.running then
		vim.notify(
			string.format("[unrealium.intel] clangd running (client %d)", status.client_id),
			vim.log.levels.INFO
		)
	else
		vim.notify("[unrealium.intel] clangd not running", vim.log.levels.INFO)
	end
end

--- Restart clangd.
function M.restart_clangd()
	local cfg = config.get()
	if not cfg then
		log.error("Config not available")
		return
	end

	lsp.restart(cfg, intel_settings())
end

M.commands = {
	intel = {
		desc = "Code intelligence management",
		subcommands = {
			["setup-clangd"] = {
				handler = function(_)
					M.setup_clangd()
				end,
				desc = "Generate optimized .clangd config and start clangd",
			},
			["status"] = {
				handler = function(_)
					M.show_status()
				end,
				desc = "Show clangd status",
			},
			["stop"] = {
				handler = function(_)
					lsp.stop()
				end,
				desc = "Stop clangd",
			},
			["restart"] = {
				handler = function(_)
					M.restart_clangd()
				end,
				desc = "Restart clangd",
			},
		},
	},
}

--- Module setup hook — register auto-start if enabled.
---@param cfg UnrealiumConfig
function M.setup(cfg)
	local settings = cfg.settings and cfg.settings.intel and cfg.settings.intel.clangd or {}

	if settings.enabled == false then
		return
	end

	if settings.generate_config ~= false then
		config_gen.generate(cfg)
	end

	if settings.auto_start ~= false then
		lsp.register_auto_start(cfg, settings)
	end
end

if _TEST then
	M._intel_settings = intel_settings
end

return M
