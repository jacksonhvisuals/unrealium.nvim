local augroup = vim.api.nvim_create_augroup("Unrealium", { clear = true })

local function init()
	print("Unrealium initializing...")
	local configuration = require("unrealium.configuration")

	if configuration._directoryHasUProject() then
		local config = configuration.getUnrealiumConfig()
		vim.g.Unrealium = vim.g.Unrealium or {}
		local enginePathValue = configuration._getEngineDirectory(config)
		vim.g.Unrealium.EnginePath = enginePathValue
		print("Engine Path is: " .. enginePathValue)
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
