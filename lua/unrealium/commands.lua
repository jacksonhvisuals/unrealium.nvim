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
		searchDirs = { UnrealiumConfig.EngineFolder }
	elseif context == "Project" then
		searchDirs = { UnrealiumConfig.ProjectFolder }
	elseif context == "All" then
		searchDirs = { UnrealiumConfig.EngineFolder, UnrealiumConfig.ProjectFolder }
	end

	require("telescope.builtin")[cmd]({ search_dirs = searchDirs })
end

---@param type string "Debug" or "Development"
function Commands:URun(type)
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

	local EditorExecutable = unrealium.Scripts.EditorBase .. suffix
	local debugCmd = "Dispatch " .. EditorExecutable .. " " .. unrealium.ProjectPath
	conf.log("Running " .. debugCmd)
	vim.cmd(debugCmd)
end

---@param type string "Debug" or "Development"
function Commands:UBuild(type)
	print("Attempting to build Unreal project...")

	local unrealium = self.unrealium
	if not unrealium then
		conf.logError("Something went wrong.")
		return
	end

	local buildTypeSuffix = "Editor-" .. unrealium.PlatformName .. "-" .. type

	conf.log("Changing directory to " .. unrealium.ProjectFolder)
	vim.cmd("cd " .. unrealium.ProjectFolder)
	local makeCmd = "Make " .. unrealium.ProjectName .. buildTypeSuffix
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

	local buildScript = unrealium.Scripts.Build
	local commandExtras = "-game -engine -progress"
	local command = buildScript .. ' -projectfiles -project="' .. unrealium.ProjectPath .. '" ' .. commandExtras
	local runCmd = "Dispatch " .. command
	conf.log("Running " .. runCmd)
	vim.cmd(runCmd)
end

return Commands
