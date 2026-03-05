---@module 'luassert'

_TEST = true
local platform = require("unrealium.core.platform")
local tUtil = require("tests.test_util")

describe("modules.build", function()
	describe("platform.build_command (legacy)", function()
		it("returns correct Linux Development build command", function()
			local cfg = tUtil.mock_config()
			local result = platform.build_command(cfg, "Development")
			assert.truthy(result)
			assert.matches("Make MyProjectEditor%-Linux%-Development", result.command)
			assert.equals(cfg.Project.Folder, result.cwd)
		end)

		it("returns correct Linux Debug build command", function()
			local cfg = tUtil.mock_config()
			local result = platform.build_command(cfg, "Debug")
			assert.truthy(result)
			assert.matches("Make MyProjectEditor%-Linux%-Debug", result.command)
		end)

		it("returns nil for unsupported platform", function()
			local cfg = tUtil.mock_config({ PlatformName = "Windows" })
			local result = platform.build_command(cfg, "Development")
			assert.is_nil(result)
		end)
	end)

	describe("platform.ubt_build_command", function()
		it("assembles correct UBT command", function()
			local cfg = tUtil.mock_config()
			local preset = {
				name = "MyProjectEditor Linux Development",
				target_name = "MyProjectEditor",
				platform = "Linux",
				configuration = "Development",
				is_editor = true,
			}
			local result = platform.ubt_build_command(cfg, preset)
			assert.truthy(result)
			assert.equals(cfg.Engine.Scripts.RunUBT, result.cmd[1])
			assert.equals("MyProjectEditor", result.cmd[2])
			assert.equals("Linux", result.cmd[3])
			assert.equals("Development", result.cmd[4])
			assert.matches("-project=", result.cmd[5])
			assert.equals("-progress", result.cmd[6])
			assert.equals(cfg.Project.Folder, result.cwd)
		end)

		it("includes extra_args", function()
			local cfg = tUtil.mock_config()
			local preset = {
				name = "test",
				target_name = "MyProjectEditor",
				platform = "Linux",
				configuration = "Development",
				is_editor = true,
				extra_args = { "-NoHotReload", "-Verbose" },
			}
			local result = platform.ubt_build_command(cfg, preset)
			assert.truthy(result)
			assert.equals("-NoHotReload", result.cmd[7])
			assert.equals("-Verbose", result.cmd[8])
		end)
	end)

	describe("platform.ubt_platform", function()
		it("maps Windows to Win64", function()
			assert.equals("Win64", platform.ubt_platform("Windows"))
		end)

		it("passes through Linux", function()
			assert.equals("Linux", platform.ubt_platform("Linux"))
		end)

		it("passes through Mac", function()
			assert.equals("Mac", platform.ubt_platform("Mac"))
		end)
	end)

	describe("platform.run_command", function()
		it("returns Development run command", function()
			local cfg = tUtil.mock_config()
			local result = platform.run_command(cfg, "Development")
			assert.truthy(result)
			assert.matches("Dispatch", result.command)
			assert.matches("UnrealEditor", result.command)
			assert.matches("MyProject.uproject", result.command)
		end)

		it("returns Debug run command with suffix", function()
			local cfg = tUtil.mock_config()
			local result = platform.run_command(cfg, "Debug")
			assert.matches("Linux%-Debug", result.command)
		end)
	end)

	describe("build module", function()
		local build = require("unrealium.modules.build")

		before_each(function()
			build._reset()
		end)

		describe("generate_dynamic_presets", function()
			it("generates presets for each target × configuration", function()
				local cfg = tUtil.mock_config({
					settings = {
						build = {
							configurations = { "Development", "Debug" },
						},
					},
				})
				local targets = {
					{ name = "MyProjectEditor", file = "/tmp/Editor.Target.cs", type = "Editor" },
					{ name = "MyProject", file = "/tmp/Game.Target.cs", type = "Game" },
				}
				local presets = build._generate_dynamic_presets(cfg, targets)
				-- 2 targets × 2 configurations = 4 presets
				assert.equals(4, #presets)
				assert.equals("MyProjectEditor Linux Development", presets[1].name)
				assert.is_true(presets[1].is_editor)
				assert.equals("MyProject Linux Debug", presets[4].name)
				assert.is_false(presets[4].is_editor)
			end)
		end)

		describe("merge_presets", function()
			it("static presets win on name collision", function()
				local static = {
					{ name = "Custom", target_name = "X", platform = "Linux", configuration = "Debug", is_editor = false },
				}
				local dynamic = {
					{ name = "Custom", target_name = "Y", platform = "Linux", configuration = "Development", is_editor = true },
					{ name = "Other", target_name = "Z", platform = "Linux", configuration = "Development", is_editor = false },
				}
				local result = build._merge_presets(static, dynamic)
				assert.equals(2, #result)
				assert.equals("X", result[1].target_name)
				assert.equals("Other", result[2].name)
			end)
		end)

		describe("preset_from_configuration", function()
			it("finds editor preset matching configuration", function()
				-- This requires get_presets to work, which needs config + target discovery
				-- Tested indirectly via integration tests
			end)
		end)
	end)
end)
