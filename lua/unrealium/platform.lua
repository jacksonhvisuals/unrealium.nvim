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

---@alias ClangDatabaseGenMode integer
---| "Project" | "Engine"
local ClangDatabaseGenMode = {
	Project = 0,
	Engine = 1,
}

---Returns the GenerateClangDatabase args for the Engine
---@param config UnrealiumConfig
---@param genMode ClangDatabaseGenMode
---@return table args
local function getGenClangDBArgs(config, genMode)
	local outputDir = ""
	local targetName = ""
	local projectArg = ""

	if genMode == ClangDatabaseGenMode.Project then
		outputDir = config.Engine.Folder
		targetName = "Unreal"
		projectArg = ""
	else
		outputDir = config.Project.Folder
		targetName = config.Project.Name
		projectArg = '-project="' .. config.Project.FullPath .. '"'
	end

	return {
		"-mode=GenerateClangDatabase",
		projectArg,
		targetName .. "Editor " .. config.PlatformName .. " Development",
		'-OutputDir="' .. outputDir .. '"',
	}
end

---Returns the GenerateClangDatabase args for the Engine
---@param config UnrealiumConfig
local function getUHTArgs(config)
	return {
		config.Project.Name .. "Editor " .. config.PlatformName .. " Development",
		"-SkipBuild",
		'-project="' .. config.Project.FullPath .. '"',
	}
end

---@alias IDE string
---| "VSCode" | "Rider" | "Makefile"
local IDE = {
	VSCode = "-VSCode",
	Rider = "-Rider",
	Makefile = "-Makefile",
}

---Collects the correct GenProjFiles arguments for the given Platform
---@param config UnrealiumConfig
---@param ide IDE
---@return table args
local function getGenProjFilesArgs(config, ide)
	return {
		"-projectfiles",
		'-project="' .. config.Project.FullPath .. '"',
		ide,
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

---Obtains the full Generate Project Files command for the given Platform
---@param config UnrealiumConfig
---@return string
function M.getGenProjFilesCommand(config)
	local command = { "Dispatch", config.Engine.Scripts.GenerateProjectFiles }

	local args = getGenProjFilesArgs(config, IDE.Makefile)
	vim.list_extend(command, args)

	return table.concat(command, " ")
end

---Obtains the full Generate Clang Database command for the given Platform
---@param config UnrealiumConfig
---@return string
function M.getGenClangDatabaseCommands(config)
	local command = { "Dispatch", config.Engine.Scripts.RunUBT }
	local engineCommand = command
	local engineArgs = getGenClangDBArgs(config, ClangDatabaseGenMode.Engine)
	vim.list_extend(engineCommand, engineArgs)

	local projectCommand = command
	local projectArgs = getGenClangDBArgs(config, ClangDatabaseGenMode.Project)
	vim.list_extend(projectCommand, projectArgs)

	vim.list_extend(engineCommand, { "&&" })
	vim.list_extend(engineCommand, projectCommand)

	return table.concat(engineCommand, " ")
end

if _TEST then
	M.getGenProjFilesArgs = getGenProjFilesArgs
	M.getBuildArgs = getBuildArgs
end

return M
