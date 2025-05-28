local configuration = require("unrealium.configuration")
local logError = configuration.logError
local log = configuration.log

local M = {}

---Collects the correct Build arguments for the given Platform
---@param config UnrealiumConfig
---@param type string
---@return table args
local function getBuildArgs(config, type)
	local args = {}
	if config.PlatformName == "Linux" then
		local buildTypeSuffix = "Editor-" .. config.PlatformName
		if type == "Debug" then
			buildTypeSuffix = buildTypeSuffix .. "-Debug"
		else
			buildTypeSuffix = buildTypeSuffix .. "-Development"
		end

		local makeCmd = config.Project.Name .. buildTypeSuffix
		args = { makeCmd }
	else
		logError("Current platform " .. config.PlatformName .. " is not yet supported.")
	end

	return args
end

---Collects the correct GenProjFiles arguments for the given Platform
---@param config UnrealiumConfig
---@return table args
local function getGenProjFilesArgs(config)
	return {
		"-projectfiles",
		'-project="' .. config.Project.FullPath .. '"',
		"-VSCode",
		"-game",
		"-engine",
		"-progress",
	}
end

---Obtains the full Build command for the given Platform
---@param config UnrealiumConfig
---@param type string build target type (Debug/Development)
---@return string
function M.getBuildCommand(config, type)
	local Platform = config.PlatformName
	local command = {}

	if Platform == "Linux" then
		table.insert(command, "Make")
	elseif Platform == "Mac" then
		table.insert(command, "Dispatch")
		table.insert(command, "xcodebuild")
	end

	local args = getBuildArgs(config, type)
	vim.list_extend(command, args)

	return table.concat(command, " ")
end

---Obtains the full Generate Project Files ccommand for the given Platform
---@param config UnrealiumConfig
---@return string
function M.getGenProjFilesCommand(config)
	local command = { "Dispatch", config.Engine.Scripts.GenerateProjectFiles }

	local args = getGenProjFilesArgs(config)
	vim.list_extend(command, args)

	return table.concat(command, " ")
end

if _TEST then
	M.getGenProjFilesArgs = getGenProjFilesArgs
	M.getBuildArgs = getBuildArgs
end

return M
