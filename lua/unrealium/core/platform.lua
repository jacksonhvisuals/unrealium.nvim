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

--- Get the run editor command as an argv array for termopen().
---@param config UnrealiumConfig
---@param type string "Debug"|"Development"
---@param extra_args? string[] additional CLI arguments
---@return { cmd: string[] }
function M.run_command(config, type, extra_args)
	local suffix = ""
	if type == "Debug" then
		suffix = "-" .. config.PlatformName .. "-Debug"
	end

	local editor = config.Engine.Scripts.EditorBase .. suffix
	local cmd = { editor, config.Project.FullPath }
	if extra_args then
		for _, arg in ipairs(extra_args) do
			table.insert(cmd, arg)
		end
	end
	return {
		cmd = cmd,
	}
end

--- Assemble a generate-project-files command for async job execution.
---@param config UnrealiumConfig
---@return { cmd: string[], cwd: string }
function M.gen_project_files_cmd(config)
	return {
		cmd = {
			config.Engine.Scripts.GenerateProjectFiles,
			"-projectfiles",
			"-project=" .. config.Project.FullPath,
			"-Makefile",
			"-game",
			"-engine",
			"-progress",
		},
		cwd = config.Project.Folder,
	}
end

--- Assemble a generate-clang-database command for async job execution.
---@param config UnrealiumConfig
---@param scope string "Project"|"Engine"
---@return { cmd: string[], cwd: string }
function M.gen_clang_database_cmd(config, scope)
	local output_dir, target_name

	if scope == "Project" then
		output_dir = config.Engine.Folder
		target_name = "Unreal"
	else
		output_dir = config.Project.Folder
		target_name = config.Project.Name
	end

	local cmd = {
		config.Engine.Scripts.RunUBT,
		"-mode=GenerateClangDatabase",
		target_name .. "Editor",
		config.PlatformName,
		"Development",
		"-OutputDir=" .. output_dir,
	}

	if scope == "Engine" then
		table.insert(cmd, 3, "-project=" .. config.Project.FullPath)
	end

	return {
		cmd = cmd,
		cwd = config.Project.Folder,
	}
end

--- Map platform name to UBT platform identifier.
---@param platform_name string "Linux"|"Mac"|"Windows"
---@return string
function M.ubt_platform(platform_name)
	if platform_name == "Windows" then
		return "Win64"
	end
	return platform_name
end

--- Assemble a UBT build command from config and preset.
---@param config UnrealiumConfig
---@param preset UnrealiumPreset
---@param extra_args? string[] additional CLI arguments (appended after preset args)
---@return { cmd: string[], cwd: string }|nil
function M.ubt_build_command(config, preset, extra_args)
	local run_ubt = config.Engine.Scripts.RunUBT
	if not run_ubt or run_ubt == "" then
		log.error("RunUBT script path not configured")
		return nil
	end

	local cmd = {
		run_ubt,
		preset.target_name,
		preset.platform,
		preset.configuration,
		"-project=" .. config.Project.FullPath,
		"-progress",
	}

	if preset.extra_args then
		for _, arg in ipairs(preset.extra_args) do
			table.insert(cmd, arg)
		end
	end

	if extra_args then
		for _, arg in ipairs(extra_args) do
			table.insert(cmd, arg)
		end
	end

	return {
		cmd = cmd,
		cwd = config.Project.Folder,
	}
end

--- Assemble a UHT (UnrealHeaderTool) command.
---@param config UnrealiumConfig
---@param preset UnrealiumPreset
---@param manifest_path? string path to .uhtmanifest for incremental builds
---@return { cmd: string[], cwd: string }|nil
function M.uht_command(config, preset, manifest_path)
	local run_ubt = config.Engine.Scripts.RunUBT
	if not run_ubt or run_ubt == "" then
		log.error("RunUBT script path not configured")
		return nil
	end

	local cmd = {
		run_ubt,
		preset.target_name,
		preset.platform,
		preset.configuration,
		"-project=" .. config.Project.FullPath,
		"-mode=UnrealHeaderTool",
	}

	if manifest_path then
		table.insert(cmd, "-manifest=" .. manifest_path)
	end

	return {
		cmd = cmd,
		cwd = config.Project.Folder,
	}
end

--- Assemble a UBT static analysis (lint) command.
---@param config UnrealiumConfig
---@param preset UnrealiumPreset
---@param lint_type? string e.g. "PVS-Studio"
---@return { cmd: string[], cwd: string }|nil
function M.ubt_lint_command(config, preset, lint_type)
	local run_ubt = config.Engine.Scripts.RunUBT
	if not run_ubt or run_ubt == "" then
		log.error("RunUBT script path not configured")
		return nil
	end

	local cmd = {
		run_ubt,
		preset.target_name,
		preset.platform,
		preset.configuration,
		"-project=" .. config.Project.FullPath,
		"-StaticAnalyzer",
	}

	if lint_type then
		table.insert(cmd, "-StaticAnalyzerMode=" .. lint_type)
	end

	return {
		cmd = cmd,
		cwd = config.Project.Folder,
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
