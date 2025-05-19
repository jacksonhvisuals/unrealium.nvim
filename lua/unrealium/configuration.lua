---@alias LOG_LEVEL integer
---| "ERROR" | "WARNING" | "LOG" | "VERBOSE" | "VERY_VERBOSE"
local LOG_LEVEL = {
	ERROR = 1,
	WARNING = 2,
	LOG = 3,
	VERBOSE = 4,
	VERY_VERBOSE = 5,
}

local LOG_FILE_PATH = vim.fn.stdpath("data") .. "/unrealium.log"

-- Set up (local) globals
local PLATFORM_NAME = "Linux"
local CONFIG_DIR_NAME = ".unrealium"
local CONFIG_FILE_NAME = "config.json"
local BUILD_FILES_SUBPATH = "Engine/Build/BatchFiles/" .. PLATFORM_NAME
local EDITOR_SUBPATH = "Engine/Binaries/" .. PLATFORM_NAME

-- Get various useful modules
local Path = require("plenary.path")
local uv = vim.uv
local cwd = uv.cwd()

local M = {}

---Handles logging, taking verbosity preference into account.
---@param verbosity LOG_LEVEL
---@param message string
local function logWithVerbosity(verbosity, message)
	local verbosityPref = LOG_LEVEL.LOG
	if vim.g.unrealium_loglevel then
		verbosityPref = vim.g.unrealium_loglevel
	end

	if verbosity > verbosityPref then
		return
	end

	local time = os.date("%m/%d/%y %H:%M:%S")
	local msg = string.format("[%s][%s]: %s\n", time, verbosity, message)
	uv.fs_open(LOG_FILE_PATH, "a", 438, function(err, fd)
		if fd then
			uv.fs_write(fd, msg, -1, function()
				uv.fs_close(fd)
			end)
		else
			vim.notify(err)
		end
	end)
end

---Wrapper for general logs in logWithVerbosity for convenience
---@param message string
local function log(message)
	if not message then
		logWithVerbosity(LOG_LEVEL.ERROR, "${message} was nil")
		return
	end

	logWithVerbosity(LOG_LEVEL.LOG, message)
end

---Wrapper for logging errors via logWithVerbosity for convenience
---@param message string
local function logError(message)
	if not message then
		logWithVerbosity(LOG_LEVEL.ERROR, "${message} was nil")
		return
	end

	logWithVerbosity(LOG_LEVEL.ERROR, message)
end

if not vim.g.unrealium_config_loaded then
	-- TODO: Set up the main global var with all the necessary values
	-- then set the value to true
	vim.g.unrealium_config_loaded = true
end

-- TODO:
-- A func for creating a new config file (interactive?)
-- A func for finding the Unreal Engine root directory
-- A func for adding the Engine Source to the search paths of Telescope

---Ensures that the config directory exists in the CWD, creating one if not.
---@return Path
local function ensureConfigDirectory()
	local fullDirPath = cwd .. "/" .. CONFIG_DIR_NAME

	local configDir = Path:new(fullDirPath) -- path

	if not configDir:exists() then
		log("Unrealium directory (.unrealium) did not exist. Creating...")
		configDir:mkdir()
	end

	return configDir
end

---Ensures that the config.json file exists at the given path, creating one if not.
---@param fullDirPath string
---@return Path
local function ensureConfigFile(fullDirPath)
	local configFilePath = tostring(fullDirPath) .. "/" .. CONFIG_FILE_NAME
	local configFile = Path:new(configFilePath) -- path

	if not configFile:exists() then
		logError("Unrealium config JSON did not exist. Generating a new one.")
		configFile:touch()
	end

	return configFile
end

---Fetches the config file as a table.
---@return table
local function readUnrealiumConfig()
	local configDir = ensureConfigDirectory()
	local configFile = ensureConfigFile(configDir.filename)

	local file = io.open(configFile.filename, "r")
	local data = {}

	if file then
		local content = file:read("*all")

		if content ~= "" then
			data = vim.fn.json_decode(content)
		else
			data = {}
		end

		file:close()
	else
		data = {}
	end

	if next(data) == nil then
		logError("Unrealium JSON file was empty.")
	end

	return data
end

---Fetches the "EnginePath" value from a table
---@param config table
---@return string
local function _getEngineDirectory(config)
	if config["EnginePath"] ~= nil then
		return config["EnginePath"]
	end

	return "None"
end

---Looks in the current directory for a file with the given extension
---@param directory string
---@param extension string
---@return Path | nil
local function checkForFileWithExtensionInDir(directory, extension)
	local dir = vim.loop.fs_opendir(directory)
	if not dir then
		return nil
	end

	handle = vim.loop.fs_scandir(directory)
	local name, typ

	while handle do
		name, typ = vim.loop.fs_scandir_next(handle)
		if not name then
			break
		end
		if typ == "file" then
			local ext = vim.fn.fnamemodify(name, ":e")
			if ext == extension then
				return Path:new(directory .. "/" .. name)
			end
		end
	end
	return nil
end

---Checks (recursively) if a file with the given extension
---exists in the current or parent directories of the given filepath.
---@param filepath Path
---@param extension string
---@return Path | nil
local function getDirectoryWithFileWithExtension(filepath, extension)
	local currentDir
	if not filepath:is_dir() then
		currentDir = filepath:parent()
	else
		currentDir = filepath
	end

	local foundFile = checkForFileWithExtensionInDir(currentDir.filename, extension)

	if foundFile then
		return foundFile
	end

	local parentDir = currentDir:parent()
	if parentDir.filename ~= currentDir.filename then
		log("Couldn't find " .. extension .. " at " .. currentDir.filename)
		return getDirectoryWithFileWithExtension(parentDir, extension)
	end

	-- File not found
	return nil
end

---Primary function to get the directory of
---a uProject, if it exists in the path
---@return Path | nil
local function getUProjectFile()
	local CurrentPath = Path:new(cwd)
	return getDirectoryWithFileWithExtension(CurrentPath, "uproject")
end

---@class UnrealiumConfig
---@field BatchFilesDir string
---@field ProjectName string
---@field ProjectFolder string
---@field EngineFolder string

---Attempts to get the UnrealiumConfig, if in a valid directory.
---@return UnrealiumConfig | nil
function M.get()
	local uProjectDir = getUProjectFile()
	if not uProjectDir then
		return nil
	end

	local config = {} ---@type UnrealiumConfig
	config.ProjectName = vim.fn.fnamemodify(uProjectDir.filename, ":t:r")
	config.ProjectFolder = vim.fn.fnamemodify(uProjectDir.filename, ":h")
	config.BatchFilesDir = "test"

	-- Ensure the config file
	-- Read config file and set values
	-- if no config file, create template & prompt user, return nil

	return config
end

return M
