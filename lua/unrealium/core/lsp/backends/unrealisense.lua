--- UnrealISense LSP backend for Unreal Engine projects.
--- UnrealISense combines tree-sitter fast indexing with a clangd subprocess.
--- See: https://github.com/jacksonhvisuals/unrealisense

local M = {}

local log = require("unrealium.core.log").get("intel")

--- Resolve the unrealisense binary path.
---@param cfg_cmd? string user-configured binary path
---@return string|nil
function M.resolve_binary(cfg_cmd)
	if cfg_cmd then
		if vim.fn.executable(cfg_cmd) == 1 then
			return cfg_cmd
		end
		log.error("Configured unrealisense path not executable: %s", cfg_cmd)
		return nil
	end

	if vim.fn.executable("unrealisense") == 1 then
		return "unrealisense"
	end

	log.error("unrealisense not found in PATH")
	return nil
end

--- Build the unrealisense command.
---@param cfg UnrealiumConfig
---@param settings table
---@return string[]|nil
function M.build_cmd(cfg, settings)
	local binary = M.resolve_binary(settings.cmd)
	if not binary then
		return nil
	end

	local cmd = { binary }

	local engine_path = settings.engine_path or (cfg.Engine and cfg.Engine.Folder)
	if engine_path then
		vim.list_extend(cmd, { "--engine-path", engine_path })
	end

	for _, arg in ipairs(settings.extra_args or {}) do
		table.insert(cmd, arg)
	end

	return cmd
end

--- Return the LSP client name for this backend.
---@return string
function M.client_name()
	return "unrealium-unrealisense"
end

--- Return the filetypes this backend handles.
---@return string[]
function M.filetypes()
	return { "c", "cpp" }
end

--- Stop any non-unrealium unrealisense and clangd clients.
--- UnrealISense wraps clangd internally, so we stop both to avoid conflicts.
---@return integer count of clients stopped
function M.stop_external()
	local stopped = 0
	local clients = vim.lsp.get_clients()
	for _, client in ipairs(clients) do
		local dominated = (client.name ~= "unrealium-unrealisense" and client.name:find("unrealisense"))
			or (client.name ~= "unrealium-clangd" and client.name:find("clangd"))
		if dominated then
			log.info("Stopping external LSP client: %s (id %d)", client.name, client.id)
			client:stop()
			stopped = stopped + 1
		end
	end
	return stopped
end

return M
