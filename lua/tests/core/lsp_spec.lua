---@module 'luassert'

_TEST = true
local tUtil = require("tests.test_util")

describe("core.lsp", function()
	local lsp = require("unrealium.core.lsp")

	before_each(function()
		lsp._reset()
	end)

	describe("resolve_clangd", function()
		it("returns configured path when executable", function()
			-- Stub vim.fn.executable to return 1 for our path
			local orig = vim.fn.executable
			vim.fn.executable = function(cmd)
				if cmd == "/usr/bin/clangd-17" then
					return 1
				end
				return 0
			end

			local result = lsp._resolve_clangd("/usr/bin/clangd-17")
			assert.equals("/usr/bin/clangd-17", result)

			vim.fn.executable = orig
		end)

		it("returns nil when configured path is not executable", function()
			local orig = vim.fn.executable
			vim.fn.executable = function(_)
				return 0
			end

			local result = lsp._resolve_clangd("/nonexistent/clangd")
			assert.is_nil(result)

			vim.fn.executable = orig
		end)

		it("falls back to PATH clangd when no config", function()
			local orig = vim.fn.executable
			vim.fn.executable = function(cmd)
				if cmd == "clangd" then
					return 1
				end
				return 0
			end

			local result = lsp._resolve_clangd(nil)
			assert.equals("clangd", result)

			vim.fn.executable = orig
		end)

		it("returns nil when clangd not in PATH and no config", function()
			local orig = vim.fn.executable
			vim.fn.executable = function(_)
				return 0
			end

			local result = lsp._resolve_clangd(nil)
			assert.is_nil(result)

			vim.fn.executable = orig
		end)
	end)

	describe("find_compile_commands", function()
		it("finds compile_commands.json in project folder", function()
			local tmp = vim.fn.tempname()
			vim.fn.mkdir(tmp, "p")
			local f = io.open(tmp .. "/compile_commands.json", "w")
			f:write("[]")
			f:close()

			local cfg = tUtil.mock_config({ Project = { Folder = tmp } })
			local result = lsp._find_compile_commands(cfg)
			assert.equals(tmp, result)

			os.remove(tmp .. "/compile_commands.json")
			vim.fn.delete(tmp, "rf")
		end)

		it("finds compile_commands.json in Intermediate subdir", function()
			local tmp = vim.fn.tempname()
			local intermediate = tmp .. "/Intermediate"
			vim.fn.mkdir(intermediate, "p")
			local f = io.open(intermediate .. "/compile_commands.json", "w")
			f:write("[]")
			f:close()

			local cfg = tUtil.mock_config({ Project = { Folder = tmp } })
			local result = lsp._find_compile_commands(cfg)
			assert.equals(intermediate, result)

			vim.fn.delete(tmp, "rf")
		end)

		it("returns nil when not found", function()
			local tmp = vim.fn.tempname()
			vim.fn.mkdir(tmp, "p")

			local cfg = tUtil.mock_config({ Project = { Folder = tmp } })
			local result = lsp._find_compile_commands(cfg)
			assert.is_nil(result)

			vim.fn.delete(tmp, "rf")
		end)
	end)

	describe("build_cmd", function()
		it("builds command with base flags", function()
			local orig = vim.fn.executable
			vim.fn.executable = function(_)
				return 1
			end

			local cfg = tUtil.mock_config()
			local cmd = lsp._build_cmd(cfg, {})
			assert.truthy(cmd)
			assert.equals("clangd", cmd[1])
			-- Check that base flags are present
			local flags = table.concat(cmd, " ")
			assert.matches("--background%-index", flags)
			assert.matches("--pch%-storage=memory", flags)
			assert.matches("--header%-insertion=never", flags)

			vim.fn.executable = orig
		end)

		it("includes extra_flags from settings", function()
			local orig = vim.fn.executable
			vim.fn.executable = function(_)
				return 1
			end

			local cfg = tUtil.mock_config()
			local cmd = lsp._build_cmd(cfg, { extra_flags = { "--log=verbose", "-j=4" } })
			assert.truthy(cmd)
			local flags = table.concat(cmd, " ")
			assert.matches("--log=verbose", flags)
			assert.matches("-j=4", flags)

			vim.fn.executable = orig
		end)

		it("returns nil when clangd not found", function()
			local orig = vim.fn.executable
			vim.fn.executable = function(_)
				return 0
			end

			local cfg = tUtil.mock_config()
			local cmd = lsp._build_cmd(cfg, {})
			assert.is_nil(cmd)

			vim.fn.executable = orig
		end)
	end)

	describe("status", function()
		it("reports not running initially", function()
			local status = lsp.status()
			assert.is_false(status.running)
			assert.is_nil(status.client_id)
		end)
	end)

	describe("is_running", function()
		it("returns false when no client started", function()
			assert.is_false(lsp.is_running())
		end)
	end)
end)
