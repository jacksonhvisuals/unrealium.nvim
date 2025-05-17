local M = {}

---@return number channel the terminal window channel
function M._openSmallTerminal()
	-- Create a new terminal window
	vim.cmd("new")
	vim.cmd("term")

	-- Set the window height to 35% of window height.
	local total_height = vim.api.nvim_get_option_value("lines", {})
	local target_height = math.floor(total_height * 0.35)
	vim.api.nvim_win_set_height(0, target_height)

	return vim.bo.channel
end

---Executes a command in a given window channel
---@param windowChannel number the window channel number
---@param command string the command to execute
function M._executeCommandInTerminal(windowChannel, command)
	vim.api.nvim_chan_send(windowChannel, command)
end

---Executes a command in a new small terminal, handles the carriage return
---@param command string the command to run
function M.runCommand(command)
	local termID = M._openSmallTerminal()

	local returnKey = "\n"
	local fullCommand = command .. returnKey

	M._executeCommandInTerminal(termID, fullCommand)
end

return M
