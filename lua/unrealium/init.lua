local augroup = vim.api.nvim_create_augroup("Unrealium", { clear = true })

local function init()
	print("Unrealium initializing...")
	local configuration = require("unrealium.configuration")

	if configuration._directoryHasUProject() then
		local config = configuration.getUnrealiumConfig()
		print(configuration._getEngineDirectory(config))
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
