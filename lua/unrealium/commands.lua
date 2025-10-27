--[[ Main functions for Unrealium ]]

local Commands = {}

local conf = require("unrealium.configuration")
Commands.unrealium = conf.get()
if not Commands.unrealium then
	conf.logError("Could not get unrealium config for Commands.")
	return {}
end

local platform = require("unrealium.platform")

---@alias SearchTypes
---| grep "grep"
---| file_search "file_search"
local SearchTypes = {
	grep = "grep",
	file_search = "file_search",
}

---A wrapper for Telescope search so as to filter Engine vs Project
---@param search_type SearchTypes the modes of search
---@param context string the categories to search: Engine / Project / All
function Commands:USearch(search_type, context)
	conf.log("Received cmd: " .. search_type .. ", context: " .. context)
	local searchDirs = {}

	if context == "Engine" then
		searchDirs = { UnrealiumConfig.Engine.Folder }
	elseif context == "Project" then
		searchDirs = { UnrealiumConfig.Project.Folder }
	else
		searchDirs = { UnrealiumConfig.Engine.Folder, UnrealiumConfig.Project.Folder }
	end

	if require("snacks") == nil then
		conf.logError("Doesn't seem like Snacks.nvim is available for search")
		return
	end

	if search_type == SearchTypes.file_search then
		require("snacks").picker.grep({ dirs = searchDirs, exclude = platform.getIgnoredFileExtensions() })
	elseif search_type == SearchTypes.grep then
		require("snacks").picker.files({ dirs = searchDirs, exclude = platform.getIgnoredFileExtensions() })
	end
end

---Launches Unreal Engine in either Development or Debug mode with the current Unreal Project
---@param type string "Debug" / "Development"
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

---Runs `make` with a specified build target, either Editor-Platform-Debug or Editor-Platform-Development
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

	conf.log("Changing directory to " .. unrealium.Project.Folder)
	vim.cmd("cd " .. unrealium.Project.Folder)
	local makeCmd = platform.getBuildCommand(unrealium, type)
	conf.log("Running " .. makeCmd)
	vim.cmd(makeCmd)
end

---Generates clang database file (compile_commands)
---@param type string "Project" or "Engine"
function Commands:UGenerateClangDatabase(type)
	conf.log("Generating Clang Database files...")

	if type == "Project" or type == "Engine" then
		local unrealium = self.unrealium
		if not unrealium then
			conf.logError("Something went wrong. Failed to get the unrealium object.")
			return
		end

		local genCmd = platform.getGenClangDatabaseCommand(unrealium, type)
		conf.log("Running " .. genCmd)
		vim.cmd(genCmd)
	else
		conf.logError('Something went wrong. Received "' .. type .. '" as the ClangDatabase type')
		return
	end
end

---Generates project files for the Project & Engine (compile commands & Makefile)
function Commands:UGenerateProjectFiles()
	conf.log("Generating project files...")

	local unrealium = self.unrealium
	if not unrealium then
		conf.logError("Something went wrong.")
		return
	end

	local genCmd = platform.getGenProjFilesCommand(unrealium)
	conf.log("Running " .. genCmd)
	vim.cmd(genCmd)
end

---For automatically locking Engine files, if the Unrealium default isn't overridden
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

-- CLEAN
-- Build.sh {projname}Editor PlatformName Development -Project={ProjPath} -buildscw -clean
-- requires dotnet in PATH

return Commands
