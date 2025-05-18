local augroup = vim.api.nvim_create_augroup("Unrealium", { clear = true })

local function init()
	local configuration = require("unrealium.configuration")

	UnrealiumConfig = configuration.get()
	if not UnrealiumConfig then
		return
	end

	print("Initialization complete for uProject: " .. UnrealiumConfig.ProjectName)
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
