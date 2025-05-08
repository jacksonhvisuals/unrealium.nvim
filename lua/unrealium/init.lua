local augroup = vim.api.nvim_create_augroup("Unrealium", { clear = true })

local function init()
	local configuration = require("unrealium.configuration")

	if configuration._directoryHasUProject() then
		print("Unrealium initializing...")
		local config = configuration.getUnrealiumConfig()
		vim.g.UnrealiumEnginePath = configuration._getEngineDirectory(config)
		print("Engine Path is: " .. vim.g.UnrealiumEnginePath)
		print("Initialization complete.")
	end
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
