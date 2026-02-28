local M = {}

---Provides autocomplete suggestions for any number of arguments
---@param args table a table of any number of lists of strings
---@return table | nil a flattened table of strings for autocomplete suggestions
function M.autocomplete(input, args)
	if not input then
		return nil
	end

	local l = vim.split(input, "%s+")
	local n = #l - 2

	for index, indexArgs in ipairs(args) do
		if n == (index - 1) then
			table.sort(indexArgs)

			return vim.tbl_filter(function(val)
				return vim.startswith(val, l[index + 1])
			end, indexArgs)
		end
	end
end

---Join multiple path segments into a single path.
---@param ... string Path segments to join
---@return string Full joined path
function M.joinPath(...)
	return vim.fs.joinpath(...)
end

function M.chain(cmd1, cmd2, opts)
	opts = opts or {}

	-- callback when first command exits
	local function on_exit_first(job_id, exit_code, event)
		if exit_code == 0 then
			-- run second command if first succeeded
			vim.fn.jobstart(cmd2, {
				on_stdout = opts.on_stdout,
				on_stderr = opts.on_stderr,
				on_exit = opts.on_exit,
			})
		else
			if opts.on_fail then
				opts.on_fail(exit_code)
			else
				vim.notify(string.format("Command failed: %s (exit %d)", cmd1, exit_code), vim.log.levels.ERROR)
			end
		end
	end

	-- run first command
	vim.fn.jobstart(cmd1, {
		on_stdout = opts.on_stdout,
		on_stderr = opts.on_stderr,
		on_exit = on_exit_first,
	})
end
return M
