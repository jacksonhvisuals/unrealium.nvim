--- Engine file read-only enforcement via BufReadPost autocmd.

local M = {}

local log = require("unrealium.core.log").get("editor_lock")
local config = require("unrealium.core.config")

M.name = "editor_lock"

--- Check if a file should be read-only and set modifiable accordingly.
---@param file_path string
function M.check_file(file_path)
	local cfg = config.get()
	if not cfg then
		return
	end

	if cfg.Engine.AllowEngineModifications then
		return
	end

	if vim.startswith(file_path, cfg.Engine.Folder) then
		log.debug("Locking engine file: %s", file_path)
		vim.bo.modifiable = false
	end
end

--- Register the BufReadPost autocmd.
---@param cfg UnrealiumConfig
function M.setup(cfg)
	vim.api.nvim_create_autocmd("BufReadPost", {
		group = vim.api.nvim_create_augroup("UnrealiumEditorLock", { clear = true }),
		callback = function()
			local filepath = vim.api.nvim_buf_get_name(0)
			M.check_file(filepath)
		end,
	})
end

return M
