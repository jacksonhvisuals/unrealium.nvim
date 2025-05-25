---@module 'luassert'

local utils = require("unrealium.utils")

describe("autocomplete", function()
	it("returns matching autocomplete suggestions for first argument list", function()
		local suggestions = utils.autocomplete("command ", {
			{ "alpha", "beta", "gamma" },
			{ "one", "two", "three" },
		})
		assert.same({ "alpha", "beta", "gamma" }, suggestions)
	end)

	it("filters second argument list correctly", function()
		local suggestions = utils.autocomplete("command alpha t", {
			{ "alpha", "beta", "gamma" },
			{ "two", "three", "ten", "happy", "silly" },
		})
		assert.same({ "ten", "three", "two" }, suggestions)
	end)

	it("filters fourth argument list correctly", function()
		local suggestions = utils.autocomplete("command alpha two green a", {
			{ "alpha", "beta", "gamma" },
			{ "two", "three", "ten" },
			{ "green", "red", "purple" },
			{ "angry", "happy", "puzzled" },
		})
		assert.same({ "angry" }, suggestions)
	end)

	it("filters partial matches correctly", function()
		local suggestions = utils.autocomplete("command alpha t", {
			{ "alpha", "beta", "gamma" },
			{ "two", "three", "ten", "gormon", "starwars" },
		})
		assert.same({ "ten", "three", "two" }, suggestions)
		local filtered = vim.tbl_filter(function(v)
			return vim.startswith(v, "t")
		end, { "ten", "three", "two" })
		assert.same(filtered, suggestions)
	end)

	it("returns nil when index is out of bounds", function()
		local suggestions = utils.autocomplete("command alpha beta charlie ", {
			{ "a", "to", "the" },
			{ "b", "c", "d" },
		})
		assert.is_nil(suggestions)
	end)

	it("returns empty list if no match is found", function()
		local suggestions = utils.autocomplete("command alpha z", {
			{ "alpha", "beta", "gamma" },
			{ "one", "two", "three" },
		})
		assert.same({}, suggestions)
	end)

	it("handles empty args gracefully", function()
		local suggestions = utils.autocomplete("command", {})
		assert.is_nil(suggestions)
	end)

	it("handles empty input correctly", function()
		local suggestions = utils.autocomplete("", {
			{ "alpha", "beta" },
		})
		assert.is_nil(suggestions)
	end)
end)
