local M = {}

---Provides autocomplete suggestions for any number of arguments
---@param args table a table of any number of lists of strings
---@return table | nil a flattened table of strings for autocomplete suggestions
function M.autocomplete(input, args)
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

return M
