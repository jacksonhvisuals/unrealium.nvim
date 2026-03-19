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

	describe("should_show_plugin_item", function()
		it("allows Source/ and descendants", function()
			assert.is_true(tree_ui._should_show_plugin_item("Source"))
			assert.is_true(tree_ui._should_show_plugin_item("Source/Foo.cpp"))
			assert.is_true(tree_ui._should_show_plugin_item("Source/Private/Bar.h"))
		end)

		it("allows Resources/ and descendants", function()
			assert.is_true(tree_ui._should_show_plugin_item("Resources"))
			assert.is_true(tree_ui._should_show_plugin_item("Resources/Icon.png"))
		end)

		it("allows Config/ and descendants", function()
			assert.is_true(tree_ui._should_show_plugin_item("Config"))
			assert.is_true(tree_ui._should_show_plugin_item("Config/Default.ini"))
		end)

		it("allows .uplugin files at root", function()
			assert.is_true(tree_ui._should_show_plugin_item("MyPlugin.uplugin"))
		end)

		it("allows Content/Python and descendants", function()
			assert.is_true(tree_ui._should_show_plugin_item("Content/Python"))
			assert.is_true(tree_ui._should_show_plugin_item("Content/Python/init.py"))
			assert.is_true(tree_ui._should_show_plugin_item("Content/Python/scripts/run.py"))
		end)

		it("blocks other Content subdirs", function()
			assert.is_false(tree_ui._should_show_plugin_item("Content/Blueprints"))
			assert.is_false(tree_ui._should_show_plugin_item("Content/Textures/foo.png"))
		end)

		it("blocks Intermediate and Binaries", function()
			assert.is_false(tree_ui._should_show_plugin_item("Intermediate"))
			assert.is_false(tree_ui._should_show_plugin_item("Intermediate/Build/foo.o"))
			assert.is_false(tree_ui._should_show_plugin_item("Binaries"))
			assert.is_false(tree_ui._should_show_plugin_item("Binaries/Linux/libfoo.so"))
		end)

		it("blocks .uplugin in subdirectories", function()
			assert.is_false(tree_ui._should_show_plugin_item("SubDir/MyPlugin.uplugin"))
		end)

		it("blocks empty string", function()
			assert.is_false(tree_ui._should_show_plugin_item(""))
		end)
	end)
end)
