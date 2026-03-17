--- LSP lifecycle management for Unreal Engine projects.
--- Backend-agnostic: dispatches to clangd or unrealisense backend.

local M = {}

local log = require("unrealium.core.log").get("intel")
local event = require("unrealium.core.event")

---@type integer|nil
local _client_id = nil

---@type integer|nil
local _autocmd_id = nil

---@type integer|nil
local _exclusive_autocmd_id = nil

---@type string|nil
local _active_server = nil

local BACKENDS = {
	clangd = "unrealium.core.lsp.backends.clangd",
	unrealisense = "unrealium.core.lsp.backends.unrealisense",
}

--- Resolve the backend module for a given server name.
---@param server_name string
---@return table|nil
local function get_backend(server_name)
	local mod_path = BACKENDS[server_name]
	if not mod_path then
		log.error("Unknown LSP backend: %s", server_name)
		return nil
	end
	return require(mod_path)
end

--- Start an LSP server.
---@param cfg UnrealiumConfig
---@param intel_settings? table
---@param server_name? string "clangd"|"unrealisense" (default: "clangd")
function M.start(cfg, intel_settings, server_name)
	if _client_id then
		local client = vim.lsp.get_client_by_id(_client_id)
		if client then
			log.info("LSP server is already running (client %d)", _client_id)
			return
		end
		_client_id = nil
	end

	server_name = server_name or "clangd"
	intel_settings = intel_settings or {}

	local backend = get_backend(server_name)
	if not backend then
		return
	end

	local cmd = backend.build_cmd(cfg, intel_settings)
	if not cmd then
		return
	end

	local name = backend.client_name()
	log.info("Starting %s: %s", server_name, table.concat(cmd, " "))

	_client_id = vim.lsp.start({
		name = name,
		cmd = cmd,
		root_dir = cfg.Project.Folder,
		filetypes = backend.filetypes(),
		on_attach = function(_, bufnr)
			log.debug("%s attached to buffer %d", server_name, bufnr)
			event.emit(event.LSP_READY, { client_id = _client_id })
		end,
	})

	if not _client_id then
		log.error("Failed to start %s", server_name)
		return
	end

	_active_server = server_name

	if intel_settings.exclusive then
		backend.stop_external()
		-- Guard against external clients that start after ours
		if not _exclusive_autocmd_id then
			local group = vim.api.nvim_create_augroup("UnrealiumExclusive", { clear = true })
			_exclusive_autocmd_id = vim.api.nvim_create_autocmd("LspAttach", {
				group = group,
				desc = "Stop external LSP clients (exclusive mode)",
				callback = function(args)
					local client = vim.lsp.get_client_by_id(args.data.client_id)
					if client and client.name ~= name and backend.stop_external then
						-- Check if this newly-attached client is one we'd stop
						local dominated = false
						if server_name == "clangd" then
							dominated = client.name:find("clangd") ~= nil
						elseif server_name == "unrealisense" then
							dominated = client.name:find("clangd") ~= nil or client.name:find("unrealisense") ~= nil
						end
						if dominated then
							log.info(
								"Stopping external LSP client: %s (id %d) [exclusive mode]",
								client.name,
								client.id
							)
							client:stop()
						end
					end
				end,
			})
		end
	end
end

--- Stop the running LSP client.
function M.stop()
	if not _client_id then
		log.info("LSP server is not running")
		return
	end

	local client = vim.lsp.get_client_by_id(_client_id)
	if client then
		client.stop()
		log.info("Stopped %s (client %d)", _active_server or "LSP server", _client_id)
	end
	_client_id = nil
	_active_server = nil
	if _exclusive_autocmd_id then
		vim.api.nvim_del_autocmd(_exclusive_autocmd_id)
		_exclusive_autocmd_id = nil
	end
end

--- Restart the LSP server.
---@param cfg UnrealiumConfig
---@param intel_settings? table
---@param server_name? string
function M.restart(cfg, intel_settings, server_name)
	server_name = server_name or _active_server or "clangd"
	M.stop()
	-- Defer start to let the old client shut down
	vim.defer_fn(function()
		M.start(cfg, intel_settings, server_name)
	end, 200)
end

--- Attach the running LSP client to a buffer.
---@param bufnr integer
---@return boolean success
function M.buf_attach(bufnr)
	if not _client_id then
		log.warn("LSP server is not running, cannot attach to buffer %d", bufnr)
		return false
	end
	local client = vim.lsp.get_client_by_id(_client_id)
	if not client then
		_client_id = nil
		return false
	end
	vim.lsp.buf_attach_client(bufnr, _client_id)
	return true
end

--- Check if the LSP server is currently running.
---@return boolean
function M.is_running()
	if not _client_id then
		return false
	end
	local client = vim.lsp.get_client_by_id(_client_id)
	return client ~= nil
end

--- Get the current status.
---@return { running: boolean, client_id: integer|nil, server: string|nil }
function M.status()
	return {
		running = M.is_running(),
		client_id = _client_id,
		server = _active_server,
	}
end

--- Register a BufReadPost autocmd to auto-start the LSP on first C++ buffer.
---@param cfg UnrealiumConfig
---@param intel_settings table
---@param server_name? string
function M.register_auto_start(cfg, intel_settings, server_name)
	if _autocmd_id then
		return
	end

	server_name = server_name or "clangd"

	local group = vim.api.nvim_create_augroup("UnrealiumIntel", { clear = true })
	_autocmd_id = vim.api.nvim_create_autocmd("BufReadPost", {
		group = group,
		pattern = { "*.h", "*.hpp", "*.cpp", "*.cc" },
		desc = "Auto-start LSP for Unreal C++ files",
		callback = function(args)
			-- Only trigger for files within the project or engine tree
			local file = args.file
			if not vim.startswith(file, cfg.Project.Folder) and not vim.startswith(file, cfg.Engine.Folder) then
				return
			end

			-- Delete this autocmd after first trigger
			vim.api.nvim_del_autocmd(_autocmd_id)
			_autocmd_id = nil

			M.start(cfg, intel_settings, server_name)
		end,
	})
end

if _TEST then
	M._get_backend = get_backend
	M._reset = function()
		_client_id = nil
		_autocmd_id = nil
		_active_server = nil
	end
end

return M
