--- .unrealisense.toml config file generation for Unreal Engine projects.

local M = {}

local log = require("unrealium.core.log").get("intel")

--- Build the .unrealisense.toml content from config.
---@param cfg UnrealiumConfig
---@return string
local function build_config(cfg)
	local lines = {}

	local engine_source = cfg.Engine.Folder .. "/Engine/Source"
	table.insert(lines, string.format('engine_path = "%s"', engine_source))
	table.insert(lines, "")

	return table.concat(lines, "\n")
end

--- Generate .unrealisense.toml at the project root.
---@param cfg UnrealiumConfig
---@param force? boolean overwrite existing file
---@return boolean success
function M.generate(cfg, force)
	local path = cfg.Project.Folder .. "/.unrealisense.toml"

	if not force then
		local stat = vim.uv.fs_stat(path)
		if stat then
			log.debug(".unrealisense.toml already exists at %s, skipping generation", path)
			return true
		end
	end

	local fd, err = io.open(path, "w")
	if not fd then
		log.error("Failed to write .unrealisense.toml: %s", err)
		return false
	end

	fd:write(build_config(cfg))
	fd:close()

	log.info("Generated .unrealisense.toml at %s", path)
	return true
end

if _TEST then
	M._build_config = build_config
end

return M
