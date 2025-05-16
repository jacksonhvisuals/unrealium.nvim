local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local config = require("telescope.config").values

local log = require("plenary.log"):new()
log.level = "debug"

local M = {}

M.ShowUnrealiumActions = function(opts)
	pickers
		.new({ results_title = "Unrealium: Actions", prompt_title = "Choose an option" }, {
			finder = finders.new_table({
				"Clean up Makefile",
				"Set build target",
				"Build",
				"Run",
				"Debug",
			}),
			sorter = config.generic_sorter(opts),
			attach_mappings = function(prompt_buffnr)
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					actions.close(prompt_buffnr)
					log.debug(selection)
				end)
				return true
			end,
		})
		:find()
end

return M
