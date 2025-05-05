local logPath = vim.fn.stdpath("data") .. "/unrealium.log"

--[[ Main functions for Unrealium ]]

local Commands = {}

function Commands.uGenerateProjectFiles(opts)
	print("Generating project files... done.")
end

function Commands.uBuild(opts)
	print("Building Unreal project.")
end

function Commands.uRun(opts)
	require("unrealium")
	print("Launching UnrealEditor for $ProjectName.")
end

function Commands.uDebug(opts)
	require("unrealium")
	print("Launching UnrealEditor & attaching debugger.")
end

return Commands
