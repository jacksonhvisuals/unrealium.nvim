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
end)
