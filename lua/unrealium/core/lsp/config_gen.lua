--- .clangd config file generation with optimized settings for Unreal Engine.

local M = {}

local log = require("unrealium.core.log").get("intel")

--- Build the .clangd config content from settings.
---@param cfg UnrealiumConfig
---@return string
local function build_config(cfg)
	local config_gen = cfg.settings
		and cfg.settings.intel
		and cfg.settings.intel.clangd
		and cfg.settings.intel.clangd.config_gen

	local compile_flags = { "-D__INTELLISENSE__", "-Wno-unknown-pragmas" }
	if config_gen and config_gen.extra_compile_flags then
		for _, flag in ipairs(config_gen.extra_compile_flags) do
			table.insert(compile_flags, flag)
		end
	end

	local exclude_paths = { "ThirdParty", "Intermediate" }
	if config_gen and config_gen.exclude_paths then
		exclude_paths = config_gen.exclude_paths
	end

	local lines = { "CompileFlags:", "  Add:" }
	for _, flag in ipairs(compile_flags) do
		table.insert(lines, "    - " .. flag)
	end
	table.insert(lines, "")
	table.insert(lines, "Index:")
	table.insert(lines, "  Background: Build")

	for _, path in ipairs(exclude_paths) do
		table.insert(lines, "")
		table.insert(lines, "---")
		table.insert(lines, "If:")
		table.insert(lines, string.format("  PathMatch: .*/%s/.*", path))
		table.insert(lines, "  Index:")
		table.insert(lines, "    Background: Skip")
	end
	table.insert(lines, "")

	return table.concat(lines, "\n")
end

--- Generate an optimized .clangd config at the project root.
---@param cfg UnrealiumConfig
---@param force? boolean overwrite existing file
---@return boolean success
function M.generate(cfg, force)
	local path = cfg.Project.Folder .. "/.clangd"

	if not force then
		local stat = vim.uv.fs_stat(path)
		if stat then
			log.debug(".clangd already exists at %s, skipping generation", path)
			return true
		end
	end

	local fd, err = io.open(path, "w")
	if not fd then
		log.error("Failed to write .clangd: %s", err)
		return false
	end

	fd:write(build_config(cfg))
	fd:close()

	log.info("Generated .clangd at %s", path)
	return true
end

return M
