local config = require("unrealium.configuration")
local utils = require("unrealium.utils")
local logError = config.logError
local log = config.log

local M = {}

---Collects the correct Build arguments for the given Platform
---@param config UnrealiumConfig
---@return table args
local function getBuildArgs(config)
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
local function getGenProjFilesArg(config)
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
---@return string
function M.getBuildCommand(config)
	local Platform = config.PlatformName
	local command = {}

	if Platform == "Linux" then
		table.insert(command, "Make")
	elseif Platform == "Mac" then
		table.insert(command, "Dispatch")
		table.insert(command, "xcodebuild")
	end

	local args = getBuildArgs(config)
	vim.list_extend(command, args)

	return table.concat(command, " ")
end

---Obtains the full Generate Project Files ccommand for the given Platform
---@param config UnrealiumConfig
---@return string
function M.getGenProjFilesCommand(config)
	local Platform = config.PlatformName
	local command = { "Dispatch", config.Engine.Scripts.GenerateProjectFiles }

	local args = getGenProjFilesArg(config)
	vim.list_extend(command, args)

	return table.concat(command, " ")
end

return M
