---@module 'luassert'

_TEST = true

describe("modules.tree", function()
	local tree

	before_each(function()
		package.loaded["unrealium.modules.tree"] = nil
		tree = require("unrealium.modules.tree")
	end)

	it("module loads without error", function()
		assert.equals("tree", tree.name)
		assert.is_table(tree.commands)
		assert.is_table(tree.commands.tree)
		assert.is_function(tree.execute)
	end)

	it("has correct command spec", function()
		local cmd = tree.commands.tree
		assert.is_function(cmd.handler)
		assert.equals("Multi-root file tree (Project + Engine)", cmd.desc)
		assert.is_table(cmd.args)
		assert.equals("action", cmd.args[1].name)

		local completions = cmd.args[1].complete
		assert.is_table(completions)
		assert.truthy(vim.tbl_contains(completions, "toggle"))
		assert.truthy(vim.tbl_contains(completions, "open"))
		assert.truthy(vim.tbl_contains(completions, "close"))
		assert.truthy(vim.tbl_contains(completions, "focus"))
		assert.truthy(vim.tbl_contains(completions, "reveal"))
		assert.truthy(vim.tbl_contains(completions, "solution"))
		assert.truthy(vim.tbl_contains(completions, "files"))
	end)

	describe("resolve_engine_root", function()
		it("returns nil when no engine folder", function()
			local cfg = {
				Engine = { Folder = nil },
				settings = { tree = { engine_dirs = { "Source" } } },
			}
			local result = tree._resolve_engine_root(cfg)
			assert.is_nil(result)
		end)

		it("returns nil when engine folder does not exist", function()
			local cfg = {
				Engine = { Folder = "/nonexistent/path/to/engine" },
				settings = { tree = { engine_dirs = { "Source" } } },
			}
			local result = tree._resolve_engine_root(cfg)
			assert.is_nil(result)
		end)
	end)
end)

describe("core.ui.tree", function()
	local tree_ui

	before_each(function()
		package.loaded["unrealium.core.ui.tree"] = nil
		tree_ui = require("unrealium.core.ui.tree")
	end)

	it("module loads without error", function()
		assert.is_function(tree_ui.execute)
		assert.is_function(tree_ui.open_fallback)
	end)

	it("has_snacks returns boolean", function()
		local result = tree_ui._has_snacks()
		assert.is_boolean(result)
	end)
end)
