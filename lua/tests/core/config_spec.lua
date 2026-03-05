---@module 'luassert'

local tUtil = require("tests.test_util")
local Path = require("plenary.path")

_TEST = true
local config = require("unrealium.core.config")

describe("unrealium.core.config", function()
	local tmp_dir = Path:new("./tmp_config_new"):absolute()

	before_each(function()
		config._reset()
		vim.fn.delete(tmp_dir, "rf")
		vim.fn.mkdir(tmp_dir, "p")
	end)

	after_each(function()
		vim.fn.delete(tmp_dir, "rf")
	end)

	describe("deep_merge", function()
		it("merges nested tables", function()
			local base = { a = { b = 1, c = 2 }, d = 3 }
			local override = { a = { c = 99 }, e = 4 }
			local result = config._deep_merge(base, override)
			assert.equals(1, result.a.b)
			assert.equals(99, result.a.c)
			assert.equals(3, result.d)
			assert.equals(4, result.e)
		end)

		it("does not mutate originals", function()
			local base = { a = { b = 1 } }
			local override = { a = { c = 2 } }
			config._deep_merge(base, override)
			assert.is_nil(base.a.c)
		end)
	end)

	describe("get", function()
		it("returns complete config for valid project", function()
			local engineDir = tmp_dir .. "/Engine"
			vim.fn.mkdir(engineDir, "p")
			vim.fn.mkdir(engineDir .. "/Build", "p")
			vim.fn.mkdir(engineDir .. "/Build/BatchFiles", "p")

			local projDir = tUtil.createValidTree(tmp_dir, engineDir)
			vim.wait(150)

			local cwd = vim.fn.getcwd()
			vim.uv.chdir(projDir)

			config.init()
			local cfg = config.get()

			vim.uv.chdir(cwd)

			assert.truthy(cfg)
			assert.equals("MyTestProject", cfg.Project.Name)
			assert.matches(projDir, cfg.Project.Folder)
			assert.equals(engineDir, cfg.Engine.Folder)
			assert.is_false(cfg.Engine.AllowEngineModifications)
			assert.truthy(cfg.Engine.Scripts.Build)
			assert.truthy(cfg.PlatformName)
		end)

		it("returns nil outside of a project", function()
			config.init()
			local cwd = vim.fn.getcwd()
			vim.uv.chdir(tmp_dir)

			local cfg = config.get()

			vim.uv.chdir(cwd)
			assert.is_nil(cfg)
		end)

		it("caches config on subsequent calls", function()
			local engineDir = tmp_dir .. "/Engine"
			vim.fn.mkdir(engineDir, "p")

			local projDir = tUtil.createValidTree(tmp_dir, engineDir)
			vim.wait(150)

			local cwd = vim.fn.getcwd()
			vim.uv.chdir(projDir)

			config.init()
			local cfg1 = config.get()
			local cfg2 = config.get()

			vim.uv.chdir(cwd)

			-- Should be the exact same table reference
			assert.equals(cfg1, cfg2)
		end)
	end)

	describe("register_defaults", function()
		it("merges sub-module defaults into settings", function()
			config.register_defaults("uep", { scan_interval = 5000 })

			local engineDir = tmp_dir .. "/Engine"
			vim.fn.mkdir(engineDir, "p")

			local projDir = tUtil.createValidTree(tmp_dir, engineDir)
			vim.wait(150)

			local cwd = vim.fn.getcwd()
			vim.uv.chdir(projDir)

			config.init()
			local cfg = config.get()

			vim.uv.chdir(cwd)

			assert.truthy(cfg)
			assert.truthy(cfg.settings.uep)
			assert.equals(5000, cfg.settings.uep.scan_interval)
		end)
	end)

	describe("set", function()
		it("invalidates cache", function()
			local engineDir = tmp_dir .. "/Engine"
			vim.fn.mkdir(engineDir, "p")

			local projDir = tUtil.createValidTree(tmp_dir, engineDir)
			vim.wait(150)

			local cwd = vim.fn.getcwd()
			vim.uv.chdir(projDir)

			config.init()
			local cfg1 = config.get()
			config.set("logging.level", "debug")
			local cfg2 = config.get()

			vim.uv.chdir(cwd)

			-- Should be different table references after invalidation
			assert.are_not.equals(cfg1, cfg2)
		end)
	end)
end)
