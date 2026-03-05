--- :UE diagnostics — Browse errors/warnings from last completed build.

local M = {}

local log = require("unrealium.core.log").get("diagnostics")
local event = require("unrealium.core.event")

M.name = "diagnostics"

---@type UnrealiumJobHandle|nil
local _last_handle = nil

--- Capture the last completed job handle.
local function on_job_finish(data)
	if data and data.handle then
		_last_handle = data.handle
	end
end

--- Show diagnostics from the last build.
---@param filter? string "errors"|"warnings"|"all"
function M.execute(filter)
	if not _last_handle then
		log.error("No build results available. Run a build first.")
		return
	end

	filter = filter or "all"

	local items = {}
	if filter == "all" or filter == "errors" then
		for _, diag in ipairs(_last_handle.errors) do
			table.insert(items, {
				text = string.format("[error] %s:%d: %s", diag.file, diag.lnum, diag.text),
				filename = diag.file,
				lnum = diag.lnum,
				col = diag.col,
				diag = diag,
			})
		end
	end
	if filter == "all" or filter == "warnings" then
		for _, diag in ipairs(_last_handle.warnings) do
			table.insert(items, {
				text = string.format("[warning] %s:%d: %s", diag.file, diag.lnum, diag.text),
				filename = diag.file,
				lnum = diag.lnum,
				col = diag.col,
				diag = diag,
			})
		end
	end

	if #items == 0 then
		log.info("No diagnostics to show (filter: %s)", filter)
		return
	end

	local display = {}
	for _, item in ipairs(items) do
		table.insert(display, item.text)
	end

	vim.ui.select(display, { prompt = "Build diagnostics:" }, function(_, idx)
		if not idx then
			return
		end
		local item = items[idx]
		if item.filename and item.lnum then
			vim.cmd("edit " .. vim.fn.fnameescape(item.filename))
			vim.api.nvim_win_set_cursor(0, { item.lnum, (item.col or 1) - 1 })
		end
	end)
end

M.commands = {
	diagnostics = {
		handler = function(opts)
			M.execute(opts.args[1])
		end,
		desc = "Browse build diagnostics",
		args = {
			{ name = "filter", complete = { "errors", "warnings", "all" } },
		},
	},
}

--- Setup: subscribe to job finish events.
---@param _ UnrealiumConfig
function M.setup(_)
	event.on(event.JOB_FINISH, on_job_finish)
end

if _TEST then
	M._on_job_finish = on_job_finish
	M._reset = function()
		_last_handle = nil
	end
end

return M
