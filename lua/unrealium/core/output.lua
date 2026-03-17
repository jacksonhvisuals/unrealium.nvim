--- Shared output buffer, log toggle, and quickfix helpers for async commands.

local M = {}

--- Get or create a named output buffer.
---@param name string module name (e.g., "build", "generate")
---@return integer bufnr
function M.get_or_create_buf(name)
	local buf_pattern = "%[unrealium:" .. name .. "%]$"
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf):match(buf_pattern) then
			return buf
		end
	end

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, "[unrealium:" .. name .. "]")
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buf })
	return buf
end

--- Clear and set a header line on the output buffer.
---@param buf integer
---@param header string
function M.clear(buf, header)
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { header })
	end
end

--- Append a line to a buffer with auto-scroll.
---@param buf integer
---@param line string
function M.append(buf, line)
	vim.schedule(function()
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end
		vim.api.nvim_buf_set_lines(buf, -1, -1, false, { line })

		for _, win in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_get_buf(win) == buf then
				local line_count = vim.api.nvim_buf_line_count(buf)
				vim.api.nvim_win_set_cursor(win, { line_count, 0 })
			end
		end
	end)
end

--- Toggle a bottom split showing the named output buffer.
---@param name string module name
---@return boolean found whether a buffer existed to show
function M.toggle(name)
	local buf_pattern = "%[unrealium:" .. name .. "%]$"

	-- Close if already open
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(win) then
			local buf = vim.api.nvim_win_get_buf(win)
			if vim.api.nvim_buf_get_name(buf):match(buf_pattern) then
				vim.api.nvim_win_close(win, false)
				return true
			end
		end
	end

	-- Find the buffer
	local target_buf = nil
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf):match(buf_pattern) then
			target_buf = buf
			break
		end
	end

	if not target_buf then
		return false
	end

	vim.cmd("botright split")
	vim.api.nvim_win_set_buf(0, target_buf)
	local line_count = vim.api.nvim_buf_line_count(target_buf)
	if line_count > 0 then
		vim.api.nvim_win_set_cursor(0, { line_count, 0 })
	end
	return true
end

--- Delete a named output buffer if it exists.
---@param name string module name
function M.delete_buf(name)
	local buf_pattern = "%[unrealium:" .. name .. "%]$"
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf):match(buf_pattern) then
			vim.api.nvim_buf_delete(buf, { force = true })
			return
		end
	end
end

--- Populate quickfix list from a job handle's diagnostics.
---@param handle UnrealiumJobHandle
---@param auto_open? boolean whether to auto-open quickfix (default true)
function M.quickfix(handle, auto_open)
	local items = {}
	for _, diag in ipairs(handle.errors) do
		table.insert(items, {
			filename = diag.file,
			lnum = diag.lnum,
			col = diag.col or 0,
			text = diag.text,
			type = "E",
		})
	end
	for _, diag in ipairs(handle.warnings) do
		table.insert(items, {
			filename = diag.file,
			lnum = diag.lnum,
			col = diag.col or 0,
			text = diag.text,
			type = "W",
		})
	end

	vim.fn.setqflist(items, "r")
	if auto_open ~= false and #handle.errors > 0 then
		vim.cmd("botright copen")
	end
end

return M
