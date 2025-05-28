---@module 'luassert'

_TEST = true
local plat = require("unrealium.platform")

describe("platform command abstraction", function()
	it("gets args for generating project files", function()
		local testPath = "/My/Test/Path"
		local testConfig = { Project = { FullPath = testPath } }
		local testResults = {
			"-projectfiles",
			'-project="' .. testConfig.Project.FullPath .. '"',
			"-VSCode",
			"-game",
			"-engine",
			"-progress",
		}

		local args = plat.getGenProjFilesArgs(testConfig)
		assert.same(testResults, args)
	end)

	it("gets args for building", function()
		local testConfig = { PlatformName = "Linux", Project = { Name = "MyTestProject" } }
		local buildCmd = plat.getBuildArgs(testConfig, "Debug")
		local buildResults = { "MyTestProjectEditor-Linux-Debug" }
		assert.same(buildResults, buildCmd)
	end)
end)
