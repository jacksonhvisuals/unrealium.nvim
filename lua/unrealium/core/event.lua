--- Pub/sub event bus with vim User autocmd bridge.

local M = {}

-- Event type constants
M.PLUGIN_READY = "unrealium.plugin_ready"
M.BUILD_START = "unrealium.build_start"
M.BUILD_END = "unrealium.build_end"
M.CONFIG_LOADED = "unrealium.config_loaded"
M.BUILD_PROGRESS = "unrealium.build_progress"
M.JOB_START = "unrealium.job_start"
M.JOB_FINISH = "unrealium.job_finish"
M.LSP_READY = "unrealium.lsp_ready"
M.LSP_INDEXED = "unrealium.lsp_indexed"
M.EDITOR_START = "unrealium.editor_start"
M.EDITOR_EXIT = "unrealium.editor_exit"

---@type table<string, fun(data: any)[]>
local _listeners = {}

--- Subscribe to an event.
---@param event string
---@param callback fun(data: any)
---@return fun() unsubscribe function
function M.on(event, callback)
	if not _listeners[event] then
		_listeners[event] = {}
	end
	table.insert(_listeners[event], callback)

	return function()
		local list = _listeners[event]
		if list then
			for i, cb in ipairs(list) do
				if cb == callback then
					table.remove(list, i)
					return
				end
			end
		end
	end
end

--- Emit an event, calling all listeners and firing a vim User autocmd.
---@param event string
---@param data? any
function M.emit(event, data)
	local list = _listeners[event]
	if list then
		for _, cb in ipairs(list) do
			cb(data)
		end
	end

	-- Fire vim User autocmd for external consumers
	-- Use the event name as the pattern (dots replaced with underscores for autocmd compat)
	local pattern = event:gsub("%.", "_")
	pcall(vim.api.nvim_exec_autocmds, "User", { pattern = pattern, data = data })
end

--- Remove all listeners (useful for testing).
function M.clear()
	_listeners = {}
end

if _TEST then
	M._listeners = function()
		return _listeners
	end
end

return M
