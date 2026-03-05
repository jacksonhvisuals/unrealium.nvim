---@module 'luassert'

_TEST = true
local tUtil = require("tests.test_util")

describe("modules.editor_lock", function()
	it("module loads without error", function()
		local ok, mod = pcall(require, "unrealium.modules.editor_lock")
		assert.is_true(ok)
		assert.equals("editor_lock", mod.name)
		assert.is_function(mod.check_file)
		assert.is_function(mod.setup)
	end)
end)
