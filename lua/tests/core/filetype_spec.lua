---@module 'luassert'

_TEST = true

local filetype = require("unrealium.core.filetype")

describe("unrealium.core.filetype", function()
	before_each(function()
		filetype.setup()
	end)

	describe("detection", function()
		it("uses json for Unreal descriptor files", function()
			assert.equals("json", vim.filetype.match({ filename = "Game.uproject" }))
			assert.equals("json", vim.filetype.match({ filename = "Plugins/MyPlugin/MyPlugin.uplugin" }))
		end)

		it("uses cs for Unreal Build.cs files", function()
			assert.equals("cs", vim.filetype.match({ filename = "Source/MyModule/MyModule.Build.cs" }))
		end)
	end)

	describe("indentation", function()
		local bufs = {}

		after_each(function()
			for _, bufnr in ipairs(bufs) do
				if vim.api.nvim_buf_is_valid(bufnr) then
					vim.api.nvim_buf_delete(bufnr, { force = true })
				end
			end
			bufs = {}
		end)

		local function new_named_buffer(name)
			local bufnr = vim.api.nvim_create_buf(false, true)
			table.insert(bufs, bufnr)
			vim.api.nvim_buf_set_name(bufnr, name)
			return bufnr
		end

		it("applies four-wide hard tabs to .uproject files", function()
			local bufnr = new_named_buffer("/tmp/Game.uproject")

			filetype.apply(bufnr)

			assert.is_false(vim.bo[bufnr].expandtab)
			assert.equals(4, vim.bo[bufnr].tabstop)
			assert.equals(4, vim.bo[bufnr].shiftwidth)
			assert.equals(4, vim.bo[bufnr].softtabstop)
		end)

		it("applies four-wide hard tabs to .uplugin files", function()
			local bufnr = new_named_buffer("/tmp/MyPlugin.uplugin")

			filetype.apply(bufnr)

			assert.is_false(vim.bo[bufnr].expandtab)
			assert.equals(4, vim.bo[bufnr].tabstop)
			assert.equals(4, vim.bo[bufnr].shiftwidth)
			assert.equals(4, vim.bo[bufnr].softtabstop)
		end)

		it("applies four-wide hard tabs to Build.cs files", function()
			local bufnr = new_named_buffer("/tmp/MyModule.Build.cs")

			filetype.apply(bufnr)

			assert.is_false(vim.bo[bufnr].expandtab)
			assert.equals(4, vim.bo[bufnr].tabstop)
			assert.equals(4, vim.bo[bufnr].shiftwidth)
			assert.equals(4, vim.bo[bufnr].softtabstop)
		end)

		it("leaves ordinary json buffers alone", function()
			local bufnr = new_named_buffer("/tmp/package.json")
			vim.bo[bufnr].expandtab = true
			vim.bo[bufnr].tabstop = 2
			vim.bo[bufnr].shiftwidth = 2
			vim.bo[bufnr].softtabstop = 2

			filetype.apply(bufnr)

			assert.is_true(vim.bo[bufnr].expandtab)
			assert.equals(2, vim.bo[bufnr].tabstop)
			assert.equals(2, vim.bo[bufnr].shiftwidth)
			assert.equals(2, vim.bo[bufnr].softtabstop)
		end)
	end)
end)
