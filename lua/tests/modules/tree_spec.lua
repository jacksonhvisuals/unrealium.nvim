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
		assert.truthy(vim.tbl_contains(completions, "symbols"))
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

	describe("flatten_symbols", function()
		it("flattens class with children into correct depth chain", function()
			local symbols = {
				{
					name = "AMyActor",
					kind = "Class",
					pos = { 1, 0 },
					end_pos = { 10, 0 },
					children = {
						{ name = "Health", kind = "Field", pos = { 3, 0 }, end_pos = { 3, 15 }, children = {} },
						{ name = "BeginPlay", kind = "Method", pos = { 5, 0 }, end_pos = { 5, 20 }, children = {} },
					},
				},
			}
			local items = tree_ui._flatten_symbols(symbols, 1)
			assert.equals(3, #items)
			-- Parent
			assert.equals("AMyActor", items[1].name)
			assert.equals(0, items[1].depth)
			assert.is_nil(items[1].parent)
			assert.is_true(items[1].tree)
			assert.is_true(items[1].last) -- only top-level item
			-- First child
			assert.equals("Health", items[2].name)
			assert.equals(1, items[2].depth)
			assert.equals(items[1], items[2].parent)
			assert.is_false(items[2].last)
			-- Second child (last)
			assert.equals("BeginPlay", items[3].name)
			assert.equals(1, items[3].depth)
			assert.equals(items[1], items[3].parent)
			assert.is_true(items[3].last)
		end)

		it("flattens nested hierarchy with correct depths", function()
			local symbols = {
				{
					name = "Outer",
					kind = "Class",
					pos = { 1, 0 },
					end_pos = { 20, 0 },
					children = {
						{
							name = "Inner",
							kind = "Class",
							pos = { 3, 0 },
							end_pos = { 8, 0 },
							children = {
								{ name = "x", kind = "Field", pos = { 5, 0 }, end_pos = { 5, 5 }, children = {} },
							},
						},
						{ name = "DoWork", kind = "Method", pos = { 10, 0 }, end_pos = { 10, 15 }, children = {} },
					},
				},
			}
			local items = tree_ui._flatten_symbols(symbols, 1)
			assert.equals(4, #items)
			assert.equals(0, items[1].depth) -- Outer
			assert.equals(1, items[2].depth) -- Inner
			assert.equals(items[1], items[2].parent)
			assert.equals(2, items[3].depth) -- x
			assert.equals(items[2], items[3].parent)
			assert.equals(1, items[4].depth) -- DoWork
			assert.equals(items[1], items[4].parent)
			assert.is_true(items[4].last)
		end)

		it("returns empty table for empty input", function()
			local items = tree_ui._flatten_symbols({}, 1)
			assert.same({}, items)
		end)

		it("assigns file for source_file symbols, buf otherwise", function()
			local symbols = {
				{
					name = "RemoteFunc",
					kind = "Function",
					pos = { 1, 0 },
					end_pos = { 3, 0 },
					source_file = "/path/to/file.cpp",
					children = {},
				},
				{
					name = "LocalFunc",
					kind = "Function",
					pos = { 5, 0 },
					end_pos = { 7, 0 },
					children = {},
				},
			}
			local items = tree_ui._flatten_symbols(symbols, 42)
			assert.equals(2, #items)
			assert.equals("/path/to/file.cpp", items[1].file)
			assert.is_nil(items[1].buf)
			assert.equals(42, items[2].buf)
			assert.is_nil(items[2].file)
		end)

		it("marks only last sibling with last=true", function()
			local symbols = {
				{ name = "A", kind = "Class", pos = { 1, 0 }, end_pos = { 2, 0 }, children = {} },
				{ name = "B", kind = "Class", pos = { 3, 0 }, end_pos = { 4, 0 }, children = {} },
				{ name = "C", kind = "Class", pos = { 5, 0 }, end_pos = { 6, 0 }, children = {} },
			}
			local items = tree_ui._flatten_symbols(symbols, 1)
			assert.equals(3, #items)
			assert.is_false(items[1].last)
			assert.is_false(items[2].last)
			assert.is_true(items[3].last)
		end)
	end)
end)
