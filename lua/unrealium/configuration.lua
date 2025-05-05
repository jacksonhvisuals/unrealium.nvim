local configDirName = ".unrealium"
local configFileName = "config.json"

local path = require("plenary.path")
local uv = vim.uv
local cwd = uv.cwd()

local M = {}

-- A func for loading the config file
-- A func for creating a new config file (interactive?)
-- A func for finding the Unreal Engine root directory
-- A func for adding the Engine Source to the search paths of Telescope

function M._ensureConfigDirectory()
	local fullDirPath = cwd .. "/" .. configDirName

	local configDir = path:new(fullDirPath) -- path

	if not configDir:exists() then
		print("Unrealium directory (.unrealium) did not exist. Creating...")
		configDir:mkdir()
	end

	return configDir
end

function M._ensureConfigFile(fullDirPath)
	local configFilePath = fullDirPath .. "/" .. configFileName
	local configFile = path:new(configFilePath) -- path

	if not configFile:exists() then
		print("Unrealium config JSON did not exist. Generating a new one.")
		configFile:touch()
	end
end

function M.getUnrealiumConfig()
	local configDir = M._ensureConfigDirectory()
	local configFile = M._ensureConfigFile(configDir.filename)

	return configFile
end

return M
