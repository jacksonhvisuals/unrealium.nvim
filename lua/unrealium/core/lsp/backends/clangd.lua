--- clangd LSP backend for Unreal Engine projects.

local M = {}

local log = require("unrealium.core.log").get("intel")

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
function M.resolve_binary(cfg_cmd)
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
---@param settings table
---@return string[]|nil
function M.build_cmd(cfg, settings)
	local clangd = M.resolve_binary(settings.cmd)
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

	if settings.extra_flags then
		for _, flag in ipairs(settings.extra_flags) do
			table.insert(cmd, flag)
		end
	end

	return cmd
end

--- Return the LSP client name for this backend.
---@return string
function M.client_name()
	return "unrealium-clangd"
end

--- Return the filetypes this backend handles.
---@return string[]
function M.filetypes()
	return { "c", "cpp", "objc", "objcpp" }
end

--- Stop any non-unrealium clangd clients.
---@return integer count of clients stopped
function M.stop_external()
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

if _TEST then
	M._find_compile_commands = find_compile_commands
end

return M
