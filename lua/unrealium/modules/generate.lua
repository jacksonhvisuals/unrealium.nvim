--- :UE generate — Generate project files, clang database, and headers.

local M = {}

local log = require("unrealium.core.log").get("generate")
local platform = require("unrealium.core.platform")
local config = require("unrealium.core.config")
local job = require("unrealium.core.job")
local progress = require("unrealium.core.progress")

M.name = "generate"

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
		},
	},
}

--- Generate project files (Makefile + compile_commands).
function M.project_files()
	local cfg = config.get()
	if not cfg then
		log.error("Config not available")
		return
	end

	log.info("Generating project files...")
	local cmd = platform.gen_project_files_command(cfg)
	log.info("Running: %s", cmd.command)
	vim.cmd(cmd.command)
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

	log.info("Generating clang database for %s...", scope)
	local result = platform.gen_clang_database_command(cfg, scope)

	-- Caller sets makeprg (moved from platform.lua — no side effects in platform)
	vim.cmd("set makeprg=" .. vim.fn.fnameescape(result.makeprg))
	log.info("Running: %s", result.command)
	vim.cmd(result.command)
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

	log.info("Running UnrealHeaderTool...")
	progress.begin("UHT: " .. preset.name)

	job.start({
		cmd = cmd_data.cmd,
		cwd = cmd_data.cwd,
		preset = preset,
		on_complete = function(handle)
			vim.schedule(function()
				local status = handle.exit_code == 0 and "completed" or "failed"
				local msg = string.format("UHT %s (%d errors)", status, #handle.errors)
				local level = handle.exit_code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR
				progress.finish(msg, level)
				log.info(msg)
			end)
		end,
	})
end

return M
