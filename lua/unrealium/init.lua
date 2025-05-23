local augroup = vim.api.nvim_create_augroup("Unrealium", { clear = true })

local function init()
	local configuration = require("unrealium.configuration")

	UnrealiumConfig = configuration.get()
	if not UnrealiumConfig then
		return
	end

	-- WIP using Telescope UI to have a more interactive mechanism to trigger commands
	-- vim.api.nvim_create_user_command("UShowActions", function(opts)
	-- 	require("unrealium.ui").ShowUnrealiumActions(opts)
	-- end, {})

	vim.api.nvim_create_user_command("UGenProjectFiles", function(opts)
		require("unrealium.commands"):uGenerateProjectFiles()
	end, {})

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
			local search_type = { "live_grep", "find_files" }
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

local function setup()
	vim.api.nvim_create_autocmd("VimEnter", {
		group = augroup,
		desc = "Configures basic mechanisms for Unrealium.",
		once = true,
		callback = init,
	})
end

return { setup = setup }
