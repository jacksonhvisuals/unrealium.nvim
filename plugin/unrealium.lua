if 1 ~= vim.fn.has("nvim-0.10.0") then
	vim.api.nvim_echo({ { "Unrealium requires at least nvim-0.10.0" } }, true, {})
	return
end

-- Ensure that Unrealium hasn't already initialized
if vim.g.unrealium_loaded == 1 then
	return
end
vim.g.unrealium_loaded = 1

-- Set up Unrealium commands
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

function setup(args)
	print("Setting up Unrealium plugin.")
end
