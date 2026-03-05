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
		it("exposes setup-clangd subcommand", function()
			assert.truthy(intel.commands.intel.subcommands["setup-clangd"])
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

	describe("intel_settings", function()
		it("returns empty table when no intel config", function()
			-- Mock config.get to return a config without intel settings
			local config = require("unrealium.core.config")
			local orig_get = config.get
			config.get = function()
				return tUtil.mock_config()
			end

			local settings = intel._intel_settings()
			assert.same({}, settings)

			config.get = orig_get
		end)

		it("returns clangd settings when present", function()
			local config = require("unrealium.core.config")
			local orig_get = config.get
			config.get = function()
				return tUtil.mock_config({
					settings = {
						intel = {
							clangd = {
								enabled = true,
								auto_start = true,
								cmd = "/usr/bin/clangd-17",
							},
						},
					},
				})
			end

			local settings = intel._intel_settings()
			assert.is_true(settings.enabled)
			assert.is_true(settings.auto_start)
			assert.equals("/usr/bin/clangd-17", settings.cmd)

			config.get = orig_get
		end)
	end)

	describe("setup", function()
		it("does nothing when intel is disabled", function()
			local config_gen = require("unrealium.core.lsp.config_gen")
			local gen_called = false
			local orig_gen = config_gen.generate
			config_gen.generate = function()
				gen_called = true
			end

			local cfg = tUtil.mock_config({
				settings = {
					intel = {
						clangd = { enabled = false },
					},
				},
			})
			intel.setup(cfg)
			assert.is_false(gen_called)

			config_gen.generate = orig_gen
		end)

		it("generates config and registers auto-start when enabled", function()
			local config_gen = require("unrealium.core.lsp.config_gen")
			local gen_called = false
			local orig_gen = config_gen.generate
			config_gen.generate = function()
				gen_called = true
			end

			local auto_start_called = false
			local orig_auto = lsp.register_auto_start
			lsp.register_auto_start = function()
				auto_start_called = true
			end

			local cfg = tUtil.mock_config({
				settings = {
					intel = {
						clangd = { enabled = true, auto_start = true, generate_config = true },
					},
				},
			})
			intel.setup(cfg)
			assert.is_true(gen_called)
			assert.is_true(auto_start_called)

			config_gen.generate = orig_gen
			lsp.register_auto_start = orig_auto
		end)
	end)
end)
