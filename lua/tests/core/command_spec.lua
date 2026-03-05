---@module 'luassert'

_TEST = true
local command = require("unrealium.core.command")

describe("unrealium.core.command", function()
	describe("flatten", function()
		it("flattens simple subcommands", function()
			local spec = {
				build = { handler = function() end, desc = "Build" },
				run = { handler = function() end, desc = "Run" },
			}
			local flat = command._flatten(spec)
			assert.truthy(flat["build"])
			assert.truthy(flat["run"])
		end)

		it("flattens nested subcommands", function()
			local spec = {
				generate = {
					desc = "Generate",
					subcommands = {
						["project-files"] = { handler = function() end, desc = "Gen PF" },
						["clang-database"] = { handler = function() end, desc = "Gen CD" },
					},
				},
			}
			local flat = command._flatten(spec)
			assert.truthy(flat["generate project-files"])
			assert.truthy(flat["generate clang-database"])
		end)
	end)

	describe("build_completer", function()
		it("completes top-level subcommands", function()
			local spec = {
				build = { handler = function() end, desc = "Build" },
				run = { handler = function() end, desc = "Run" },
				search = { handler = function() end, desc = "Search" },
			}
			local completer = command._build_completer(spec)
			local results = completer("", "UE ", 3)
			table.sort(results)
			assert.same({ "build", "run", "search" }, results)
		end)

		it("completes with partial input", function()
			local spec = {
				build = { handler = function() end, desc = "Build" },
				run = { handler = function() end, desc = "Run" },
			}
			local completer = command._build_completer(spec)
			local results = completer("b", "UE b", 4)
			assert.same({ "build" }, results)
		end)

		it("completes args for a command", function()
			local spec = {
				build = {
					handler = function() end,
					desc = "Build",
					args = {
						{ name = "type", complete = { "Development", "Debug" } },
					},
				},
			}
			local completer = command._build_completer(spec)
			local results = completer("", "UE build ", 9)
			table.sort(results)
			assert.same({ "Debug", "Development" }, results)
		end)
	end)
end)
