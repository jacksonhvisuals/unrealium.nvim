--- Progress UI: fidget.nvim when available, vim.notify fallback.

local M = {}

---@type table|nil fidget progress handle
local _handle = nil

---@type boolean|nil
local _has_fidget = nil

--- Check for fidget.nvim availability (cached).
---@return boolean
local function has_fidget()
	if _has_fidget == nil then
		_has_fidget = pcall(require, "fidget")
	end
	return _has_fidget
end

--- Begin a progress indicator.
---@param title string
function M.begin(title)
	if has_fidget() then
		local progress = require("fidget.progress")
		_handle = progress.handle.create({
			title = title,
			lsp_client = { name = "unrealium" },
		})
	else
		vim.notify("[unrealium] " .. title, vim.log.levels.INFO)
	end
end

--- Report progress update.
---@param percentage integer 0-100
---@param message? string
function M.report(percentage, message)
	if _handle then
		_handle.percentage = percentage
		if message then
			_handle.message = message
		end
	end
end

--- Finish the progress indicator.
---@param message string
---@param level? integer vim.log.levels value
function M.finish(message, level)
	if _handle then
		_handle.message = message
		_handle:finish()
		_handle = nil
	else
		vim.notify("[unrealium] " .. message, level or vim.log.levels.INFO)
	end
end

return M
