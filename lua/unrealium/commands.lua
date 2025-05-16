local M = {}

-- Registers commands for Unrealium
function M.register()
	vim.api.nvim_create_user_command("UShowActions", function(opts)
		require("unrealium.ui").ShowUnrealiumActions(opts)
	end, {})

	vim.api.nvim_create_user_command("UGenProjectFiles", function(opts)
		require("unrealium.integration").uGenerateProjectFiles(opts)
	end, {})

	vim.api.nvim_create_user_command("UBuild", function(opts)
		require("unrealium.integration").uBuild(opts)
	end, {})

	vim.api.nvim_create_user_command("URun", function(opts)
		require("unrealium.integration").uRun(opts)
	end, {})

	vim.api.nvim_create_user_command("UDebug", function(opts)
		require("unrealium.integration").uDebug(opts)
	end, {})
end

return M
