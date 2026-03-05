---@module 'luassert'

_TEST = true
local log = require("unrealium.core.log")

describe("unrealium.core.log", function()
	before_each(function()
		log.init({ level = "info" })
	end)

	it("initializes with default level", function()
		log.init()
		assert.equals(3, log._get_level()) -- INFO = 3
	end)

	it("sets level from string", function()
		log.set_level("debug")
		assert.equals(4, log._get_level()) -- DEBUG = 4
	end)

	it("sets level from integer", function()
		log.set_level(1)
		assert.equals(1, log._get_level()) -- ERROR = 1
	end)

	it("creates named loggers with all level methods", function()
		local logger = log.get("test")
		assert.is_function(logger.error)
		assert.is_function(logger.warn)
		assert.is_function(logger.info)
		assert.is_function(logger.debug)
		assert.is_function(logger.trace)
	end)

	it("has correct LEVELS constants", function()
		assert.equals(1, log.LEVELS.ERROR)
		assert.equals(2, log.LEVELS.WARN)
		assert.equals(3, log.LEVELS.INFO)
		assert.equals(4, log.LEVELS.DEBUG)
		assert.equals(5, log.LEVELS.TRACE)
	end)

	it("respects custom file path", function()
		local custom = "/tmp/test_unrealium.log"
		log.init({ file = custom })
		assert.equals(custom, log._get_file_path())
	end)
end)
