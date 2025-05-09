local logPath = vim.fn.stdpath("data") .. "/unrealium.log"

--[[ Main functions for Unrealium ]]

local Commands = {}

function Commands.uGenerateProjectFiles(opts)
	print("Generating project files... done.")
	local conf = require("unrealium.configuration")

	if not conf._directoryHasUProject() then
		print("The CWD does not have a .uproject, aborting.")
		return
	end

	local globals = require("unrealium.globals")

	local uconfig = conf.getUnrealiumConfig()
	local engineDir = conf._getEngineDirectory(uconfig)
	local buildScript = engineDir .. globals.BatchFileSubpath .. "/Build.sh"

	local uprojectFilePath = conf.getUProjectPath()
	if not uprojectFilePath then
		print("Received no uprojectFilePath")
		return
	end

	local commandExtras = "-game -engine -progress"
	local command = buildScript .. '-projectfiles -project="' .. uprojectFilePath .. '" ' .. commandExtras
	print("Command to execute would be: " .. command)
end

Commands.uGenerateProjectFiles()

function Commands.uBuild(opts)
	local conf = require("unrealium.configuration")

	if not conf._directoryHasUProject() then
		print("The CWD does not have a .uproject, aborting.")
		return
	end

	print("Building Unreal project.")
	local cli = require("unrealium.cli")

	cli.runCommandInSmallTerminal("make")
end

function Commands.uRun(opts)
	print("Launching UnrealEditor for $ProjectName.")
end

function Commands.uDebug(opts)
	print("Launching UnrealEditor & attaching debugger.")
end

return Commands
