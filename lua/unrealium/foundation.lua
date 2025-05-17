local M = {}

function M.logMessage(message)
	vim.notify(message, vim.log.levels.INFO)
end

function M.logError(message)
	vim.notify(message, vim.log.levels.ERROR)
end

return M
