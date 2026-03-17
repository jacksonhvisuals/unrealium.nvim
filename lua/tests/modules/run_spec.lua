---@module 'luassert'

_TEST = true
local build = require("unrealium.modules.build")
local run = require("unrealium.modules.run")
local config = require("unrealium.core.config")
local event = require("unrealium.core.event")
local job = require("unrealium.core.job")
local progress = require("unrealium.core.progress")
local tUtil = require("tests.test_util")

--- Helper: stub vim functions needed by run.execute's terminal workflow.
--- Returns a table with captured state and the on_exit callback.
---@return table stubs
local function stub_terminal_env()
	local stubs = {
		termopen_called = false,
		termopen_cmd = nil,
		termopen_on_exit = nil,
		cmd_called = nil,
		created_buf = 100,
		prev_win = 1,
		term_win = 2,
		term_job_id = 42,
	}

	-- Track originals
	stubs._orig = {
		termopen = vim.fn.termopen,
		jobstop = vim.fn.jobstop,
		nvim_get_current_win = vim.api.nvim_get_current_win,
		nvim_set_current_win = vim.api.nvim_set_current_win,
		nvim_create_buf = vim.api.nvim_create_buf,
		nvim_set_current_buf = vim.api.nvim_set_current_buf,
		nvim_buf_attach = vim.api.nvim_buf_attach,
		nvim_buf_is_valid = vim.api.nvim_buf_is_valid,
		nvim_win_is_valid = vim.api.nvim_win_is_valid,
		nvim_win_get_buf = vim.api.nvim_win_get_buf,
		nvim_list_wins = vim.api.nvim_list_wins,
		nvim_win_close = vim.api.nvim_win_close,
		nvim_buf_delete = vim.api.nvim_buf_delete,
		vim_cmd = vim.cmd,
		vim_schedule = vim.schedule,
	}

	-- Run vim.schedule callbacks inline in tests
	vim.schedule = function(fn)
		fn()
	end

	-- Install stubs
	local win_counter = stubs.prev_win
	vim.api.nvim_get_current_win = function()
		return win_counter
	end
	vim.api.nvim_set_current_win = function() end
	vim.api.nvim_create_buf = function()
		return stubs.created_buf
	end
	vim.api.nvim_set_current_buf = function() end
	vim.api.nvim_buf_attach = function()
		return true
	end
	vim.api.nvim_buf_is_valid = function()
		return true
	end
	vim.api.nvim_win_is_valid = function()
		return true
	end
	vim.api.nvim_win_get_buf = function()
		return stubs.created_buf
	end
	vim.api.nvim_list_wins = function()
		return { stubs.term_win }
	end
	vim.api.nvim_win_close = function() end
	vim.api.nvim_buf_delete = function() end
	vim.cmd = function(cmd_str)
		stubs.cmd_called = cmd_str
		-- After "botright split", the current window changes
		win_counter = stubs.term_win
	end
	vim.fn.termopen = function(cmd, opts)
		stubs.termopen_called = true
		stubs.termopen_cmd = cmd
		if opts and opts.on_exit then
			stubs.termopen_on_exit = opts.on_exit
		end
		return stubs.term_job_id
	end
	vim.fn.jobstop = function() end

	return stubs
end

--- Restore originals from stubs.
---@param stubs table
local function restore_terminal_env(stubs)
	vim.fn.termopen = stubs._orig.termopen
	vim.fn.jobstop = stubs._orig.jobstop
	vim.api.nvim_get_current_win = stubs._orig.nvim_get_current_win
	vim.api.nvim_set_current_win = stubs._orig.nvim_set_current_win
	vim.api.nvim_create_buf = stubs._orig.nvim_create_buf
	vim.api.nvim_set_current_buf = stubs._orig.nvim_set_current_buf
	vim.api.nvim_buf_attach = stubs._orig.nvim_buf_attach
	vim.api.nvim_buf_is_valid = stubs._orig.nvim_buf_is_valid
	vim.api.nvim_win_is_valid = stubs._orig.nvim_win_is_valid
	vim.api.nvim_win_get_buf = stubs._orig.nvim_win_get_buf
	vim.api.nvim_list_wins = stubs._orig.nvim_list_wins
	vim.api.nvim_win_close = stubs._orig.nvim_win_close
	vim.api.nvim_buf_delete = stubs._orig.nvim_buf_delete
	vim.cmd = stubs._orig.vim_cmd
	vim.schedule = stubs._orig.vim_schedule
end

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

			build._set_last_preset({
				name = "MyProjectEditor Linux Debug",
				target_name = "MyProjectEditor",
				platform = "Linux",
				configuration = "Debug",
				is_editor = true,
			})

			local captured_type
			local plat = require("unrealium.core.platform")
			local orig_run_command = plat.run_command
			plat.run_command = function(_cfg, t, _args)
				captured_type = t
				return { cmd = { "echo", "test" } }
			end

			local stubs = stub_terminal_env()
			run.execute(nil, nil)
			restore_terminal_env(stubs)
			plat.run_command = orig_run_command
			run._set_editor_terminal(nil)

			assert.equals("Debug", captured_type)
		end)

		it("infers Development type from editor preset with Development configuration", function()
			local cfg = tUtil.mock_config()
			config.get = function()
				return cfg
			end

			build._set_last_preset({
				name = "MyProjectEditor Linux Development",
				target_name = "MyProjectEditor",
				platform = "Linux",
				configuration = "Development",
				is_editor = true,
			})

			local captured_type
			local plat = require("unrealium.core.platform")
			local orig_run_command = plat.run_command
			plat.run_command = function(_cfg, t, _args)
				captured_type = t
				return { cmd = { "echo", "test" } }
			end

			local stubs = stub_terminal_env()
			run.execute(nil, nil)
			restore_terminal_env(stubs)
			plat.run_command = orig_run_command
			run._set_editor_terminal(nil)

			assert.equals("Development", captured_type)
		end)

		it("infers Development type from editor preset with DebugGame configuration", function()
			local cfg = tUtil.mock_config()
			config.get = function()
				return cfg
			end

			build._set_last_preset({
				name = "MyProjectEditor Linux DebugGame",
				target_name = "MyProjectEditor",
				platform = "Linux",
				configuration = "DebugGame",
				is_editor = true,
			})

			local captured_type
			local plat = require("unrealium.core.platform")
			local orig_run_command = plat.run_command
			plat.run_command = function(_cfg, t, _args)
				captured_type = t
				return { cmd = { "echo", "test" } }
			end

			local stubs = stub_terminal_env()
			run.execute(nil, nil)
			restore_terminal_env(stubs)
			plat.run_command = orig_run_command
			run._set_editor_terminal(nil)

			assert.equals("Development", captured_type)
		end)

		it("falls back to config default for non-editor preset", function()
			local cfg = tUtil.mock_config({
				settings = { run = { default_type = "Development" } },
			})
			config.get = function()
				return cfg
			end

			build._set_last_preset({
				name = "MyProject Linux Debug",
				target_name = "MyProject",
				platform = "Linux",
				configuration = "Debug",
				is_editor = false,
			})

			local captured_type
			local plat = require("unrealium.core.platform")
			local orig_run_command = plat.run_command
			plat.run_command = function(_cfg, t, _args)
				captured_type = t
				return { cmd = { "echo", "test" } }
			end

			local stubs = stub_terminal_env()
			run.execute(nil, nil)
			restore_terminal_env(stubs)
			plat.run_command = orig_run_command
			run._set_editor_terminal(nil)

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
			local plat = require("unrealium.core.platform")
			local orig_run_command = plat.run_command
			plat.run_command = function(_cfg, t, _args)
				captured_type = t
				return { cmd = { "echo", "test" } }
			end

			local stubs = stub_terminal_env()
			run.execute(nil, nil)
			restore_terminal_env(stubs)
			plat.run_command = orig_run_command
			run._set_editor_terminal(nil)

			assert.equals("Development", captured_type)
		end)
	end)

	describe("editor terminal lifecycle", function()
		local original_get

		before_each(function()
			build._reset()
			event.clear()
			original_get = config.get
			run._set_editor_terminal(nil)
		end)

		after_each(function()
			config.get = original_get
			run._set_editor_terminal(nil)
		end)

		it("opens a terminal split via termopen", function()
			local cfg = tUtil.mock_config()
			config.get = function()
				return cfg
			end

			local stubs = stub_terminal_env()
			run.execute("Development", nil)
			restore_terminal_env(stubs)

			assert.is_true(stubs.termopen_called)
			assert.truthy(stubs.termopen_cmd)
			assert.matches("UnrealEditor", stubs.termopen_cmd[1])
			assert.truthy(stubs.cmd_called:match("^botright %d+split$"))

			-- Should have set editor terminal state
			local term = run._get_editor_terminal()
			assert.truthy(term)
			assert.equals(stubs.created_buf, term.bufnr)
			assert.equals(stubs.term_job_id, term.job_id)

			run._set_editor_terminal(nil)
		end)

		it("emits EDITOR_START event on launch", function()
			local cfg = tUtil.mock_config()
			config.get = function()
				return cfg
			end

			local start_emitted = false
			local unsub = event.on(event.EDITOR_START, function()
				start_emitted = true
			end)

			local stubs = stub_terminal_env()
			run.execute("Development", nil)
			restore_terminal_env(stubs)
			unsub()

			assert.is_true(start_emitted)
			run._set_editor_terminal(nil)
		end)

		it("auto-closes terminal buffer on clean exit (exit_code 0)", function()
			local cfg = tUtil.mock_config()
			config.get = function()
				return cfg
			end

			local stubs = stub_terminal_env()
			run.execute("Development", nil)

			-- Simulate clean exit via the on_exit callback
			local buf_deleted = false
			local win_closed = false
			vim.api.nvim_win_close = function()
				win_closed = true
			end
			vim.api.nvim_buf_delete = function()
				buf_deleted = true
			end

			-- Fire on_exit synchronously (in tests vim.schedule runs inline)
			assert.truthy(stubs.termopen_on_exit)
			stubs.termopen_on_exit(stubs.term_job_id, 0)

			restore_terminal_env(stubs)

			assert.is_true(win_closed)
			assert.is_true(buf_deleted)
			assert.is_nil(run._get_editor_terminal())
		end)

		it("keeps terminal buffer on crash (exit_code != 0)", function()
			local cfg = tUtil.mock_config()
			config.get = function()
				return cfg
			end

			local stubs = stub_terminal_env()
			run.execute("Development", nil)

			local buf_deleted = false
			vim.api.nvim_buf_delete = function()
				buf_deleted = true
			end

			-- Fire on_exit with non-zero exit code
			assert.truthy(stubs.termopen_on_exit)
			stubs.termopen_on_exit(stubs.term_job_id, 1)

			restore_terminal_env(stubs)

			-- Buffer should NOT be deleted on crash
			assert.is_false(buf_deleted)
			-- Terminal tracking should be cleared so re-run works
			assert.is_nil(run._get_editor_terminal())
		end)

		it("replaces existing editor terminal on re-run", function()
			local cfg = tUtil.mock_config()
			config.get = function()
				return cfg
			end

			local stubs = stub_terminal_env()

			-- First run
			run.execute("Development", nil)
			local first_term = run._get_editor_terminal()
			assert.truthy(first_term)

			-- Track if jobstop was called on re-run
			local jobstop_called = false
			vim.fn.jobstop = function()
				jobstop_called = true
			end

			-- Bump buf id for second terminal
			stubs.created_buf = 101
			stubs.term_job_id = 43
			vim.api.nvim_create_buf = function()
				return 101
			end
			vim.fn.termopen = function(cmd, opts)
				if opts and opts.on_exit then
					stubs.termopen_on_exit = opts.on_exit
				end
				return 43
			end

			-- Second run should close the first terminal
			run.execute("Development", nil)
			restore_terminal_env(stubs)

			assert.is_true(jobstop_called)
			local second_term = run._get_editor_terminal()
			assert.truthy(second_term)
			assert.equals(101, second_term.bufnr)
			assert.equals(43, second_term.job_id)

			run._set_editor_terminal(nil)
		end)

		it("emits EDITOR_EXIT event on exit", function()
			local cfg = tUtil.mock_config()
			config.get = function()
				return cfg
			end

			local exit_data = nil
			local unsub = event.on(event.EDITOR_EXIT, function(data)
				exit_data = data
			end)

			local stubs = stub_terminal_env()
			run.execute("Development", nil)

			assert.truthy(stubs.termopen_on_exit)
			stubs.termopen_on_exit(stubs.term_job_id, 0)

			restore_terminal_env(stubs)
			unsub()

			assert.truthy(exit_data)
			assert.equals(0, exit_data.exit_code)
		end)
	end)

	describe("build-and-run", function()
		local original_get

		before_each(function()
			build._reset()
			job._reset()
			event.clear()
			original_get = config.get
			run._set_editor_terminal(nil)
		end)

		after_each(function()
			config.get = original_get
			run._set_editor_terminal(nil)
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
				return { cmd = { "echo", "test" } }
			end

			local stubs = stub_terminal_env()

			local orig_execute = build.execute
			build.execute = function(_arg, _bang)
				event.emit(event.BUILD_END, { exit_code = 0 })
			end

			run._build_then_run(nil, nil, nil)

			build.execute = orig_execute
			plat.run_command = orig_run_command
			restore_terminal_env(stubs)
			run._set_editor_terminal(nil)

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
				return { cmd = { "echo", "test" } }
			end

			local orig_execute = build.execute
			build.execute = function(_arg, _bang)
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
				return { cmd = { "echo", "test" } }
			end

			local stubs = stub_terminal_env()
			run.execute(nil, nil)
			restore_terminal_env(stubs)

			build.execute = orig_execute
			plat.run_command = orig_run_command
			run._set_editor_terminal(nil)

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
				return { cmd = { "echo", "test" } }
			end

			local stubs = stub_terminal_env()

			local orig_execute = build.execute
			build.execute = function(_arg, _bang)
				event.emit(event.BUILD_END, { exit_code = 0 })
			end

			run._build_then_run(nil, nil, nil)

			build.execute = orig_execute
			plat.run_command = orig_run_command
			restore_terminal_env(stubs)
			run._set_editor_terminal(nil)

			local listeners = event._listeners()
			assert.equals(0, #(listeners[event.BUILD_END] or {}))
		end)

		it("dismisses build progress notification in build-and-run", function()
			local cfg = tUtil.mock_config()
			config.get = function()
				return cfg
			end

			-- Track if progress.dismiss was called
			local dismiss_called = false
			local orig_dismiss = progress.dismiss
			progress.dismiss = function()
				dismiss_called = true
			end

			local plat = require("unrealium.core.platform")
			local orig_run_command = plat.run_command
			plat.run_command = function(_cfg, t, _args)
				return { cmd = { "echo", "test" } }
			end

			local stubs = stub_terminal_env()

			local orig_execute = build.execute
			build.execute = function(_arg, _bang)
				event.emit(event.BUILD_END, { exit_code = 0 })
			end

			run._build_then_run(nil, nil, nil)

			build.execute = orig_execute
			plat.run_command = orig_run_command
			progress.dismiss = orig_dismiss
			restore_terminal_env(stubs)
			run._set_editor_terminal(nil)

			assert.is_true(dismiss_called)
		end)
	end)
end)
