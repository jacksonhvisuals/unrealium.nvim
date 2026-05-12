--- Unreal filetype detection and editor defaults.

local M = {}

local augroup_name = "UnrealiumFiletype"

---@param path string
---@return boolean
local function is_unreal_json(path)
	return path:match("%.uproject$") ~= nil or path:match("%.uplugin$") ~= nil
end

---@param path string
---@return boolean
local function is_build_cs(path)
	return path:match("%.Build%.cs$") ~= nil
end

---@param bufnr integer
local function apply_unreal_indent(bufnr)
	vim.bo[bufnr].expandtab = false
	vim.bo[bufnr].tabstop = 4
	vim.bo[bufnr].shiftwidth = 4
	vim.bo[bufnr].softtabstop = 4
end

---@param bufnr integer
function M.apply(bufnr)
	bufnr = bufnr or 0
	local path = vim.api.nvim_buf_get_name(bufnr)
	if path == "" then
		return
	end

	if is_unreal_json(path) or is_build_cs(path) then
		apply_unreal_indent(bufnr)
	end
end

--- Register Unreal filetype detection and buffer-local defaults.
function M.setup()
	vim.filetype.add({
		extension = {
			uproject = "json",
			uplugin = "json",
		},
		pattern = {
			[".*%.Build%.cs$"] = "cs",
		},
	})

	local augroup = vim.api.nvim_create_augroup(augroup_name, { clear = true })
	vim.api.nvim_create_autocmd("FileType", {
		group = augroup,
		desc = "Apply Unreal file indentation defaults.",
		pattern = { "json", "cs" },
		callback = function(args)
			M.apply(args.buf)
		end,
	})

	M.apply(0)
end

if _TEST then
	M._is_unreal_json = is_unreal_json
	M._is_build_cs = is_build_cs
end

return M
