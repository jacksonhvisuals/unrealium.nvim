local G = {}

function G.logMessage(message)
	vim.notify(message, vim.log.levels.INFO)
end

function G.logError(message)
	vim.notify(message, vim.log.levels.ERROR)
end

return G
