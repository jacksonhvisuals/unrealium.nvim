--- UI backend auto-detection and dispatch.

local M = {}

local picker = require("unrealium.core.ui.picker")

--- Pick items using the best available backend.
---@param opts { mode: string, dirs?: string[], title?: string, search?: string, exclude?: string[] }
function M.pick(opts)
	picker.pick(opts)
end

--- Get the name of the active picker backend.
---@return string
function M.active_backend()
	return picker.active_backend()
end

return M
