#!/usr/bin/env -S nvim -l

vim.env.LAZY_STDPATH = ".tests"
load(vim.fn.system("curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua"))()

-- Setup lazy.nvim
require("lazy.minit").setup({
	spec = {
		{ "nvim-telescope/telescope.nvim", dependencies = { "nvim-lua/plenary.nvim" } },
		{ "radenling/vim-dispatch-neovim", dependencies = { "tpope/vim-dispatch" } },
		{
			"nvim-treesitter/nvim-treesitter",
			build = function()
				require("nvim-treesitter.install").install({ "cpp" })
			end,
		},
		{
			"echasnovski/mini.test",
			opts = {
				collect = {
					find_files = function()
						return #_G.arg > 0 and _G.arg or vim.fn.globpath("lua/tests", "**/*_spec.lua", true, true)
					end,
				},
			},
		},
		{ dir = vim.uv.cwd() },
	},
})

-- Make system-installed treesitter parsers available in the sandboxed test env.
-- Tests that need specific parsers use has_cpp_parser() guards and skip gracefully in CI.
local sys_parser_dir = vim.fn.expand("~/.local/share/nvim/site")
if vim.uv.fs_stat(sys_parser_dir) then
	vim.opt.runtimepath:append(sys_parser_dir)
end
