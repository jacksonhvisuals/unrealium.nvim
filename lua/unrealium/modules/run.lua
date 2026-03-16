--- :UE run — Launch the Unreal Editor.
--- :UE build-run — Build then launch the Unreal Editor.

local M = {}

local log = require("unrealium.core.log").get("run")
local platform = require("unrealium.core.platform")
local config = require("unrealium.core.config")
local event = require("unrealium.core.event")
local job = require("unrealium.core.job")
local progress = require("unrealium.core.progress")

M.name = "run"

--- Active editor terminal state (only one at a time).
---@type { bufnr: integer, job_id: integer }|nil
local _editor_terminal = nil

--- Close the active editor terminal if one exists.
local function close_editor_terminal()
	if not _editor_terminal then
		return
	end

	local term = _editor_terminal
	_editor_terminal = nil

	-- Stop the job if still running
	pcall(vim.fn.jobstop, term.job_id)

	-- Close all windows showing this buffer, then delete it
	if vim.api.nvim_buf_is_valid(term.bufnr) then
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == term.bufnr then
				pcall(vim.api.nvim_win_close, win, true)
			end
		end
		pcall(vim.api.nvim_buf_delete, term.bufnr, { force = true })
	end
end

--- Build first, then launch the editor on success.
---@param build_arg? string preset name or configuration to pass to build.execute
---@param run_type? string "Debug"|"Development"
---@param run_extra_args? string[] additional CLI arguments for the editor
local function build_then_run(build_arg, run_type, run_extra_args)
	if job.is_running() then
		log.error("A build is already running. Wait for it to finish or stop it first.")
		return
	end

	local build = require("unrealium.modules.build")

	local unsub
	unsub = event.on(event.BUILD_END, function(data)
		unsub()
		if data and data.exit_code == 0 then
			log.info("Build succeeded, launching editor")
			progress.dismiss()
			M.execute(run_type, run_extra_args, true)
		else
			log.error("Build failed (exit code %s), not launching editor", tostring(data and data.exit_code or "?"))
		end
	end)

	build.execute(build_arg, false)
end

M.commands = {
	run = {
		handler = function(opts)
			M.execute(opts.args[1], { unpack(opts.args, 2) })
		end,
		desc = "Run Unreal Editor",
		args = {
			{ name = "type", complete = { "Development", "Debug" } },
		},
	},
	["build-run"] = {
		handler = function(opts)
			if #opts.args == 0 then
				build_then_run(nil, nil, nil)
				return
			end

			-- Try longest match for preset name (same pattern as build command)
			local build = require("unrealium.modules.build")
			local presets = build.get_presets()
			local preset_set = {}
			for _, p in ipairs(presets) do
				preset_set[p.name] = true
			end
			for i = #opts.args, 1, -1 do
				local candidate = table.concat(opts.args, " ", 1, i)
				if preset_set[candidate] then
					build_then_run(candidate, nil, nil)
					return
				end
			end
			-- Fall through with full arg as preset/configuration name
			build_then_run(table.concat(opts.args, " "), nil, nil)
		end,
		desc = "Build then run Unreal Editor",
		args = {
			{
				name = "preset",
				complete = function()
					local build = require("unrealium.modules.build")
					local presets = build.get_presets()
					local names = {}
					for _, p in ipairs(presets) do
						table.insert(names, p.name)
					end
					return names
				end,
			},
		},
	},
}

--- Launch Unreal Editor in a terminal split.
---@param type? string "Debug"|"Development" (defaults to config run.default_type)
---@param extra_args? string[] additional CLI arguments
---@param _skip_build? boolean internal flag to skip build_first check (prevents recursion)
function M.execute(type, extra_args, _skip_build)
	local cfg = config.get()
	if not cfg then
		log.error("Config not available")
		return
	end

	-- If build_first is enabled and we weren't called from build_then_run, build first
	if not _skip_build then
		local build_first = cfg.settings and cfg.settings.run and cfg.settings.run.build_first
		if build_first then
			build_then_run(nil, type, extra_args)
			return
		end
	end

	if not type then
		local build = require("unrealium.modules.build")
		local last = build.last_preset()
		if last and last.is_editor then
			type = last.configuration == "Debug" and "Debug" or "Development"
		else
			type = cfg.settings and cfg.settings.run and cfg.settings.run.default_type or "Development"
		end
	end

	-- Merge config-level extra_args with dynamic extra_args
	local merged_args = {}
	local config_args = cfg.settings and cfg.settings.run and cfg.settings.run.extra_args
	if config_args then
		for _, arg in ipairs(config_args) do
			table.insert(merged_args, arg)
		end
	end
	if extra_args then
		for _, arg in ipairs(extra_args) do
			table.insert(merged_args, arg)
		end
	end

	local cmd_data = platform.run_command(cfg, type, #merged_args > 0 and merged_args or nil)
	log.info("Launching UnrealEditor in %s mode: %s", type, table.concat(cmd_data.cmd, " "))

	-- Close any existing editor terminal before opening a new one
	close_editor_terminal()

	-- Remember current window to return focus
	local prev_win = vim.api.nvim_get_current_win()

	-- Create a new buffer and open it in a bottom split
	vim.cmd("botright split")
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_current_buf(buf)
	local term_win = vim.api.nvim_get_current_win()

	-- Auto-scroll: whenever new output arrives, scroll the terminal window to the bottom
	vim.api.nvim_buf_attach(buf, false, {
		on_lines = function(_, attached_buf)
			-- Detach if buffer was deleted
			if not vim.api.nvim_buf_is_valid(attached_buf) then
				return true
			end
			-- Only scroll if the terminal window still exists and shows this buffer
			if vim.api.nvim_win_is_valid(term_win) and vim.api.nvim_win_get_buf(term_win) == attached_buf then
				local line_count = vim.api.nvim_buf_line_count(attached_buf)
				pcall(vim.api.nvim_win_set_cursor, term_win, { line_count, 0 })
			end
		end,
	})

	local job_id = vim.fn.termopen(cmd_data.cmd, {
		on_exit = function(_, exit_code)
			vim.schedule(function()
				event.emit(event.EDITOR_EXIT, { exit_code = exit_code })

				if exit_code == 0 then
					-- Clean exit: close terminal windows and delete buffer
					if _editor_terminal and _editor_terminal.bufnr == buf then
						close_editor_terminal()
					end
				else
					-- Crash: keep buffer visible for inspection
					log.warn("Editor exited with code %d — terminal kept open for inspection", exit_code)
					-- Clear our tracking so a new run can start fresh
					if _editor_terminal and _editor_terminal.bufnr == buf then
						_editor_terminal = nil
					end
				end
			end)
		end,
	})

	if job_id <= 0 then
		log.error("Failed to start editor process")
		vim.api.nvim_buf_delete(buf, { force = true })
		-- Return to previous window
		if vim.api.nvim_win_is_valid(prev_win) then
			vim.api.nvim_set_current_win(prev_win)
		end
		return
	end

	_editor_terminal = { bufnr = buf, job_id = job_id }
	event.emit(event.EDITOR_START, { cmd = cmd_data.cmd })

	-- Return focus to previous window
	if vim.api.nvim_win_is_valid(prev_win) then
		vim.api.nvim_set_current_win(prev_win)
	end
end

if _TEST then
	M._build_then_run = build_then_run
	M._close_editor_terminal = close_editor_terminal
	M._get_editor_terminal = function()
		return _editor_terminal
	end
	M._set_editor_terminal = function(val)
		_editor_terminal = val
	end
end

return M
