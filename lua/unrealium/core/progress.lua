--- Progress UI: fidget.nvim when available, vim.notify fallback.

local M = {}

---@type table|nil fidget progress handle
local _handle = nil

---@type table|nil handle awaiting user interaction before dismissal
local _pending_handle = nil

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
	if _pending_handle then
		_pending_handle:finish()
		_pending_handle = nil
		pcall(vim.api.nvim_del_augroup_by_name, "unrealium_build_done")
	end

	if has_fidget() then
		local fidget_progress = require("fidget.progress")
		_handle = fidget_progress.handle.create({
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
--- Shows a status icon immediately and defers dismissal until user interaction.
---@param message string
---@param level? integer vim.log.levels value
function M.finish(message, level)
	if _handle then
		local icon = "✓"
		if level == vim.log.levels.ERROR then
			icon = "✗"
		elseif level == vim.log.levels.WARN then
			icon = "⚠"
		end
		_handle.title = icon .. " " .. message
		_handle.percentage = 100
		_pending_handle = _handle
		_handle = nil

		local handle = _pending_handle
		local augroup = vim.api.nvim_create_augroup("unrealium_build_done", { clear = true })
		vim.api.nvim_create_autocmd({ "CursorMoved", "InsertEnter", "CmdlineEnter" }, {
			group = augroup,
			once = true,
			callback = function()
				handle:finish()
				_pending_handle = nil
			end,
		})
	else
		vim.notify("[unrealium] " .. message, level or vim.log.levels.INFO)
	end
end

--- Dismiss any pending notification without waiting for user interaction.
function M.dismiss()
	if _pending_handle then
		_pending_handle:finish()
		_pending_handle = nil
		pcall(vim.api.nvim_del_augroup_by_name, "unrealium_build_done")
	end
end

return M
