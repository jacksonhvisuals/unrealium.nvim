---@module 'luassert'

_TEST = true
local build = require("unrealium.modules.build")
local run = require("unrealium.modules.run")
local config = require("unrealium.core.config")
local tUtil = require("tests.test_util")

describe("modules.run", function()
	describe("type inference from last build preset", function()
		local original_get

		before_each(function()
			build._reset()
			original_get = config.get
		end)

		after_each(function()
			config.get = original_get
		end)

		it("infers Debug type from editor preset with Debug configuration", function()
			local cfg = tUtil.mock_config()
			config.get = function()
				return cfg
			end

			-- Simulate a Debug editor build
			local preset = {
				name = "MyProjectEditor Linux Debug",
				target_name = "MyProjectEditor",
				platform = "Linux",
				configuration = "Debug",
				is_editor = true,
			}
			-- Set last preset by running the internal build path
			build._set_last_preset(preset)

			-- Capture what run.execute resolves — we stub platform.run_command
			local captured_type
			local platform = require("unrealium.core.platform")
			local orig_run_command = platform.run_command
			platform.run_command = function(_cfg, t, _args)
				captured_type = t
				return { command = "echo 'test'" }
			end

			run.execute(nil, nil)
			platform.run_command = orig_run_command

			assert.equals("Debug", captured_type)
		end)

		it("infers Development type from editor preset with Development configuration", function()
			local cfg = tUtil.mock_config()
			config.get = function()
				return cfg
			end

			local preset = {
				name = "MyProjectEditor Linux Development",
				target_name = "MyProjectEditor",
				platform = "Linux",
				configuration = "Development",
				is_editor = true,
			}
			build._set_last_preset(preset)

			local captured_type
			local platform = require("unrealium.core.platform")
			local orig_run_command = platform.run_command
			platform.run_command = function(_cfg, t, _args)
				captured_type = t
				return { command = "echo 'test'" }
			end

			run.execute(nil, nil)
			platform.run_command = orig_run_command

			assert.equals("Development", captured_type)
		end)

		it("infers Development type from editor preset with DebugGame configuration", function()
			local cfg = tUtil.mock_config()
			config.get = function()
				return cfg
			end

			local preset = {
				name = "MyProjectEditor Linux DebugGame",
				target_name = "MyProjectEditor",
				platform = "Linux",
				configuration = "DebugGame",
				is_editor = true,
			}
			build._set_last_preset(preset)

			local captured_type
			local platform = require("unrealium.core.platform")
			local orig_run_command = platform.run_command
			platform.run_command = function(_cfg, t, _args)
				captured_type = t
				return { command = "echo 'test'" }
			end

			run.execute(nil, nil)
			platform.run_command = orig_run_command

			assert.equals("Development", captured_type)
		end)

		it("falls back to config default for non-editor preset", function()
			local cfg = tUtil.mock_config({
				settings = { run = { default_type = "Development" } },
			})
			config.get = function()
				return cfg
			end

			local preset = {
				name = "MyProject Linux Debug",
				target_name = "MyProject",
				platform = "Linux",
				configuration = "Debug",
				is_editor = false,
			}
			build._set_last_preset(preset)

			local captured_type
			local platform = require("unrealium.core.platform")
			local orig_run_command = platform.run_command
			platform.run_command = function(_cfg, t, _args)
				captured_type = t
				return { command = "echo 'test'" }
			end

			run.execute(nil, nil)
			platform.run_command = orig_run_command

			assert.equals("Development", captured_type)
		end)

		it("falls back to config default when no last preset exists", function()
			local cfg = tUtil.mock_config({
				settings = { run = { default_type = "Development" } },
			})
			config.get = function()
				return cfg
			end

			local captured_type
			local platform = require("unrealium.core.platform")
			local orig_run_command = platform.run_command
			platform.run_command = function(_cfg, t, _args)
				captured_type = t
				return { command = "echo 'test'" }
			end

			run.execute(nil, nil)
			platform.run_command = orig_run_command

			assert.equals("Development", captured_type)
		end)
	end)
end)
