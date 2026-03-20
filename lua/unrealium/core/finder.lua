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

--- Read and parse a JSON file, returning the decoded table or nil.
---@param path string
---@return table|nil
local function read_json_file(path)
	if vim.fn.filereadable(path) ~= 1 then
		return nil
	end
	local file = io.open(path, "r")
	if not file then
		return nil
	end
	local content = file:read("*all")
	file:close()
	if not content or content == "" then
		return nil
	end
	-- Strip BOM
	content = content:gsub("^\xEF\xBB\xBF", "")
	local ok, data = pcall(vim.fn.json_decode, content)
	if ok and type(data) == "table" then
		return data
	end
	log.error("Failed to parse JSON file: %s\n%s", path, ok and "unexpected type: " .. type(data) or tostring(data))
	return nil
end

--- Read the project config file (unrealium.json).
--- Returns an empty table if no config file is found (config is optional).
---@param project_root string
---@return table parsed JSON data (may be empty)
function M.read_project_config(project_root)
	local candidates = {
		vim.fs.joinpath(project_root, "unrealium.json"),
	}

	for _, config_path in ipairs(candidates) do
		local data = read_json_file(config_path)
		if data and next(data) ~= nil then
			return data
		end
	end

	log.debug("No unrealium.json config file found in %s (using defaults)", project_root)
	return {}
end

--- Read the .uproject file and extract the EngineAssociation value.
---@param uproject_path string
---@return string|nil engine_association
function M.read_engine_association(uproject_path)
	local data = read_json_file(uproject_path)
	if data and data.EngineAssociation then
		return data.EngineAssociation
	end
	return nil
end

--- Get the platform-specific path to the Epic engine install registry.
---@return string|nil
local function get_install_registry_path()
	local platform = vim.uv.os_uname().sysname
	if platform == "Linux" then
		return vim.fs.joinpath(os.getenv("HOME") or "", ".config", "Epic", "UnrealEngine", "Install.ini")
	elseif platform == "Darwin" then
		return vim.fs.joinpath(
			os.getenv("HOME") or "",
			"Library",
			"Application Support",
			"Epic",
			"UnrealEngine",
			"Install.ini"
		)
	end
	return nil
end

--- Parse the Epic Install.ini file and return a table mapping identifiers to paths.
---@param ini_path string
---@return table<string, string>
local function parse_install_ini(ini_path)
	local entries = {}
	if vim.fn.filereadable(ini_path) ~= 1 then
		return entries
	end
	local file = io.open(ini_path, "r")
	if not file then
		return entries
	end
	for line in file:lines() do
		local key, value = line:match("^(.-)=(.+)$")
		if key and value then
			entries[key] = value
		end
	end
	file:close()
	return entries
end

--- Resolve an EngineAssociation value to an engine install path.
---@param association string GUID or version string from .uproject
---@return string|nil engine_path
function M.resolve_engine_association(association)
	local ini_path = get_install_registry_path()
	if not ini_path then
		log.debug("No install registry path for this platform")
		return nil
	end

	local entries = parse_install_ini(ini_path)
	if not next(entries) then
		log.debug("No entries found in install registry: %s", ini_path)
		return nil
	end

	-- Direct match (GUID or exact key)
	if entries[association] then
		return entries[association]
	end

	-- Try matching by version string in paths (e.g. "5.4" matching a path containing "UE_5.4")
	for _, path in pairs(entries) do
		if path:find(association, 1, true) then
			return path
		end
	end

	log.debug("Could not resolve EngineAssociation '%s' from install registry", association)
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

--- Resolve engine config from raw project config and .uproject engine association.
--- Priority: explicit engine.folder in config > EngineAssociation from .uproject.
---@param raw_config table
---@param uproject_path? string path to .uproject for engine association resolution
---@return { folder: string|nil, allow_modifications: boolean }
function M.resolve_engine_config(raw_config, uproject_path)
	local folder, allow_mods

	-- Check for explicit engine path in config
	if raw_config.engine then
		folder = raw_config.engine.folder
		allow_mods = raw_config.engine.allow_modifications
	end

	-- Validate explicit path exists on disk; fall through to GUID resolution if not
	if folder and vim.fn.isdirectory(folder) ~= 1 then
		log.warn("Configured engine path does not exist: %s — falling back to EngineAssociation", folder)
		folder = nil
	end

	-- If no explicit path, resolve from .uproject EngineAssociation
	if not folder and uproject_path then
		local association = M.read_engine_association(uproject_path)
		if association then
			folder = M.resolve_engine_association(association)
			if folder then
				log.info("Resolved engine path from EngineAssociation '%s': %s", association, folder)
			end
		end
	end

	return {
		folder = folder,
		allow_modifications = allow_mods or false,
	}
end

--- Recursively scan a directory for .uplugin files.
---@param dir string directory to scan
---@param plugins UnrealiumPlugin[] accumulator for discovered plugins
local function scan_for_plugins(dir, plugins)
	local handle = vim.uv.fs_scandir(dir)
	if not handle then
		return
	end

	while true do
		local name, typ = vim.uv.fs_scandir_next(handle)
		if not name then
			break
		end
		if typ == "directory" then
			local dir_path = vim.fs.joinpath(dir, name)
			local uplugin = find_file_with_extension(dir_path, "uplugin")
			if uplugin then
				table.insert(plugins, { name = name, path = dir_path, uplugin = uplugin })
			else
				-- Recurse deeper to find nested plugins
				scan_for_plugins(dir_path, plugins)
			end
		end
	end
end

--- Discover plugins in the project's Plugins/ directory.
--- Recursively scans for directories containing .uplugin files at any depth.
---@param project_root string
---@return UnrealiumPlugin[]
function M.discover_plugins(project_root)
	local plugins_dir = vim.fs.joinpath(project_root, "Plugins")
	local plugins = {}
	scan_for_plugins(plugins_dir, plugins)

	table.sort(plugins, function(a, b)
		return a.name < b.name
	end)

	return plugins
end

if _TEST then
	M._find_file_with_extension = find_file_with_extension
	M._read_json_file = read_json_file
	M._parse_install_ini = parse_install_ini
end

return M
