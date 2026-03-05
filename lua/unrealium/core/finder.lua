--- Project discovery: ancestor traversal, .uproject discovery, engine path resolution.

local M = {}

local log = require("unrealium.core.log").get("finder")

local BATCH_FILES_SUBPATH = "Engine/Build/BatchFiles"

--- Walk up from start_dir, calling predicate on each directory.
--- Returns the first directory where predicate returns a truthy value.
---@param start_dir string
---@param predicate fun(dir: string): any
---@return any result The value returned by predicate, or nil
function M.walk_ancestors(start_dir, predicate)
	local current = vim.fn.fnamemodify(start_dir, ":p")
	-- Remove trailing slash for consistent comparison
	current = current:gsub("/$", "")

	while true do
		local result = predicate(current)
		if result then
			return result
		end

		local parent = vim.fn.fnamemodify(current, ":h")
		if parent == current then
			return nil
		end
		current = parent
	end
end

--- Check if a directory contains a file with the given extension.
---@param directory string
---@param extension string
---@return string|nil full_path Path to the found file, or nil
local function find_file_with_extension(directory, extension)
	local handle = vim.uv.fs_scandir(directory)
	if not handle then
		return nil
	end

	while true do
		local name, typ = vim.uv.fs_scandir_next(handle)
		if not name then
			break
		end
		if typ == "file" then
			local ext = vim.fn.fnamemodify(name, ":e")
			if ext == extension then
				return vim.fs.joinpath(directory, name)
			end
		end
	end
	return nil
end

--- Find the .uproject file by walking up from start_dir.
---@param start_dir? string Defaults to vim.uv.cwd()
---@return { root: string, uproject_path: string, name: string }|nil
function M.find_project(start_dir)
	start_dir = start_dir or vim.uv.cwd()
	if not start_dir then
		return nil
	end

	local uproject_path = M.walk_ancestors(start_dir, function(dir)
		return find_file_with_extension(dir, "uproject")
	end)

	if not uproject_path then
		log.debug("No .uproject found from %s", start_dir)
		return nil
	end

	local root = vim.fn.fnamemodify(uproject_path, ":h")
	local name = vim.fn.fnamemodify(uproject_path, ":t:r")

	return {
		root = root,
		uproject_path = uproject_path,
		name = name,
	}
end

--- Read and parse the .unrealium or .unrealium.json config file.
---@param project_root string
---@return table|nil parsed JSON data
function M.read_project_config(project_root)
	-- Try .unrealium.json first, then legacy .unrealium
	local candidates = {
		vim.fs.joinpath(project_root, ".unrealium.json"),
		vim.fs.joinpath(project_root, ".unrealium"),
	}

	for _, config_path in ipairs(candidates) do
		if vim.fn.filereadable(config_path) == 1 then
			local file = io.open(config_path, "r")
			if file then
				local content = file:read("*all")
				file:close()

				if content and content ~= "" then
					-- Strip BOM
					content = content:gsub("^\xEF\xBB\xBF", "")
					local ok, data = pcall(vim.fn.json_decode, content)
					if ok and type(data) == "table" and next(data) ~= nil then
						return data
					else
						log.error("Failed to parse config file: %s", config_path)
					end
				end
			end
		end
	end

	log.error("No .unrealium.json or .unrealium config file found in %s", project_root)
	return nil
end

--- Resolve and validate the engine installation path.
---@param engine_path string
---@return string|nil validated path, or nil if invalid
function M.validate_engine_path(engine_path)
	if not engine_path or engine_path == "" then
		return nil
	end
	-- Fix: explicit == 1 check (0 is truthy in Lua)
	if vim.fn.isdirectory(engine_path) == 1 then
		return engine_path
	end
	log.error("Engine path does not exist: %s", engine_path)
	return nil
end

--- Build engine script paths for a given engine root and platform.
---@param engine_path string
---@param platform_name string
---@return EngineScripts
function M.get_script_paths(engine_path, platform_name)
	return {
		Build = vim.fs.joinpath(engine_path, BATCH_FILES_SUBPATH, platform_name, "Build.sh"),
		GenerateProjectFiles = vim.fs.joinpath(
			engine_path,
			BATCH_FILES_SUBPATH,
			platform_name,
			"GenerateProjectFiles.sh"
		),
		EditorBase = vim.fs.joinpath(engine_path, "Engine", "Binaries", platform_name, "UnrealEditor"),
		RunUBT = vim.fs.joinpath(engine_path, BATCH_FILES_SUBPATH, "RunUBT.sh"),
	}
end

--- Detect the current platform name.
---@return string "Linux"|"Mac"|"Windows"|"Unknown"
function M.get_platform_name()
	local sysname = vim.uv.os_uname().sysname
	if sysname == "Linux" then
		return "Linux"
	elseif sysname == "Darwin" then
		return "Mac"
	elseif sysname:match("Windows") or sysname:match("Win") then
		return "Windows"
	else
		return "Unknown"
	end
end

--- Resolve engine config from raw project config data.
--- Supports both new format ({ engine = { folder = ... } }) and legacy ({ EnginePath = ... }).
---@param raw_config table
---@return { folder: string|nil, allow_modifications: boolean }
function M.resolve_engine_config(raw_config)
	local folder, allow_mods

	-- New format
	if raw_config.engine then
		folder = raw_config.engine.folder
		allow_mods = raw_config.engine.allow_modifications
	end

	-- Legacy format fallback
	if not folder and raw_config.EnginePath then
		folder = raw_config.EnginePath
	end
	if allow_mods == nil and raw_config.allowEngineModifications ~= nil then
		allow_mods = raw_config.allowEngineModifications
	end

	return {
		folder = folder,
		allow_modifications = allow_mods or false,
	}
end

if _TEST then
	M._find_file_with_extension = find_file_with_extension
end

return M
