--- .clangd config file generation with optimized settings for Unreal Engine.

local M = {}

local log = require("unrealium.core.log").get("intel")

local CLANGD_CONFIG = [[CompileFlags:
  Add:
    - -D__INTELLISENSE__
    - -Wno-unknown-pragmas

Index:
  Background: Build

---
If:
  PathMatch: .*/ThirdParty/.*
  Index:
    Background: Skip

---
If:
  PathMatch: .*/Intermediate/.*
  Index:
    Background: Skip
]]

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

	fd:write(CLANGD_CONFIG)
	fd:close()

	log.info("Generated .clangd at %s", path)
	return true
end

return M
