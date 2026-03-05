--- Logger factory for unrealium.nvim
--- Named loggers with file + notify writers, async file I/O via vim.uv.

local M = {}

local uv = vim.uv

---@alias LogLevel integer
local LEVELS = {
	ERROR = 1,
	WARN = 2,
	INFO = 3,
	DEBUG = 4,
	TRACE = 5,
}

M.LEVELS = LEVELS

--- Map string names to numeric levels
local LEVEL_NAMES = {
	error = LEVELS.ERROR,
	warn = LEVELS.WARN,
	info = LEVELS.INFO,
	debug = LEVELS.DEBUG,
	trace = LEVELS.TRACE,
}

local LEVEL_LABELS = { "ERROR", "WARN", "INFO", "DEBUG", "TRACE" }

local _level = LEVELS.INFO
local _file_path = vim.fn.stdpath("data") .. "/unrealium.log"
local _notify = true

--- Set the global log level.
---@param level string|integer
function M.set_level(level)
	if type(level) == "string" then
		_level = LEVEL_NAMES[level:lower()] or LEVELS.INFO
	else
		_level = level
	end
end

--- Initialize logging from config values.
---@param opts? { level?: string|integer, file?: string, notify?: boolean }
function M.init(opts)
	opts = opts or {}
	if opts.level then
		M.set_level(opts.level)
	end
	if opts.file then
		_file_path = opts.file
	end
	if opts.notify ~= nil then
		_notify = opts.notify
	end
	-- Support legacy vim.g.unrealium_loglevel
	if vim.g.unrealium_loglevel then
		_level = vim.g.unrealium_loglevel
	end
end

--- Write a message to the log file asynchronously.
---@param msg string
local function write_file(msg)
	uv.fs_open(_file_path, "a", 438, function(err, fd)
		if fd then
			uv.fs_write(fd, msg, -1, function()
				uv.fs_close(fd)
			end)
		elseif err then
			-- Can't log this without recursion, so just notify
			vim.schedule(function()
				vim.notify("[unrealium] log write error: " .. err, vim.log.levels.ERROR)
			end)
		end
	end)
end

--- Map our levels to vim.log.levels for vim.notify
local VIM_LEVELS = {
	[LEVELS.ERROR] = vim.log.levels.ERROR,
	[LEVELS.WARN] = vim.log.levels.WARN,
	[LEVELS.INFO] = vim.log.levels.INFO,
	[LEVELS.DEBUG] = vim.log.levels.DEBUG,
	[LEVELS.TRACE] = vim.log.levels.TRACE,
}

---@class UnrealiumLogger
---@field error fun(fmt: string, ...: any)
---@field warn fun(fmt: string, ...: any)
---@field info fun(fmt: string, ...: any)
---@field debug fun(fmt: string, ...: any)
---@field trace fun(fmt: string, ...: any)

--- Create a named logger.
---@param name string Module name prefix
---@return UnrealiumLogger
function M.get(name)
	local logger = {}

	for level_name, level_num in pairs(LEVELS) do
		logger[level_name:lower()] = function(fmt, ...)
			if level_num > _level then
				return
			end

			local msg
			if select("#", ...) > 0 then
				msg = string.format(fmt, ...)
			else
				msg = fmt
			end

			local time = os.date("%m/%d/%y %H:%M:%S")
			local line = string.format("[%s][%s][%s]: %s\n", time, LEVEL_LABELS[level_num], name, msg)
			write_file(line)

			-- Notify for errors and warnings
			if _notify and level_num <= LEVELS.WARN then
				vim.schedule(function()
					vim.notify(string.format("[unrealium.%s] %s", name, msg), VIM_LEVELS[level_num])
				end)
			end
		end
	end

	return logger
end

if _TEST then
	M._get_level = function()
		return _level
	end
	M._get_file_path = function()
		return _file_path
	end
end

return M
