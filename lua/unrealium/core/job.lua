--- Async job runner with single-job guard, line buffering, and diagnostic parsing.

local M = {}

local log = require("unrealium.core.log").get("job")
local event = require("unrealium.core.event")

---@class UnrealiumJobHandle
---@field id integer jobstart() return value
---@field preset? UnrealiumPreset
---@field output_lines string[]
---@field errors UnrealiumDiagnostic[]
---@field warnings UnrealiumDiagnostic[]
---@field progress? { percentage: integer, label: string }
---@field exit_code? integer

---@type UnrealiumJobHandle|nil
local _active_job = nil

--- Parse UBT progress output.
--- Matches patterns like "@progress 'Compiling' 45%" and "[3/10]".
---@param line string
---@return { percentage: integer, label: string }|nil
local function parse_progress(line)
	-- @progress 'label' NN%
	local label, pct = line:match("@progress%s+'([^']+)'%s+(%d+)%%")
	if label and pct then
		return { percentage = tonumber(pct), label = label }
	end

	-- [N/M] pattern
	local current, total = line:match("%[(%d+)/(%d+)%]")
	if current and total then
		local c, t = tonumber(current), tonumber(total)
		if t > 0 then
			local percentage = math.floor((c / t) * 100)
			return { percentage = percentage, label = string.format("[%d/%d]", c, t) }
		end
	end

	return nil
end

--- Parse a compiler diagnostic from a line.
--- Supports GCC/Clang (file:line:col: error/warning: msg) and MSVC (file(line): error/warning msg).
---@param line string
---@return UnrealiumDiagnostic|nil
local function parse_diagnostic(line)
	-- GCC/Clang: file:line:col: error: message  or  file:line:col: warning: message
	for _, dtype in ipairs({ "error", "warning" }) do
		local pattern_col = "^(.+):(%d+):(%d+):%s*" .. dtype .. ":%s*(.+)$"
		local file, lnum, col, text = line:match(pattern_col)
		if file then
			return {
				file = file,
				lnum = tonumber(lnum),
				col = tonumber(col),
				type = dtype,
				text = text,
			}
		end

		-- GCC/Clang without column: file:line: error: message
		local pattern_no_col = "^(.+):(%d+):%s*" .. dtype .. ":%s*(.+)$"
		file, lnum, text = line:match(pattern_no_col)
		if file then
			return {
				file = file,
				lnum = tonumber(lnum),
				type = dtype,
				text = text,
			}
		end

		-- MSVC: file(line): error C1234: message
		local pattern_msvc = "^(.+)%((%d+)%):%s*" .. dtype .. "%s+(.+)$"
		file, lnum, text = line:match(pattern_msvc)
		if file then
			return {
				file = file,
				lnum = tonumber(lnum),
				type = dtype,
				text = text,
			}
		end
	end

	return nil
end

--- Buffer partial lines from jobstart data arrays.
--- The last element of jobstart's data array may be a partial line.
---@param remainder string existing partial line buffer
---@param data string[] raw data from jobstart callback
---@return string[] complete_lines, string new_remainder
local function buffer_lines(remainder, data)
	local lines = {}
	for i, chunk in ipairs(data) do
		if i == 1 then
			chunk = remainder .. chunk
		end
		if i == #data then
			-- Last element is potentially partial
			remainder = chunk
		else
			table.insert(lines, chunk)
		end
	end
	-- If data has only one element, remainder is already set
	if #data == 1 then
		remainder = (remainder == data[1]) and remainder or remainder
	end
	return lines, remainder
end

--- Start an async job.
---@param opts { cmd: string[], cwd?: string, preset?: UnrealiumPreset, on_line?: fun(line: string), on_complete?: fun(handle: UnrealiumJobHandle) }
---@return UnrealiumJobHandle|nil
function M.start(opts)
	if _active_job then
		log.error("A build is already running (job %d). Stop it first or wait for completion.", _active_job.id)
		return nil
	end

	---@type UnrealiumJobHandle
	local handle = {
		id = 0,
		preset = opts.preset,
		output_lines = {},
		errors = {},
		warnings = {},
	}

	local stdout_remainder = ""
	local stderr_remainder = ""

	local function process_line(line)
		if line == "" then
			return
		end
		table.insert(handle.output_lines, line)

		-- Check for progress
		local prog = parse_progress(line)
		if prog then
			handle.progress = prog
			event.emit(event.BUILD_PROGRESS, { handle = handle, progress = prog })
		end

		-- Check for diagnostics
		local diag = parse_diagnostic(line)
		if diag then
			if diag.type == "error" then
				table.insert(handle.errors, diag)
			else
				table.insert(handle.warnings, diag)
			end
		end

		if opts.on_line then
			opts.on_line(line)
		end
	end

	local job_id = vim.fn.jobstart(opts.cmd, {
		cwd = opts.cwd,
		stdout_buffered = false,
		stderr_buffered = false,
		on_stdout = function(_, data, _)
			if not data then
				return
			end
			local lines
			lines, stdout_remainder = buffer_lines(stdout_remainder, data)
			for _, line in ipairs(lines) do
				process_line(line)
			end
		end,
		on_stderr = function(_, data, _)
			if not data then
				return
			end
			local lines
			lines, stderr_remainder = buffer_lines(stderr_remainder, data)
			for _, line in ipairs(lines) do
				process_line(line)
			end
		end,
		on_exit = function(_, exit_code, _)
			-- Flush remaining partial lines
			if stdout_remainder ~= "" then
				process_line(stdout_remainder)
				stdout_remainder = ""
			end
			if stderr_remainder ~= "" then
				process_line(stderr_remainder)
				stderr_remainder = ""
			end

			handle.exit_code = exit_code
			_active_job = nil

			event.emit(event.JOB_FINISH, { handle = handle, exit_code = exit_code })

			if opts.on_complete then
				opts.on_complete(handle)
			end
		end,
	})

	if job_id <= 0 then
		log.error("Failed to start job: %s", table.concat(opts.cmd, " "))
		return nil
	end

	handle.id = job_id
	_active_job = handle

	event.emit(event.JOB_START, { handle = handle })
	log.info("Job started: %s (id=%d)", table.concat(opts.cmd, " "), job_id)

	return handle
end

--- Stop the active job.
--- jobstop() triggers the on_exit callback, which handles cleanup.
function M.stop()
	if not _active_job then
		log.info("No active job to stop")
		return
	end
	log.info("Stopping job %d", _active_job.id)
	vim.fn.jobstop(_active_job.id)
end

--- Check if a job is currently running.
---@return boolean
function M.is_running()
	return _active_job ~= nil
end

--- Get the active job handle.
---@return UnrealiumJobHandle|nil
function M.active()
	return _active_job
end

if _TEST then
	M._parse_progress = parse_progress
	M._parse_diagnostic = parse_diagnostic
	M._buffer_lines = buffer_lines
	M._reset = function()
		_active_job = nil
	end
end

return M
