local logPath = vim.fn.stdpath("data") .. "/unrealium.log"

--[[ Main functions for Unrealium ]]

local Commands = {}

function Commands.uGenerateProjectFiles(opts)
	print("Generating project files... done.")
end

function Commands.uBuild(opts)
	print("Building Unreal project.")
	-- Ensure Correct Directory
	-- Get the Unreal Builder Executable (build.sh)
	-- Execute it
end

function Commands.uRun(opts)
	print("Launching UnrealEditor for $ProjectName.")
end

function Commands.uDebug(opts)
	print("Launching UnrealEditor & attaching debugger.")
end

return Commands
