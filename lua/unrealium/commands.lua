local logPath = vim.fn.stdpath("data") .. "/unrealium.log"

--[[ Main functions for Unrealium ]]

local Commands = {}

local conf = require("unrealium.configuration")
Commands.unrealium = conf.get()
if not Commands.unrealium then
	conf.logError("Could not get unrealium config for Commands.")
	return {}
end

function Commands:uGenerateProjectFiles(opts)
	print("Generating project files...")

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

function Commands:uBuild(opts)
	print("Attempting to build Unreal project...")

	local unrealium = self.unrealium
	if not unrealium then
		conf.logError("Something went wrong.")
		return
	end

	conf.log("Changing directory to " .. unrealium.ProjectFolder)
	vim.cmd("cd " .. unrealium.ProjectFolder)
	local makeCmd = "Make " .. unrealium.ProjectName .. "Editor-" .. unrealium.PlatformName .. "-Development"
	conf.log("Running " .. makeCmd)
	vim.cmd(makeCmd)
end

function Commands:uRun(opts)
	print("Launching UnrealEditor for $ProjectName.")

	local unrealium = self.unrealium
	if not unrealium then
		conf.logError("Something went wrong.")
		return
	end

	conf.log("Running Unreal Engine")

	local runCmd = "Dispatch " .. unrealium.Scripts.EditorBase .. " " .. unrealium.ProjectPath
	vim.cmd(runCmd)
end

function Commands:uDebug(opts)
	print("Launching UnrealEditor Debug for $ProjectName.")

	local unrealium = self.unrealium
	if not unrealium then
		conf.logError("Something went wrong.")
		return
	end

	conf.log("Running Unreal Engine")
	local EditorExecutable = unrealium.Scripts.EditorBase .. "-" .. unrealium.PlatformName .. "-Debug"
	local debugCmd = "Dispatch " .. EditorExecutable .. " " .. unrealium.ProjectPath
	conf.log("Running " .. debugCmd)
	vim.cmd(debugCmd)
end

return Commands
