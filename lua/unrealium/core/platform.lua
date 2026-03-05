--- Platform-specific command assembly. All functions return pure data — no side effects.

local M = {}

local log = require("unrealium.core.log").get("platform")

--- Build the make target name for a given config and build type.
---@param config UnrealiumConfig
---@param type string "Debug"|"Development"
---@return string|nil target_name
local function get_build_target(config, type)
	if config.PlatformName == "Linux" then
		local suffix = "Editor-" .. config.PlatformName
		if type == "Debug" then
			suffix = suffix .. "-Debug"
		else
			suffix = suffix .. "-Development"
		end
		return config.Project.Name .. suffix
	elseif config.PlatformName == "Mac" then
		return config.Project.Name .. "Editor"
	else
		log.error("Platform %s is not yet supported for building", config.PlatformName)
		return nil
	end
end

--- Get the full build command.
---@param config UnrealiumConfig
---@param type string "Debug"|"Development"
---@return { command: string, cwd: string }|nil
function M.build_command(config, type)
	local target = get_build_target(config, type)
	if not target then
		return nil
	end

	local command
	if config.PlatformName == "Linux" then
		command = "Make " .. target
	elseif config.PlatformName == "Mac" then
		command = "Dispatch xcodebuild " .. target
	end

	return {
		command = command,
		cwd = config.Project.Folder,
	}
end

--- Get the run editor command.
---@param config UnrealiumConfig
---@param type string "Debug"|"Development"
---@return { command: string }
function M.run_command(config, type)
	local suffix = ""
	if type == "Debug" then
		suffix = "-" .. config.PlatformName .. "-Debug"
	end

	local editor = config.Engine.Scripts.EditorBase .. suffix
	return {
		command = "Dispatch " .. editor .. " " .. config.Project.FullPath,
	}
end

--- Get the generate project files command.
---@param config UnrealiumConfig
---@return { command: string }
function M.gen_project_files_command(config)
	local args = {
		"Dispatch",
		config.Engine.Scripts.GenerateProjectFiles,
		"-projectfiles",
		'-project="' .. config.Project.FullPath .. '"',
		"-Makefile",
		"-game",
		"-engine",
		"-progress",
	}
	return {
		command = table.concat(args, " "),
	}
end

--- Get the generate clang database command.
--- Returns pure data — caller is responsible for setting makeprg.
---@param config UnrealiumConfig
---@param gen_mode string "Project"|"Engine"
---@return { command: string, makeprg: string }
function M.gen_clang_database_command(config, gen_mode)
	local output_dir, target_name, project_arg

	if gen_mode == "Project" then
		output_dir = config.Engine.Folder
		target_name = "Unreal"
		project_arg = ""
	else
		output_dir = config.Project.Folder
		target_name = config.Project.Name
		project_arg = "-project='" .. config.Project.FullPath .. "'"
	end

	local args = {
		"Dispatch",
		config.Engine.Scripts.RunUBT,
		"-mode=GenerateClangDatabase",
		project_arg,
		target_name .. "Editor " .. config.PlatformName .. " Development",
		"-OutputDir='" .. output_dir .. "'",
	}

	return {
		command = table.concat(args, " "),
		makeprg = config.Engine.Scripts.RunUBT,
	}
end

--- Returns glob patterns to exclude in searches.
---@return string[]
function M.get_exclude_globs()
	return { "**/*.po", "**/*.archive", "**/*.gen.h", "**/Intermediate/Build/**" }
end

if _TEST then
	M._get_build_target = get_build_target
end

return M
