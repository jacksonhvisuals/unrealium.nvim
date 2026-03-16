---@module 'luassert'

_TEST = true
local build = require("unrealium.modules.build")
local run = require("unrealium.modules.run")
local config = require("unrealium.core.config")
local event = require("unrealium.core.event")
local job = require("unrealium.core.job")
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

	describe("build-and-run", function()
		local original_get

		before_each(function()
			build._reset()
			job._reset()
			event.clear()
			original_get = config.get
		end)

		after_each(function()
			config.get = original_get
		end)

		it("calls build.execute and registers BUILD_END listener", function()
			local cfg = tUtil.mock_config()
			config.get = function()
				return cfg
			end

			local build_called = false
			local orig_execute = build.execute
			build.execute = function(_arg, _bang)
				build_called = true
			end

			run._build_then_run(nil, nil, nil)

			build.execute = orig_execute

			assert.is_true(build_called)
			-- Verify a BUILD_END listener was registered
			local listeners = event._listeners()
			assert.truthy(listeners[event.BUILD_END])
			assert.equals(1, #listeners[event.BUILD_END])
		end)

		it("launches editor on build success (exit_code == 0)", function()
			local cfg = tUtil.mock_config()
			config.get = function()
				return cfg
			end

			local editor_launched = false
			local plat = require("unrealium.core.platform")
			local orig_run_command = plat.run_command
			plat.run_command = function(_cfg, t, _args)
				editor_launched = true
				return { command = "echo 'test'" }
			end

			local orig_execute = build.execute
			build.execute = function(_arg, _bang)
				-- Simulate build completing successfully
				event.emit(event.BUILD_END, { exit_code = 0 })
			end

			run._build_then_run(nil, nil, nil)

			build.execute = orig_execute
			plat.run_command = orig_run_command

			assert.is_true(editor_launched)
		end)

		it("does not launch editor on build failure", function()
			local cfg = tUtil.mock_config()
			config.get = function()
				return cfg
			end

			local editor_launched = false
			local plat = require("unrealium.core.platform")
			local orig_run_command = plat.run_command
			plat.run_command = function(_cfg, t, _args)
				editor_launched = true
				return { command = "echo 'test'" }
			end

			local orig_execute = build.execute
			build.execute = function(_arg, _bang)
				-- Simulate build failing
				event.emit(event.BUILD_END, { exit_code = 1 })
			end

			run._build_then_run(nil, nil, nil)

			build.execute = orig_execute
			plat.run_command = orig_run_command

			assert.is_false(editor_launched)
		end)

		it("refuses when a build is already running", function()
			local cfg = tUtil.mock_config()
			config.get = function()
				return cfg
			end

			-- Simulate an active job by starting one
			local orig_is_running = job.is_running
			job.is_running = function()
				return true
			end

			local build_called = false
			local orig_execute = build.execute
			build.execute = function(_arg, _bang)
				build_called = true
			end

			run._build_then_run(nil, nil, nil)

			job.is_running = orig_is_running
			build.execute = orig_execute

			assert.is_false(build_called)
		end)

		it("build_first = true triggers build before run", function()
			local cfg = tUtil.mock_config({
				settings = { run = { build_first = true } },
			})
			config.get = function()
				return cfg
			end

			local build_called = false
			local orig_execute = build.execute
			build.execute = function(_arg, _bang)
				build_called = true
			end

			-- Call execute without _skip_build — should trigger build_then_run
			run.execute(nil, nil)

			build.execute = orig_execute

			assert.is_true(build_called)
		end)

		it("build_first = false (default) goes straight to run", function()
			local cfg = tUtil.mock_config({
				settings = { run = { build_first = false, default_type = "Development" } },
			})
			config.get = function()
				return cfg
			end

			local build_called = false
			local orig_execute = build.execute
			build.execute = function(_arg, _bang)
				build_called = true
			end

			local editor_launched = false
			local plat = require("unrealium.core.platform")
			local orig_run_command = plat.run_command
			plat.run_command = function(_cfg, t, _args)
				editor_launched = true
				return { command = "echo 'test'" }
			end

			run.execute(nil, nil)

			build.execute = orig_execute
			plat.run_command = orig_run_command

			assert.is_false(build_called)
			assert.is_true(editor_launched)
		end)

		it("unsubscribes BUILD_END listener after firing", function()
			local cfg = tUtil.mock_config()
			config.get = function()
				return cfg
			end

			local plat = require("unrealium.core.platform")
			local orig_run_command = plat.run_command
			plat.run_command = function(_cfg, t, _args)
				return { command = "echo 'test'" }
			end

			local orig_execute = build.execute
			build.execute = function(_arg, _bang)
				-- Simulate build completing
				event.emit(event.BUILD_END, { exit_code = 0 })
			end

			run._build_then_run(nil, nil, nil)

			build.execute = orig_execute
			plat.run_command = orig_run_command

			-- After the callback fired and unsubscribed, listeners should be empty
			local listeners = event._listeners()
			assert.equals(0, #(listeners[event.BUILD_END] or {}))
		end)
	end)
end)
