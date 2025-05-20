local augroup = vim.api.nvim_create_augroup("Unrealium", { clear = true })

local function init()
	local configuration = require("unrealium.configuration")

	UnrealiumConfig = configuration.get()
	if not UnrealiumConfig then
		return
	end

	vim.api.nvim_create_user_command("UShowActions", function(opts)
		require("unrealium.ui").ShowUnrealiumActions(opts)
	end, {})

	vim.api.nvim_create_user_command("UGenProjectFiles", function(opts)
		require("unrealium.commands").uGenerateProjectFiles(opts)
	end, {})

	vim.api.nvim_create_user_command("UBuild", function(opts)
		require("unrealium.commands").uBuild(opts)
	end, {})

	vim.api.nvim_create_user_command("URun", function(opts)
		require("unrealium.commands").uRun(opts)
	end, {})

	vim.api.nvim_create_user_command("UDebug", function(opts)
		require("unrealium.commands").uDebug(opts)
	end, {})
end

local function setup()
	vim.api.nvim_create_autocmd("VimEnter", {
		group = augroup,
		desc = "Configures basic mechanisms for Unrealium.",
		once = true,
		callback = init,
	})
end

return { setup = setup }
