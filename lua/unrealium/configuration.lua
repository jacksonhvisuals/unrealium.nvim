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
local CONFIG_FILE_NAME = ".unrealium"
local BATCH_FILES_SUBPATH = "Engine/Build/BatchFiles" ---@see Needs platform subfoler

-- Get various useful modules
local uv = vim.uv
local utils = require("unrealium.utils")

---@class EngineConfig
---@field Folder string
---@field Scripts EngineScripts
---@field AllowEngineModifications boolean

---@class ProjectConfig
---@field Folder string
---@field FullPath string
---@field Name string

---@class EngineScripts
---@field Build string
---@field GenerateProjectFiles string
---@field RunUBT string
---@field EditorBase string The UnrealEditor, but can have strings appended for various build targets.

---@class UnrealiumConfig
---@field Project ProjectConfig
---@field Engine EngineConfig
---@field PlatformName string

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
			if err ~= nil then
				vim.notify(err)
			end
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

---Checks to see if the .unrealium file exists at the given path
---@param projectDirectory string the Unreal Engine Project folder path
---@return string | nil
local function getConfigFile(projectDirectory)
	local configFilePath = utils.joinPath(projectDirectory, CONFIG_FILE_NAME)

	if not vim.fs.exists(configFilePath) then
		logError(
			"Unrealium config file (.unrealium) did not exist at your .uproject path, ("
				.. projectDirectory
				.. ". Please create one."
		)
		return nil
	end

	if vim.fs.isdirectory(configFilePath) then
		logError("Unrealium found a config folder called .unrealium, not a config ~file~. Please fix.")
		return nil
	end
	return configFilePath
end

---Fetches the config file as a table.
---@param uProjectDirectory string
---@return table | nil
local function readUnrealiumConfig(uProjectDirectory)
	local configFile = getConfigFile(uProjectDirectory)
	if not configFile then
		if not uProjectDirectory then
			uProjectDirectory = "nil"
		end
		logError("Config file did not exist at " .. uProjectDirectory)
		return nil
	end

	local file = io.open(configFile, "r")
	local data = {}

	if file then
		local content = file:read("*all")

		if content ~= "" then
			content = content:gsub("^\xEF\xBB\xBF", "")
			local ok, decode = pcall(vim.fn.json_decode, content)
			if not ok then
				logError("Unrealium file was not readable")
				return nil
			end

			data = decode
		end

		file:close()
	else
		return nil
	end

	if next(data) == nil then
		logError("Unrealium JSON file was empty.")
		return nil
	else
		return data
	end
end

---Fetches the "EnginePath" value from a table
---@param config table
---@return string | nil
local function getEnginePath(config)
	local enginePath = config["EnginePath"] ---@type string
	if enginePath ~= nil then
		if vim.fs.exists(enginePath) then
			return enginePath
		end
	end

	return nil
end

---Fetches the system name.
---@return string platformName a UBT-friendly platform string
local function getPlatformName()
	local sysname = vim.loop.os_uname().sysname

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

---Fetches the "allowEngineModifications" value from a table, falls back to false
---@param config table
---@return boolean
local function getEngineModifiablePref(config)
	local configValue = config["allowEngineModifications"] ---@type boolean
	if configValue ~= nil then
		return configValue
	end

	return false
end

---Looks in the current directory for a file with the given extension
---@param directory string
---@param extension string
---@return string | nil
local function checkForFileWithExtensionInDir(directory, extension)
	local dir = vim.loop.fs_opendir(directory)
	if not dir then
		return nil
	end

	local handle = vim.loop.fs_scandir(directory)
	local name, typ

	while handle do
		name, typ = vim.loop.fs_scandir_next(handle)
		if not name then
			break
		end
		if typ == "file" then
			local ext = vim.fn.fnamemodify(name, ":e")
			if ext == extension then
				return utils.joinPath(directory, name)
			end
		end
	end
	return nil
end

---Checks (recursively) if a file with the given extension
---exists in the current or parent directories of the given filepath.
---@param path string
---@param extension string
---@return string | nil
local function getDirectoryWithFileWithExtension(path, extension)
	local currentDir
	if not vim.fn.isdirectory(path) then
		currentDir = vim.fn.fnamemodify(path, ":p:h")
	else
		currentDir = path
	end

	local foundFile = checkForFileWithExtensionInDir(currentDir, extension)

	if foundFile then
		return foundFile
	end

	local parentDir = vim.fn.fnamemodify(currentDir, ":p:h")
	if parentDir ~= currentDir then
		return getDirectoryWithFileWithExtension(parentDir, extension)
	end

	-- File not found
	return nil
end

---Primary function to get the directory of
---a uProject, if it exists in the path
---@return string | nil
local function getUProjectFile()
	local CurrentPath = uv.cwd()

	if CurrentPath ~= nil then
		return nil
	end

	local uProjectFile = getDirectoryWithFileWithExtension(CurrentPath, "uproject")
	if not uProjectFile then
		logError(
			"Could not find uProject file in the current cwd (" .. CurrentPath .. ") or any of its parent directories."
		)
	end

	return uProjectFile
end

---Builds the fields of EngineScripts
---@param enginePath string
---@param platformName string
---@return EngineScripts
local function getScriptPaths(enginePath, platformName)
	local Scripts = {} ---@type EngineScripts
	Scripts.Build = utils.joinPath(enginePath, BATCH_FILES_SUBPATH, platformName, "Build.sh")
	Scripts.GenerateProjectFiles =
		utils.joinPath(enginePath, BATCH_FILES_SUBPATH, platformName, "GenerateProjectFiles.sh")
	Scripts.EditorBase = utils.joinPath(enginePath, "Engine", "Binaries", platformName, "UnrealEditor")
	Scripts.RunUBT = utils.joinPath(enginePath, BATCH_FILES_SUBPATH, platformName, "RunUBT.sh")

	return Scripts
end

---Attempts to get the UnrealiumConfig, if in a valid directory.
---@return UnrealiumConfig | nil
function M.get()
	local uProjectPath = getUProjectFile()
	if not uProjectPath then
		return nil
	end

	local uProjectFilePath = uProjectPath
	local projectDir = vim.fn.fnamemodify(uProjectFilePath, ":h")

	local configData = readUnrealiumConfig(projectDir)
	if not configData then
		logError("Could not get the configData out of " .. projectDir)
		return nil
	end

	local engineDir = getEnginePath(configData)
	if not engineDir then
		--TODO: Write docs.
		logError("Looks like your .unrealium config is not set up yet. See :h unrealium.config for docs.")
		return nil
	end

	-- TODO:
	-- if no config file, create template & prompt user, return nil

	local config = {} ---@type UnrealiumConfig
	config.Project = {}
	config.Engine = {}
	config.Project.FullPath = uProjectFilePath
	config.PlatformName = getPlatformName()
	config.Project.Name = vim.fn.fnamemodify(uProjectFilePath, ":t:r")
	config.Project.Folder = projectDir
	config.Engine.Folder = engineDir
	config.Engine.AllowEngineModifications = getEngineModifiablePref(configData)
	config.Engine.Scripts = getScriptPaths(config.Engine.Folder, config.PlatformName)

	return config
end

M.log = log
M.logError = logError

if _TEST then
	M._readUnrealiumConfig = readUnrealiumConfig
	M._getEnginePath = getEnginePath
	M._getPlatformName = getPlatformName
	M._getScriptPaths = getScriptPaths
	M._getEngineModifiablePref = getEngineModifiablePref
	M._getDirectoryWithFileExtension = getDirectoryWithFileWithExtension
	M._checkForFileWithExtensionInDir = checkForFileWithExtensionInDir
	M._getConfigFile = getConfigFile
end

return M
