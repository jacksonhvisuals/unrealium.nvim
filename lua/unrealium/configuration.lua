local globals = require("unrealium.globals")
local foundation = require("unrealium.foundation")

local CONFIG_DIR_NAME = globals.UnrealiumConfigDir
local CONFIG_FILE_NAME = globals.UnrealiumConfigFile
local UPROJECT_FILE_EXT = globals.UnrealProjectExt

local Path = require("plenary.path")
local uv = vim.uv
local cwd = uv.cwd()

local M = {}

-- TODO:
-- A func for creating a new config file (interactive?)
-- A func for finding the Unreal Engine root directory
-- A func for adding the Engine Source to the search paths of Telescope

---Ensures that the config directory exists in the CWD, creating one if not.
---@return Path
function M._ensureConfigDirectory()
	local fullDirPath = cwd .. "/" .. CONFIG_DIR_NAME

	local configDir = Path:new(fullDirPath) -- path

	if not configDir:exists() then
		foundation.logMessage("Unrealium directory (.unrealium) did not exist. Creating...")
		configDir:mkdir()
	end

	return configDir
end

---Ensures that the config.json file exists at the given path, creating one if not.
---@param fullDirPath string
---@return Path
function M._ensureConfigFile(fullDirPath)
	local configFilePath = tostring(fullDirPath) .. "/" .. CONFIG_FILE_NAME
	local configFile = Path:new(configFilePath) -- path

	if not configFile:exists() then
		foundation.logError("Unrealium config JSON did not exist. Generating a new one.")
		configFile:touch()
	end

	return configFile
end

---Fetches the config file as a table.
---@return table
function M.readUnrealiumConfig()
	local configDir = M._ensureConfigDirectory()
	local configFile = M._ensureConfigFile(configDir.filename)

	local file = io.open(configFile.filename, "r")
	local data = {}

	if file then
		local content = file:read("*all")

		if content ~= "" then
			data = vim.fn.json_decode(content)
		else
			data = {}
		end
	else
		data = {}
	end

	file:close()

	if next(data) == nil then
		foundation.logError("Unrealium JSON file was empty.")
	end

	return data
end

---Fetches the "EnginePath" value from a table
---@param config table
---@return string
function M._getEngineDirectory(config)
	if config["EnginePath"] ~= nil then
		return config["EnginePath"]
	end

	return "None"
end

---Queries whether or not cwd houses a .uproject file
---@return boolean
function M._directoryHasUProject()
	local found = false

	-- See if there is a file in the CWD that has a .uproject extension
	for name in vim.fs.dir(cwd) do
		if name:sub(-#UPROJECT_FILE_EXT) == UPROJECT_FILE_EXT then
			found = true
			break
		end
	end

	return found
end

---Fetches the full path of the .uproject file
---@return Path | nil
function M.getUProjectPath()
	local dir = uv.fs_opendir(cwd, nil, 50)
	if not dir then
		return nil
	end

	while true do
		local entries = uv.fs_readdir(dir)
		if not entries then
			break
		end

		for _, entry in ipairs(entries) do
			if entry.type == "file" and entry.name:sub(-#UPROJECT_FILE_EXT) == UPROJECT_FILE_EXT then
				uv.fs_closedir(dir)
				return Path:new(cwd .. "/" .. entry.name)
			end
		end

		uv.fs_closedir(dir)
		return nil
	end
end

M.ProjectName = vim.fn.fnamemodify(M.getUProjectPath().filename, ":t"):match("^[^.]+")

return M
