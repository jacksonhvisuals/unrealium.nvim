---@module 'luassert'

_TEST = true
local tUtil = require("tests.test_util")

describe("core.lsp.unrealisense_config_gen", function()
	local config_gen = require("unrealium.core.lsp.unrealisense_config_gen")

	describe("build_config", function()
		it("includes engine source path", function()
			local cfg = tUtil.mock_config()
			local content = config_gen._build_config(cfg)
			assert.matches('engine_path = "/tmp/test/Engine/Engine/Source"', content, 1, true)
		end)
	end)

	describe("generate", function()
		it("creates .unrealisense.toml at project root", function()
			local tmp = vim.fn.tempname()
			vim.fn.mkdir(tmp, "p")

			local cfg = tUtil.mock_config({ Project = { Folder = tmp } })
			local ok = config_gen.generate(cfg, true)
			assert.is_true(ok)

			local stat = vim.uv.fs_stat(tmp .. "/.unrealisense.toml")
			assert.truthy(stat)

			-- Verify content
			local f = io.open(tmp .. "/.unrealisense.toml", "r")
			local content = f:read("*a")
			f:close()
			assert.matches("engine_path", content)

			vim.fn.delete(tmp, "rf")
		end)

		it("does not overwrite existing file without force", function()
			local tmp = vim.fn.tempname()
			vim.fn.mkdir(tmp, "p")

			-- Create existing file
			local f = io.open(tmp .. "/.unrealisense.toml", "w")
			f:write("existing content")
			f:close()

			local cfg = tUtil.mock_config({ Project = { Folder = tmp } })
			local ok = config_gen.generate(cfg, false)
			assert.is_true(ok)

			-- Verify content unchanged
			f = io.open(tmp .. "/.unrealisense.toml", "r")
			local content = f:read("*a")
			f:close()
			assert.equals("existing content", content)

			vim.fn.delete(tmp, "rf")
		end)

		it("overwrites existing file with force", function()
			local tmp = vim.fn.tempname()
			vim.fn.mkdir(tmp, "p")

			-- Create existing file
			local f = io.open(tmp .. "/.unrealisense.toml", "w")
			f:write("existing content")
			f:close()

			local cfg = tUtil.mock_config({ Project = { Folder = tmp } })
			local ok = config_gen.generate(cfg, true)
			assert.is_true(ok)

			-- Verify content changed
			f = io.open(tmp .. "/.unrealisense.toml", "r")
			local content = f:read("*a")
			f:close()
			assert.matches("engine_path", content)

			vim.fn.delete(tmp, "rf")
		end)
	end)
end)
