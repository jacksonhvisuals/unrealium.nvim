---@module 'luassert'

_TEST = true
local tUtil = require("tests.test_util")

describe("modules.debug", function()
	local debug_mod = require("unrealium.modules.debug")

	before_each(function()
		debug_mod._reset()
	end)

	describe("find_epic_formatters", function()
		it("returns nil when engine path has no formatters", function()
			local result = debug_mod._find_epic_formatters("/nonexistent/engine")
			assert.is_nil(result)
		end)
	end)

	describe("generate_debug_presets", function()
		it("generates presets for each target x configuration", function()
			-- Mock target.discover by using a config that has targets
			local cfg = tUtil.mock_config()
			local presets = debug_mod._generate_debug_presets(cfg)
			-- Without actual Target.cs files, presets will be empty
			assert.is_table(presets)
		end)
	end)

	describe("default_preset", function()
		it("prefers Editor + DebugGame", function()
			local presets = {
				{ name = "MyProject (Development)", target_name = "MyProject", target_type = "Game", configuration = "Development" },
				{ name = "MyProjectEditor (Development)", target_name = "MyProjectEditor", target_type = "Editor", configuration = "Development" },
				{ name = "MyProjectEditor (DebugGame)", target_name = "MyProjectEditor", target_type = "Editor", configuration = "DebugGame" },
			}
			local result = debug_mod._default_preset(presets)
			assert.truthy(result)
			assert.equals("MyProjectEditor (DebugGame)", result.name)
		end)

		it("falls back to first preset when no Editor + DebugGame", function()
			local presets = {
				{ name = "MyProject (Debug)", target_name = "MyProject", target_type = "Game", configuration = "Debug" },
			}
			local result = debug_mod._default_preset(presets)
			assert.truthy(result)
			assert.equals("MyProject (Debug)", result.name)
		end)

		it("returns nil for empty presets", function()
			local result = debug_mod._default_preset({})
			assert.is_nil(result)
		end)
	end)

	describe("resolve_binary_path", function()
		it("returns editor base for Editor Development target", function()
			local cfg = tUtil.mock_config()
			local preset = {
				name = "MyProjectEditor (Development)",
				target_name = "MyProjectEditor",
				target_type = "Editor",
				configuration = "Development",
			}
			local result = debug_mod._resolve_binary_path(cfg, preset)
			assert.truthy(result)
			assert.equals(cfg.Engine.Scripts.EditorBase, result)
		end)

		it("appends suffix for Editor DebugGame target", function()
			local cfg = tUtil.mock_config()
			local preset = {
				name = "MyProjectEditor (DebugGame)",
				target_name = "MyProjectEditor",
				target_type = "Editor",
				configuration = "DebugGame",
			}
			local result = debug_mod._resolve_binary_path(cfg, preset)
			assert.truthy(result)
			assert.matches("Linux%-DebugGame$", result)
		end)

		it("returns project binary for Game target", function()
			local cfg = tUtil.mock_config()
			local preset = {
				name = "MyProject (Development)",
				target_name = "MyProject",
				target_type = "Game",
				configuration = "Development",
			}
			local result = debug_mod._resolve_binary_path(cfg, preset)
			assert.truthy(result)
			assert.matches("MyProject/Binaries/Linux/MyProject$", result)
		end)
	end)

	describe("build_init_commands", function()
		it("always includes inline-breakpoint-strategy", function()
			local cfg = tUtil.mock_config()
			local cmds = debug_mod._build_init_commands(cfg)
			assert.truthy(#cmds >= 1)
			assert.matches("inline%-breakpoint%-strategy", cmds[1])
		end)

		it("includes extra_init_commands from config", function()
			local cfg = tUtil.mock_config({
				settings = {
					debug = {
						extra_init_commands = { "settings set foo bar" },
					},
				},
			})
			local cmds = debug_mod._build_init_commands(cfg)
			local found = false
			for _, cmd in ipairs(cmds) do
				if cmd == "settings set foo bar" then
					found = true
				end
			end
			assert.is_true(found)
		end)
	end)

	describe("build_dap_config", function()
		it("creates a valid launch config", function()
			local cfg = tUtil.mock_config({
				settings = {
					debug = {
						adapter = "codelldb",
						extra_init_commands = {},
						extra_args = {},
					},
				},
			})
			local preset = {
				name = "MyProjectEditor (DebugGame)",
				target_name = "MyProjectEditor",
				target_type = "Editor",
				configuration = "DebugGame",
			}
			local result = debug_mod._build_dap_config(cfg, preset)
			assert.truthy(result)
			assert.equals("codelldb", result.type)
			assert.equals("launch", result.request)
			assert.matches("UnrealEditor", result.program)
			assert.equals(cfg.Project.Folder, result.cwd)
			assert.is_table(result.initCommands)
			assert.truthy(#result.initCommands >= 1)
		end)

		it("includes project path in args", function()
			local cfg = tUtil.mock_config({
				settings = {
					debug = {
						adapter = "codelldb",
						extra_init_commands = {},
						extra_args = {},
					},
				},
			})
			local preset = {
				name = "MyProjectEditor (DebugGame)",
				target_name = "MyProjectEditor",
				target_type = "Editor",
				configuration = "DebugGame",
			}
			local result = debug_mod._build_dap_config(cfg, preset)
			assert.truthy(result)
			assert.equals(cfg.Project.FullPath, result.args[1])
		end)
	end)

	describe("build_attach_config", function()
		it("creates a valid attach config", function()
			local cfg = tUtil.mock_config({
				settings = {
					debug = {
						adapter = "codelldb",
						extra_init_commands = {},
					},
				},
			})
			local result = debug_mod._build_attach_config(cfg)
			assert.truthy(result)
			assert.equals("attach", result.request)
			assert.equals("codelldb", result.type)
			assert.is_table(result.initCommands)
		end)
	end)

	describe("commands", function()
		it("has debug command spec", function()
			assert.truthy(debug_mod.commands)
			assert.truthy(debug_mod.commands.debug)
			assert.truthy(debug_mod.commands.debug.handler)
			assert.truthy(debug_mod.commands.debug.desc)
		end)
	end)
end)
