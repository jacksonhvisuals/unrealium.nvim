---@module 'luassert'

_TEST = true
local platform = require("unrealium.core.platform")

describe("modules.search", function()
	it("returns exclude globs", function()
		local globs = platform.get_exclude_globs()
		assert.truthy(#globs > 0)
		assert.truthy(vim.tbl_contains(globs, "**/*.po"))
		assert.truthy(vim.tbl_contains(globs, "**/Intermediate/Build/**"))
	end)
end)
