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

---Ensures that the config directory exists in the CWD, creating one if not.
---@return Path
function M._ensureConfigDirectory()
	local fullDirPath = cwd .. "/" .. configDirName

	local configDir = path:new(fullDirPath) -- path

	if not configDir:exists() then
		print("Unrealium directory (.unrealium) did not exist. Creating...")
		configDir:mkdir()
	end

	return configDir
end

---Ensures that the config.json file exists at the given path, creating one if not.
---@param fullDirPath string
---@return Path
function M._ensureConfigFile(fullDirPath)
	local configFilePath = tostring(fullDirPath) .. "/" .. configFileName
	local configFile = path:new(configFilePath) -- path

	if not configFile:exists() then
		print("Unrealium config JSON did not exist. Generating a new one.")
		configFile:touch()
	end

	return configFile
end

---Fetches the config file as a table.
---@return table
function M.getUnrealiumConfig()
	local configDir = M._ensureConfigDirectory()
	local configFile = M._ensureConfigFile(configDir.filename)

	local file = io.open(configFile.filename, "r")
	local data = {}

	if file then
		local content = file:read("*all")

		if content ~= "" then
			data = vim.fn.json_decode(content)
			print("Decoded JSON file.")
		else
			data = {}
		end

		file:close()
	else
		data = {}
	end

	if next(data) == nil then
		print("JSON file was empty.")
	else
		print(data)
	end
end

return M
