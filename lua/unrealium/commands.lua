local logPath = vim.fn.stdpath("data") .. "/unrealium.log"

--[[ Main functions for Unrealium ]]

local Commands = {}

function Commands:uGenerateProjectFiles(opts)
	print("Generating project files...")
	local conf = require("unrealium.configuration")
	local cli = require("unrealium.cli")

	local unrealium = conf.get()

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
	local conf = require("unrealium.configuration")
	local cli = require("unrealium.cli")

	local unrealium = conf.get()

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
end

function Commands:uDebug(opts)
	print("Launching UnrealEditor & attaching debugger.")
end

return Commands
