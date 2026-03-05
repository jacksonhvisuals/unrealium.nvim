--- Build target discovery: scan Source/ for *.Target.cs files.

local M = {}

local log = require("unrealium.core.log").get("target")

--- Classify a target file by its name.
---@param filename string base name without path (e.g. "MyProjectEditor.Target.cs")
---@return string "Editor"|"Server"|"Client"|"Game"
local function classify_target(filename)
	local base = filename:match("^(.+)%.Target%.cs$")
	if not base then
		return "Game"
	end
	if base:match("Editor$") then
		return "Editor"
	elseif base:match("Server$") then
		return "Server"
	elseif base:match("Client$") then
		return "Client"
	else
		return "Game"
	end
end

--- Scan a directory for *.Target.cs files using vim.fs.find.
---@param project_folder string
---@return string[] paths List of absolute paths to Target.cs files
local function scan_directory(project_folder)
	local source_dir = vim.fs.joinpath(project_folder, "Source")
	if vim.fn.isdirectory(source_dir) ~= 1 then
		log.debug("No Source/ directory found in %s", project_folder)
		return {}
	end

	return vim.fs.find(function(name)
		return name:match("%.Target%.cs$") ~= nil
	end, {
		path = source_dir,
		type = "file",
		limit = math.huge,
	})
end

--- Discover build targets in a project.
---@param project_folder string
---@return UnrealiumBuildTarget[]
function M.discover(project_folder)
	local files = scan_directory(project_folder)
	local targets = {}

	for _, file_path in ipairs(files) do
		local filename = vim.fn.fnamemodify(file_path, ":t")
		local base_name = filename:match("^(.+)%.Target%.cs$")
		if base_name then
			table.insert(targets, {
				name = base_name,
				file = file_path,
				type = classify_target(filename),
			})
		end
	end

	log.debug("Discovered %d build targets in %s", #targets, project_folder)
	return targets
end

if _TEST then
	M._classify_target = classify_target
	M._scan_directory = scan_directory
end

return M
