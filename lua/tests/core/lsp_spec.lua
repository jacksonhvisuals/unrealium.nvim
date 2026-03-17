---@module 'luassert'

_TEST = true

describe("core.lsp", function()
	local lsp = require("unrealium.core.lsp")

	before_each(function()
		lsp._reset()
	end)

	describe("get_backend", function()
		it("resolves clangd backend", function()
			local backend = lsp._get_backend("clangd")
			assert.truthy(backend)
			assert.equals("unrealium-clangd", backend.client_name())
		end)

		it("resolves unrealisense backend", function()
			local backend = lsp._get_backend("unrealisense")
			assert.truthy(backend)
			assert.equals("unrealium-unrealisense", backend.client_name())
		end)

		it("returns nil for unknown backend", function()
			local backend = lsp._get_backend("unknown")
			assert.is_nil(backend)
		end)
	end)

	describe("status", function()
		it("reports not running initially", function()
			local status = lsp.status()
			assert.is_false(status.running)
			assert.is_nil(status.client_id)
			assert.is_nil(status.server)
		end)
	end)

	describe("is_running", function()
		it("returns false when no client started", function()
			assert.is_false(lsp.is_running())
		end)
	end)
end)
