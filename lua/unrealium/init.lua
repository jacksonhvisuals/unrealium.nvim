local M = {}

local function init()
	local configuration = require("unrealium.configuration")
	print("Unrealium initializing")

	UnrealiumConfig = configuration.get()
	if not UnrealiumConfig then
		print("Unrealium Config did not work")
		return
	end
	print("Unrealium initialized")

	vim.api.nvim_exec_autocmds("User", { pattern = "UnrealiumStart" })

	-- WIP using Telescope UI to have a more interactive mechanism to trigger commands
	-- vim.api.nvim_create_user_command("UShowActions", function(opts)
	-- 	require("unrealium.ui").ShowUnrealiumActions(opts)
	-- end, {})

	vim.api.nvim_create_user_command("UGenProjectFiles", function(opts)
		require("unrealium.commands"):UGenerateProjectFiles()
	end, {})

	vim.api.nvim_create_user_command("UGenClangDatabase", function(opts)
		require("unrealium.commands"):UGenerateClangDatabase(unpack(opts.fargs))
	end, {
		nargs = "*",
		complete = function(_, line)
			local gen_types = { "Project", "Engine" }
			return require("unrealium.utils").autocomplete(line, { gen_types })
		end,
	})

	vim.api.nvim_create_user_command("UBuild", function(opts)
		require("unrealium.commands"):UBuild(unpack(opts.fargs))
	end, {
		nargs = "*",
		complete = function(_, line)
			local build_types = { "Development", "Debug" }
			return require("unrealium.utils").autocomplete(line, { build_types })
		end,
	})

	vim.api.nvim_create_user_command("URun", function(opts)
		require("unrealium.commands"):URun(unpack(opts.fargs))
	end, {
		nargs = "*",
		complete = function(_, line)
			local build_types = { "Development", "Debug" }
			return require("unrealium.utils").autocomplete(line, { build_types })
		end,
	})

	vim.api.nvim_create_user_command("USearch", function(opts)
		require("unrealium.commands"):USearch(unpack(opts.fargs))
	end, {
		nargs = "*",
		complete = function(_, line)
			local search_type = { "grep", "file_search" }
			local sources_list = { "Engine", "Project", "All" }
			return require("unrealium.utils").autocomplete(line, { search_type, sources_list })
		end,
	})

	-- Automatically check if newly-opened files should be editable
	vim.api.nvim_create_autocmd("BufReadPost", {
		callback = function()
			local filepath = vim.api.nvim_buf_get_name(0)
			require("unrealium.commands"):DetermineFileEditable(filepath)
		end,
	})
end

function M.setup()
	local augroup = vim.api.nvim_create_augroup("Unrealium", { clear = true })
	vim.api.nvim_create_autocmd("VimEnter", {
		group = augroup,
		desc = "Configures basic mechanisms for Unrealium.",
		once = true,
		callback = init,
	})
end

if _TEST then
	M._init = init
end

return M
