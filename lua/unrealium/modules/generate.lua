--- :UE generate — Generate project files, clang database, and headers.

local M = {}

local log = require("unrealium.core.log").get("generate")
local platform = require("unrealium.core.platform")
local config = require("unrealium.core.config")
local job = require("unrealium.core.job")
local progress = require("unrealium.core.progress")
local output = require("unrealium.core.output")

M.name = "generate"

local OUTPUT_BUF_NAME = "generate"

--- Run a generate command with progress, output capture, and quickfix on failure.
---@param label string display name for progress/logging
---@param cmd_data { cmd: string[], cwd: string }
local function run_generate(label, cmd_data)
	if job.is_running() then
		log.error("A job is already running.")
		return
	end

	local term_buf = output.get_or_create_buf(OUTPUT_BUF_NAME)
	output.clear(term_buf, "--- " .. label .. " ---")

	progress.begin(label)

	job.start({
		cmd = cmd_data.cmd,
		cwd = cmd_data.cwd,
		on_line = function(line)
			output.append(term_buf, line)
		end,
		on_complete = function(handle)
			vim.schedule(function()
				local cancelled = handle.exit_code ~= 0 and handle.exit_code ~= nil and #handle.errors == 0
				local level, status
				if handle.exit_code == 0 then
					level = vim.log.levels.INFO
					status = "completed"
				elseif cancelled then
					level = vim.log.levels.WARN
					status = "cancelled"
				else
					level = vim.log.levels.ERROR
					status = "failed"
				end

				local msg = string.format("%s %s (%d errors)", label, status, #handle.errors)
				progress.finish(msg, level)
				log.info(msg)

				if handle.exit_code ~= 0 and not cancelled then
					output.quickfix(handle)
				end

				if handle.exit_code == 0 and #handle.errors == 0 and #handle.warnings == 0 then
					output.delete_buf(OUTPUT_BUF_NAME)
				end
			end)
		end,
	})
end

--- Generate project files (Makefile + compile_commands).
function M.project_files()
	local cfg = config.get()
	if not cfg then
		log.error("Config not available")
		return
	end

	local cmd_data = platform.gen_project_files_cmd(cfg)
	run_generate("Generate project files", cmd_data)
end

--- Generate clang database.
---@param scope? string "Project"|"Engine"
function M.clang_database(scope)
	if scope ~= "Project" and scope ~= "Engine" then
		log.error('Scope must be "Project" or "Engine", got: %s', tostring(scope))
		return
	end

	local cfg = config.get()
	if not cfg then
		log.error("Config not available")
		return
	end

	local cmd_data = platform.gen_clang_database_cmd(cfg, scope)
	run_generate("Generate clang database (" .. scope .. ")", cmd_data)
end

--- Generate headers via UHT (UnrealHeaderTool).
---@param manifest_path? string path to .uhtmanifest for incremental builds
function M.header(manifest_path)
	local cfg = config.get()
	if not cfg then
		log.error("Config not available")
		return
	end

	if job.is_running() then
		log.error("A job is already running.")
		return
	end

	-- Get a preset from the build module
	local build_mod = require("unrealium.modules.build")
	local preset = build_mod.last_preset()
	if not preset then
		local presets = build_mod.get_presets()
		local ubt_plat = platform.ubt_platform(cfg.PlatformName)
		for _, p in ipairs(presets) do
			if p.is_editor and p.configuration == "Development" and p.platform == ubt_plat then
				preset = p
				break
			end
		end
	end

	if not preset then
		log.error("No build preset available. Ensure *.Target.cs files exist in Source/.")
		return
	end

	-- Auto-detect manifest if not provided
	if not manifest_path then
		local intermediate = vim.fs.joinpath(cfg.Project.Folder, "Intermediate")
		local manifests = vim.fs.find(function(name)
			return name:match("%.uhtmanifest$") ~= nil
		end, {
			path = intermediate,
			type = "file",
			limit = 1,
		})
		if #manifests > 0 then
			manifest_path = manifests[1]
			log.debug("Auto-detected manifest: %s", manifest_path)
		end
	end

	local cmd_data = platform.uht_command(cfg, preset, manifest_path)
	if not cmd_data then
		log.error("Failed to assemble UHT command")
		return
	end

	run_generate("UHT: " .. preset.name, cmd_data)
end

M.commands = {
	generate = {
		desc = "Generate project files, clang database, or headers",
		subcommands = {
			["project-files"] = {
				handler = function(_)
					M.project_files()
				end,
				desc = "Generate Makefile and compile_commands.json",
			},
			["clang-database"] = {
				handler = function(opts)
					M.clang_database(opts.args[1])
				end,
				desc = "Regenerate compile_commands.json",
				args = {
					{ name = "scope", complete = { "Project", "Engine" } },
				},
			},
			["header"] = {
				handler = function(opts)
					M.header(opts.args[1])
				end,
				desc = "Run UnrealHeaderTool (UHT) for code generation",
				args = {
					{ name = "manifest_path", complete = {} },
				},
			},
			["log"] = {
				handler = function(_)
					if not output.toggle(OUTPUT_BUF_NAME) then
						log.info("No generate output available")
					end
				end,
				desc = "Toggle generate output log",
			},
		},
	},
}

return M
