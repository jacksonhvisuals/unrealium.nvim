--- clangd lifecycle management for Unreal Engine projects.

local M = {}

local log = require("unrealium.core.log").get("intel")
local event = require("unrealium.core.event")

---@type integer|nil
local _client_id = nil

---@type integer|nil
local _autocmd_id = nil

---@type integer|nil
local _exclusive_autocmd_id = nil

local BASE_FLAGS = {
	"--background-index",
	"--pch-storage=memory",
	"--header-insertion=never",
	"--completion-style=detailed",
	"--clang-tidy=false",
	"--limit-results=50",
}

--- Find compile_commands.json in standard Unreal project locations.
---@param cfg UnrealiumConfig
---@return string|nil directory containing compile_commands.json
local function find_compile_commands(cfg)
	local candidates = {
		cfg.Project.Folder,
		cfg.Engine.Folder,
		cfg.Project.Folder .. "/Intermediate",
	}

	for _, dir in ipairs(candidates) do
		local path = dir .. "/compile_commands.json"
		local stat = vim.uv.fs_stat(path)
		if stat then
			log.debug("Found compile_commands.json at %s", dir)
			return dir
		end
	end

	return nil
end

--- Resolve the clangd binary path.
---@param cfg_cmd? string user-configured clangd path
---@return string|nil
local function resolve_clangd(cfg_cmd)
	if cfg_cmd then
		if vim.fn.executable(cfg_cmd) == 1 then
			return cfg_cmd
		end
		log.error("Configured clangd path not executable: %s", cfg_cmd)
		return nil
	end

	if vim.fn.executable("clangd") == 1 then
		return "clangd"
	end

	log.error("clangd not found in PATH")
	return nil
end

--- Build the clangd command with optimized flags.
---@param cfg UnrealiumConfig
---@param intel_settings table
---@return string[]|nil
local function build_cmd(cfg, intel_settings)
	local clangd = resolve_clangd(intel_settings.cmd)
	if not clangd then
		return nil
	end

	local cmd = { clangd }

	for _, flag in ipairs(BASE_FLAGS) do
		table.insert(cmd, flag)
	end

	local cc_dir = find_compile_commands(cfg)
	if cc_dir then
		table.insert(cmd, "--compile-commands-dir=" .. cc_dir)
	else
		log.warn("No compile_commands.json found. Run :UE generate clang-database to generate one.")
	end

	if intel_settings.extra_flags then
		for _, flag in ipairs(intel_settings.extra_flags) do
			table.insert(cmd, flag)
		end
	end

	return cmd
end

--- Stop any non-unrealium clangd clients.
---@return integer count of clients stopped
local function stop_external_clangd()
	local stopped = 0
	local clients = vim.lsp.get_clients()
	for _, client in ipairs(clients) do
		if client.name ~= "unrealium-clangd" and client.name:find("clangd") then
			log.info("Stopping external clangd client: %s (id %d)", client.name, client.id)
			client:stop()
			stopped = stopped + 1
		end
	end
	return stopped
end

--- Start clangd with optimized flags.
---@param cfg UnrealiumConfig
---@param intel_settings? table
function M.start(cfg, intel_settings)
	if _client_id then
		local client = vim.lsp.get_client_by_id(_client_id)
		if client then
			log.info("clangd is already running (client %d)", _client_id)
			return
		end
		_client_id = nil
	end

	intel_settings = intel_settings or {}
	local cmd = build_cmd(cfg, intel_settings)
	if not cmd then
		return
	end

	log.info("Starting clangd: %s", table.concat(cmd, " "))

	_client_id = vim.lsp.start({
		name = "unrealium-clangd",
		cmd = cmd,
		root_dir = cfg.Project.Folder,
		filetypes = { "c", "cpp", "objc", "objcpp" },
		on_attach = function(_, bufnr)
			log.debug("clangd attached to buffer %d", bufnr)
			event.emit(event.LSP_READY, { client_id = _client_id })
		end,
	})

	if not _client_id then
		log.error("Failed to start clangd")
		return
	end

	if intel_settings.exclusive then
		stop_external_clangd()
		-- Guard against external clangd clients that start after ours
		if not _exclusive_autocmd_id then
			local group = vim.api.nvim_create_augroup("UnrealiumExclusive", { clear = true })
			_exclusive_autocmd_id = vim.api.nvim_create_autocmd("LspAttach", {
				group = group,
				desc = "Stop external clangd clients (exclusive mode)",
				callback = function(args)
					local client = vim.lsp.get_client_by_id(args.data.client_id)
					if client and client.name ~= "unrealium-clangd" and client.name:find("clangd") then
						log.info("Stopping external clangd client: %s (id %d) [exclusive mode]", client.name, client.id)
						client:stop()
					end
				end,
			})
		end
	end
end

--- Stop the running clangd client.
function M.stop()
	if not _client_id then
		log.info("clangd is not running")
		return
	end

	local client = vim.lsp.get_client_by_id(_client_id)
	if client then
		client.stop()
		log.info("Stopped clangd (client %d)", _client_id)
	end
	_client_id = nil
	if _exclusive_autocmd_id then
		vim.api.nvim_del_autocmd(_exclusive_autocmd_id)
		_exclusive_autocmd_id = nil
	end
end

--- Restart clangd.
---@param cfg UnrealiumConfig
---@param intel_settings? table
function M.restart(cfg, intel_settings)
	M.stop()
	-- Defer start to let the old client shut down
	vim.defer_fn(function()
		M.start(cfg, intel_settings)
	end, 200)
end

--- Attach the running clangd client to a buffer.
---@param bufnr integer
---@return boolean success
function M.buf_attach(bufnr)
	if not _client_id then
		log.warn("clangd is not running, cannot attach to buffer %d", bufnr)
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

--- Check if clangd is currently running.
---@return boolean
function M.is_running()
	if not _client_id then
		return false
	end
	local client = vim.lsp.get_client_by_id(_client_id)
	return client ~= nil
end

--- Get the current status.
---@return { running: boolean, client_id: integer|nil }
function M.status()
	return {
		running = M.is_running(),
		client_id = _client_id,
	}
end

--- Register a BufReadPost autocmd to auto-start clangd on first C++ buffer.
---@param cfg UnrealiumConfig
---@param intel_settings table
function M.register_auto_start(cfg, intel_settings)
	if _autocmd_id then
		return
	end

	local group = vim.api.nvim_create_augroup("UnrealiumIntel", { clear = true })
	_autocmd_id = vim.api.nvim_create_autocmd("BufReadPost", {
		group = group,
		pattern = { "*.h", "*.hpp", "*.cpp", "*.cc" },
		desc = "Auto-start clangd for Unreal C++ files",
		callback = function(args)
			-- Only trigger for files within the project or engine tree
			local file = args.file
			if not vim.startswith(file, cfg.Project.Folder) and not vim.startswith(file, cfg.Engine.Folder) then
				return
			end

			-- Delete this autocmd after first trigger
			vim.api.nvim_del_autocmd(_autocmd_id)
			_autocmd_id = nil

			M.start(cfg, intel_settings)
		end,
	})
end

if _TEST then
	M._find_compile_commands = find_compile_commands
	M._resolve_clangd = resolve_clangd
	M._build_cmd = build_cmd
	M._stop_external_clangd = stop_external_clangd
	M._reset = function()
		_client_id = nil
		_autocmd_id = nil
	end
end

return M
