--- :UE switch — Header/source file switcher with UE Public/Private awareness.

local M = {}

local log = require("unrealium.core.log").get("switch")

M.name = "switch"

--- Extension-to-target mappings.
local EXT_MAP = {
	[".h"] = { ".cpp", ".c" },
	[".hpp"] = { ".cpp", ".c" },
	[".cpp"] = { ".h", ".hpp" },
	[".c"] = { ".h", ".hpp" },
}

--- Check if a file exists.
---@param path string
---@return boolean
local function file_exists(path)
	local stat = vim.uv.fs_stat(path)
	return stat ~= nil and stat.type == "file"
end

--- Get base name and extension from a file path.
---@param filepath string
---@return string basename without extension
---@return string ext including the dot
local function split_ext(filepath)
	local base = vim.fn.fnamemodify(filepath, ":t:r")
	local ext = vim.fn.fnamemodify(filepath, ":e")
	return base, ext ~= "" and ("." .. ext) or ""
end

--- Find the companion file for a given source/header path.
---@param filepath string absolute path to current file
---@return string|nil companion absolute path, or nil if not found
function M.find_companion(filepath)
	local base, ext = split_ext(filepath)
	if ext == "" then
		return nil
	end

	-- If on a .generated.h, strip .generated and look for the real .h first
	if base:match("%.generated$") then
		base = base:gsub("%.generated$", "")
		-- Rewrite ext to .h so we search for the real header's companion
		ext = ".h"
		local dir = vim.fn.fnamemodify(filepath, ":h")
		local real_header = dir .. "/" .. base .. ".h"
		if file_exists(real_header) then
			filepath = real_header
		end
	end

	local targets = EXT_MAP[ext]
	if not targets then
		return nil
	end

	local dir = vim.fn.fnamemodify(filepath, ":h")

	-- Strategy 1: Same directory
	for _, target_ext in ipairs(targets) do
		local candidate = dir .. "/" .. base .. target_ext
		if file_exists(candidate) then
			return candidate
		end
	end

	-- Strategy 2: UE Public/Private mirror
	local mirror_dir
	if dir:find("/Public/") or dir:match("/Public$") then
		mirror_dir = dir:gsub("/Public", "/Private", 1)
	elseif dir:find("/Private/") or dir:match("/Private$") then
		mirror_dir = dir:gsub("/Private", "/Public", 1)
	end

	if mirror_dir then
		for _, target_ext in ipairs(targets) do
			local candidate = mirror_dir .. "/" .. base .. target_ext
			if file_exists(candidate) then
				return candidate
			end
		end
	end

	-- Strategy 3: Sibling directories
	local parent = vim.fn.fnamemodify(dir, ":h")
	local handle = vim.uv.fs_scandir(parent)
	if handle then
		while true do
			local name, typ = vim.uv.fs_scandir_next(handle)
			if not name then
				break
			end
			if typ == "directory" and parent .. "/" .. name ~= dir then
				for _, target_ext in ipairs(targets) do
					local candidate = parent .. "/" .. name .. "/" .. base .. target_ext
					if file_exists(candidate) then
						return candidate
					end
				end
			end
		end
	end

	return nil
end

--- Execute the switch command.
---@param mode? string "split", "vsplit", or nil for edit
function M.execute(mode)
	local filepath = vim.api.nvim_buf_get_name(0)
	if filepath == "" then
		log.error("No file in current buffer")
		return
	end

	-- Skip .generated.h as a target (handled inside find_companion)
	local companion = M.find_companion(filepath)
	if not companion then
		vim.notify("No companion file found", vim.log.levels.WARN)
		return
	end

	-- Never switch TO a .generated.h
	if companion:match("%.generated%.h$") then
		vim.notify("No companion file found (skipping .generated.h)", vim.log.levels.WARN)
		return
	end

	if mode == "split" then
		vim.cmd.split(companion)
	elseif mode == "vsplit" then
		vim.cmd.vsplit(companion)
	else
		vim.cmd.edit(companion)
	end
end

M.commands = {
	switch = {
		handler = function(opts)
			M.execute(opts.args[1])
		end,
		desc = "Switch between header and source file",
		args = {
			{ name = "mode", complete = { "split", "vsplit" } },
		},
	},
}

if _TEST then
	M._file_exists = file_exists
	M._split_ext = split_ext
end

return M
