---@module 'luassert'

_TEST = true
local event = require("unrealium.core.event")

describe("unrealium.core.event", function()
	before_each(function()
		event.clear()
	end)

	it("calls listener on emit", function()
		local received = nil
		event.on("test.event", function(data)
			received = data
		end)

		event.emit("test.event", { foo = "bar" })
		assert.same({ foo = "bar" }, received)
	end)

	it("supports multiple listeners", function()
		local count = 0
		event.on("test.multi", function()
			count = count + 1
		end)
		event.on("test.multi", function()
			count = count + 1
		end)

		event.emit("test.multi")
		assert.equals(2, count)
	end)

	it("returns unsubscribe function", function()
		local count = 0
		local unsub = event.on("test.unsub", function()
			count = count + 1
		end)

		event.emit("test.unsub")
		assert.equals(1, count)

		unsub()
		event.emit("test.unsub")
		assert.equals(1, count)
	end)

	it("clears all listeners", function()
		event.on("test.clear", function() end)
		event.clear()
		assert.same({}, event._listeners())
	end)

	it("has expected event constants", function()
		assert.equals("unrealium.plugin_ready", event.PLUGIN_READY)
		assert.equals("unrealium.build_start", event.BUILD_START)
		assert.equals("unrealium.build_end", event.BUILD_END)
		assert.equals("unrealium.config_loaded", event.CONFIG_LOADED)
	end)
end)
