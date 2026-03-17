---@module 'luassert'

_TEST = true
local tUtil = require("tests.test_util")

describe("modules.intel", function()
	local intel = require("unrealium.modules.intel")
	local lsp = require("unrealium.core.lsp")

	before_each(function()
		lsp._reset()
	end)

	describe("commands", function()
		it("exposes setup subcommand", function()
			assert.truthy(intel.commands.intel.subcommands["setup"])
		end)

		it("exposes setup-clangd subcommand", function()
			assert.truthy(intel.commands.intel.subcommands["setup-clangd"])
		end)

		it("exposes setup-unrealisense subcommand", function()
			assert.truthy(intel.commands.intel.subcommands["setup-unrealisense"])
		end)

		it("exposes status subcommand", function()
			assert.truthy(intel.commands.intel.subcommands["status"])
		end)

		it("exposes restart subcommand", function()
			assert.truthy(intel.commands.intel.subcommands["restart"])
		end)

		it("exposes stop subcommand", function()
			assert.truthy(intel.commands.intel.subcommands["stop"])
		end)
	end)

	describe("get_server_name", function()
		it("defaults to clangd when no intel config", function()
			local config = require("unrealium.core.config")
			local orig_get = config.get
			config.get = function()
				return tUtil.mock_config()
			end

			local name = intel._get_server_name()
			assert.equals("clangd", name)

			config.get = orig_get
		end)

		it("returns unrealisense when configured", function()
			local config = require("unrealium.core.config")
			local orig_get = config.get
			config.get = function()
				return tUtil.mock_config({
					settings = {
						intel = { server = "unrealisense" },
					},
				})
			end

			local name = intel._get_server_name()
			assert.equals("unrealisense", name)

			config.get = orig_get
		end)
	end)

	describe("server_settings", function()
		it("returns clangd settings when server is clangd", function()
			local config = require("unrealium.core.config")
			local orig_get = config.get
			config.get = function()
				return tUtil.mock_config({
					settings = {
						intel = {
							server = "clangd",
							clangd = {
								enabled = true,
								auto_start = true,
								cmd = "/usr/bin/clangd-17",
							},
						},
					},
				})
			end

			local settings = intel._server_settings("clangd")
			assert.is_true(settings.enabled)
			assert.equals("/usr/bin/clangd-17", settings.cmd)

			config.get = orig_get
		end)

		it("returns unrealisense settings when server is unrealisense", function()
			local config = require("unrealium.core.config")
			local orig_get = config.get
			config.get = function()
				return tUtil.mock_config({
					settings = {
						intel = {
							server = "unrealisense",
							unrealisense = {
								auto_start = true,
								cmd = "/usr/local/bin/unrealisense",
							},
						},
					},
				})
			end

			local settings = intel._server_settings("unrealisense")
			assert.equals("/usr/local/bin/unrealisense", settings.cmd)

			config.get = orig_get
		end)
	end)

	describe("setup", function()
		it("does nothing when clangd is disabled", function()
			local config_gen = require("unrealium.core.lsp.config_gen")
			local gen_called = false
			local orig_gen = config_gen.generate
			config_gen.generate = function()
				gen_called = true
			end

			local cfg = tUtil.mock_config({
				settings = {
					intel = {
						server = "clangd",
						clangd = { enabled = false },
					},
				},
			})
			intel.setup(cfg)
			assert.is_false(gen_called)

			config_gen.generate = orig_gen
		end)

		it("generates clangd config and registers auto-start when clangd enabled", function()
			local config_gen = require("unrealium.core.lsp.config_gen")
			local gen_called = false
			local orig_gen = config_gen.generate
			config_gen.generate = function()
				gen_called = true
			end

			local auto_start_called = false
			local auto_start_server = nil
			local orig_auto = lsp.register_auto_start
			lsp.register_auto_start = function(_, _, server)
				auto_start_called = true
				auto_start_server = server
			end

			local cfg = tUtil.mock_config({
				settings = {
					intel = {
						server = "clangd",
						clangd = { enabled = true, auto_start = true, generate_config = true },
					},
				},
			})
			intel.setup(cfg)
			assert.is_true(gen_called)
			assert.is_true(auto_start_called)
			assert.equals("clangd", auto_start_server)

			config_gen.generate = orig_gen
			lsp.register_auto_start = orig_auto
		end)

		it("generates unrealisense config when server is unrealisense", function()
			local uis_config_gen = require("unrealium.core.lsp.unrealisense_config_gen")
			local gen_called = false
			local orig_gen = uis_config_gen.generate
			uis_config_gen.generate = function()
				gen_called = true
			end

			local auto_start_called = false
			local auto_start_server = nil
			local orig_auto = lsp.register_auto_start
			lsp.register_auto_start = function(_, _, server)
				auto_start_called = true
				auto_start_server = server
			end

			local cfg = tUtil.mock_config({
				settings = {
					intel = {
						server = "unrealisense",
						unrealisense = { auto_start = true, generate_config = true },
					},
				},
			})
			intel.setup(cfg)
			assert.is_true(gen_called)
			assert.is_true(auto_start_called)
			assert.equals("unrealisense", auto_start_server)

			uis_config_gen.generate = orig_gen
			lsp.register_auto_start = orig_auto
		end)
	end)
end)
