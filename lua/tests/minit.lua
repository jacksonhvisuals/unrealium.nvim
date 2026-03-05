#!/usr/bin/env -S nvim -l

vim.env.LAZY_STDPATH = ".tests"
load(vim.fn.system("curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua"))()

-- Setup lazy.nvim
require("lazy.minit").setup({
	spec = {
		{ "nvim-telescope/telescope.nvim", dependencies = { "nvim-lua/plenary.nvim" } },
		{ "radenling/vim-dispatch-neovim", dependencies = { "tpope/vim-dispatch" } },
		{
			"echasnovski/mini.test",
			opts = {
				collect = {
					find_files = function()
						return #_G.arg > 0 and _G.arg
							or vim.fn.globpath("lua/tests", "**/*_spec.lua", true, true)
					end,
				},
			},
		},
		{ dir = vim.uv.cwd() },
	},
})
