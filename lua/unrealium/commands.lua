local logPath = vim.fn.stdpath("data") .. "/unrealium.log"

--[[ Main functions for Unrealium ]]

local Commands = {}

local conf = require("unrealium.configuration")
Commands.unrealium = conf.get()
if not Commands.unrealium then
	conf.logError("Could not get unrealium config for Commands.")
	return {}
end

function Commands:USearch(cmd, context)
	conf.log("Received cmd: " .. cmd .. ", context: " .. context)
	local searchDirs = {}

	if context == "Engine" then
		searchDirs = { UnrealiumConfig.Engine.Folder }
	elseif context == "Project" then
		searchDirs = { UnrealiumConfig.Project.Folder }
	else
		searchDirs = { UnrealiumConfig.Engine.Folder, UnrealiumConfig.Project.Folder }
	end

	require("telescope.builtin")[cmd]({ search_dirs = searchDirs })
end

---@param type string "Debug" or "Development"
function Commands:URun(type)
	if type == nil then
		type = "Development"
	end
	conf.log("Launching UnrealEditor in " .. type .. " mode")

	local unrealium = self.unrealium
	if not unrealium then
		conf.logError("Something went wrong.")
		return
	end

	conf.log("Running Unreal Engine")

	local suffix = ""
	if type == "Debug" then
		suffix = "-" .. unrealium.PlatformName .. "-Debug"
	end

	local EditorExecutable = unrealium.Engine.Scripts.EditorBase .. suffix
	local debugCmd = "Dispatch " .. EditorExecutable .. " " .. unrealium.Project.FullPath
	conf.log("Running " .. debugCmd)
	vim.cmd(debugCmd)
end

---@param type string "Debug" or "Development"
function Commands:UBuild(type)
	if type == nil then
		type = "Development"
	end
	conf.log("Attempting to build Unreal project with " .. type .. " configuration")

	local unrealium = self.unrealium
	if not unrealium then
		conf.logError("Something went wrong.")
		return
	end

	local buildTypeSuffix = "Editor-" .. unrealium.PlatformName
	if type == "Debug" then
		buildTypeSuffix = buildTypeSuffix .. "-Debug"
	else
		buildTypeSuffix = buildTypeSuffix .. "-Development"
	end

	conf.log("Changing directory to " .. unrealium.Project.Folder)
	vim.cmd("cd " .. unrealium.Project.Folder)
	local makeCmd = "Make " .. unrealium.Project.Name .. buildTypeSuffix
	conf.log("Running " .. makeCmd)
	vim.cmd(makeCmd)
end

function Commands:uGenerateProjectFiles(opts)
	conf.log("Generating project files...")

	local unrealium = self.unrealium
	if not unrealium then
		conf.logError("Something went wrong.")
		return
	end

	local buildScript = unrealium.Engine.Scripts.Build
	local commandExtras = "-game -engine -progress"
	local command = buildScript .. ' -projectfiles -project="' .. unrealium.Project.Path .. '" ' .. commandExtras
	local runCmd = "Dispatch " .. command
	conf.log("Running " .. runCmd)
	vim.cmd(runCmd)
end

---@param filePath string The file path of the newly-opened file
function Commands:DetermineFileEditable(filePath)
	local unrealium = self.unrealium
	if not unrealium then
		conf.logError("Unrealium config was nil when trying to determine file editability for " .. filePath)
		return
	end

	if unrealium.Engine.AllowEngineModifications then
		conf.log("AllowEngineModifications is true, so modifiable is true for " .. filePath)
		return
	end

	if vim.startswith(filePath, unrealium.Engine.Folder) then
		conf.log("AllowEngineModifications is false, setting modifiable false for " .. filePath)
		vim.bo.modifiable = false
	end
end

return Commands
