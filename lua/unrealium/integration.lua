local logPath = vim.fn.stdpath("data") .. "/unrealium.log"

--[[ Main functions for Unrealium ]]

local Commands = {}

function Commands.uGenerateProjectFiles(opts)
	print("Generating project files... done.")
end

function Commands.uBuild(opts)
	print("Building Unreal project.")
	local cmds = require("unrealium.configuration")

	if not cmds._directoryHasUProject() then
		print("The CWD does not have a .uproject, aborting.")
		return
	end

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
