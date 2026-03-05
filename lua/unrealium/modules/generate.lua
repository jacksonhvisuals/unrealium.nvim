--- :UE generate — Generate project files and clang database.

local M = {}

local log = require("unrealium.core.log").get("generate")
local platform = require("unrealium.core.platform")
local config = require("unrealium.core.config")

M.name = "generate"

M.commands = {
	generate = {
		desc = "Generate project files or clang database",
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

return M
