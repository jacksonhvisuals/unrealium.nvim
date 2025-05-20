local M = {}

---@param title string the title for the new terminal buffer
---@return number channel the terminal job ID
local function _openSmallTerminal(title)
	-- Create a new terminal window
	vim.cmd("split")
	vim.cmd("term")
	vim.api.nvim_feedkeys("G", "n", false)
	vim.api.nvim_buf_set_name(0, title)

	-- Set the window height to 35% of window height.
	local total_height = vim.api.nvim_get_option_value("lines", {})
	local target_height = math.floor(total_height * 0.35)
	vim.api.nvim_win_set_height(0, target_height)

	return vim.b.terminal_job_id
end

---@param jobID number the term job ID number
---@param command string the command to execute
local function _executeCommandInTerminal(jobID, command)
	vim.api.nvim_chan_send(jobID, command)
end

---Executes a command in a new small terminal, handles the carriage return
---@param command string the command to run
---@param title string the title of the new terminal buffer
function M.runCommand(command, title)
	local currentBuf = vim.api.nvim_get_current_buf()
	local termID = _openSmallTerminal(title)

	local returnKey = "\n"
	local fullCommand = command .. returnKey

	-- Go back to original buffer
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-w>k", true, false, true), "n", false)
	_executeCommandInTerminal(termID, fullCommand)
end

return M
