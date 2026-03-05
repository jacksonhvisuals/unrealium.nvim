---@module 'luassert'

_TEST = true
local tUtil = require("tests.test_util")

describe("core.lsp.config_gen", function()
	local config_gen = require("unrealium.core.lsp.config_gen")

	describe("generate", function()
		it("creates .clangd file at project root", function()
			local tmp = vim.fn.tempname()
			vim.fn.mkdir(tmp, "p")

			local cfg = tUtil.mock_config({ Project = { Folder = tmp } })
			local ok = config_gen.generate(cfg)
			assert.is_true(ok)

			local path = tmp .. "/.clangd"
			local stat = vim.uv.fs_stat(path)
			assert.truthy(stat)

			local f = io.open(path, "r")
			local content = f:read("*a")
			f:close()

			assert.matches("CompileFlags:", content)
			assert.matches("__INTELLISENSE__", content)
			assert.matches("ThirdParty", content)
			assert.matches("Intermediate", content)
			assert.matches("Background: Skip", content)

			vim.fn.delete(tmp, "rf")
		end)

		it("skips generation if file exists and force is false", function()
			local tmp = vim.fn.tempname()
			vim.fn.mkdir(tmp, "p")

			-- Write existing file
			local path = tmp .. "/.clangd"
			local f = io.open(path, "w")
			f:write("existing content")
			f:close()

			local cfg = tUtil.mock_config({ Project = { Folder = tmp } })
			local ok = config_gen.generate(cfg)
			assert.is_true(ok)

			-- Verify content was NOT overwritten
			f = io.open(path, "r")
			local content = f:read("*a")
			f:close()
			assert.equals("existing content", content)

			vim.fn.delete(tmp, "rf")
		end)

		it("overwrites existing file when force is true", function()
			local tmp = vim.fn.tempname()
			vim.fn.mkdir(tmp, "p")

			-- Write existing file
			local path = tmp .. "/.clangd"
			local f = io.open(path, "w")
			f:write("existing content")
			f:close()

			local cfg = tUtil.mock_config({ Project = { Folder = tmp } })
			local ok = config_gen.generate(cfg, true)
			assert.is_true(ok)

			-- Verify content WAS overwritten
			f = io.open(path, "r")
			local content = f:read("*a")
			f:close()
			assert.matches("CompileFlags:", content)

			vim.fn.delete(tmp, "rf")
		end)
	end)
end)
