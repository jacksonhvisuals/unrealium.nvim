local augroup = vim.api.nvim_create_augroup("Unrealium", { clear = true })

local function main()
	print("Unrealium initializing...")
	print("Initialization complete.")
	require("unrealium.configuration").getUnrealiumConfig()
end

local function setup()
	vim.api.nvim_create_autocmd("VimEnter", {
		group = augroup,
		desc = "Configures basic mechanisms for Unrealium.",
		once = true,
		callback = main,
	})
end

return { setup = setup }
