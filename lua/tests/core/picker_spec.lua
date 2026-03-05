---@module 'luassert'

_TEST = true
local picker = require("unrealium.core.ui.picker")

describe("unrealium.core.ui.picker", function()
	it("has a resolve_backend function", function()
		local backend = picker._resolve_backend()
		assert.truthy(backend)
		assert.truthy(backend.name)
		assert.is_function(backend.pick)
	end)

	it("always has native as fallback", function()
		local backends = picker._BACKENDS
		local last = backends[#backends]
		assert.equals("native", last.name)
		assert.is_true(last.check())
	end)

	it("reports active backend name", function()
		local name = picker.active_backend()
		assert.is_string(name)
	end)
end)
