local logPath = vim.fn.stdpath("data") .. "/unrealium.log"

--[[ Main functions for Unrealium ]]

local Commands = {}

function Commands:uGenerateProjectFiles(opts)
	print("Generating project files... done.")
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
	cli.runCommand(command)
end

function Commands:uBuild(opts)
	local conf = require("unrealium.configuration")

	if not conf._directoryHasUProject() then
		print("The CWD does not have a .uproject, aborting.")
		return
	end

	print("Building Unreal project.")
	local cli = require("unrealium.cli")

	cli.runCommandInSmallTerminal("make")
end

function Commands:uRun(opts)
	print("Launching UnrealEditor for $ProjectName.")
end

function Commands:uDebug(opts)
	print("Launching UnrealEditor & attaching debugger.")
end

return Commands
