---@module 'luassert'

_TEST = true
local tree = require("unrealium.core.ui.tree")

local function split(rel)
	return vim.split(rel, "/", { plain = true })
end

describe("core.ui.tree", function()
	describe("project_top_filter", function()
		local f = tree._project_top_filter

		it("accepts top-level Source dir", function()
			assert.is_true(f(split("Source"), "Source"))
		end)

		it("accepts files under Source", function()
			assert.is_true(f(split("Source/MyProject/Foo.cpp"), "Foo.cpp"))
		end)

		it("rejects .Target.cs files at depth 2 (hoisted separately)", function()
			assert.is_false(f(split("Source/MyProjectEditor.Target.cs"), "MyProjectEditor.Target.cs"))
		end)

		it("accepts non-Target.cs files at depth 2 under Source", function()
			assert.is_true(f(split("Source/Foo.cs"), "Foo.cs"))
		end)

		it("accepts top-level Config dir", function()
			assert.is_true(f(split("Config"), "Config"))
		end)

		it("accepts files inside Config", function()
			assert.is_true(f(split("Config/DefaultEngine.ini"), "DefaultEngine.ini"))
		end)

		it("accepts top-level .uproject file", function()
			assert.is_true(f(split("MyProject.uproject"), "MyProject.uproject"))
		end)

		it("rejects top-level Content dir", function()
			assert.is_false(f(split("Content"), "Content"))
		end)

		it("rejects top-level Saved dir", function()
			assert.is_false(f(split("Saved"), "Saved"))
		end)

		it("rejects top-level Intermediate dir", function()
			assert.is_false(f(split("Intermediate"), "Intermediate"))
		end)

		it("rejects miscellaneous top-level files", function()
			assert.is_false(f(split("README.md"), "README.md"))
			assert.is_false(f(split(".gitignore"), ".gitignore"))
		end)

		it("rejects empty input", function()
			assert.is_false(f({ "" }, ""))
		end)
	end)

	describe("plugin_internal_filter", function()
		local f = tree._plugin_internal_filter

		it("accepts Source/", function()
			assert.is_true(f({ "Source" }))
			assert.is_true(f({ "Source", "Foo.cpp" }))
		end)

		it("accepts Config/", function()
			assert.is_true(f({ "Config" }))
		end)

		it("accepts Resources/", function()
			assert.is_true(f({ "Resources" }))
			assert.is_true(f({ "Resources", "Icon128.png" }))
		end)

		it("accepts Source/Python/", function()
			assert.is_true(f({ "Source", "Python", "bar.py" }))
		end)

		it("accepts Content/Python/ specifically", function()
			assert.is_true(f({ "Content", "Python" }))
			assert.is_true(f({ "Content", "Python", "foo.py" }))
		end)

		it("accepts top-level *.uplugin", function()
			assert.is_true(f({ "MyPlugin.uplugin" }))
		end)

		it("rejects Content/ generically", function()
			assert.is_false(f({ "Content" }))
			assert.is_false(f({ "Content", "Foo.uasset" }))
		end)

		it("rejects Intermediate/", function()
			assert.is_false(f({ "Intermediate" }))
			assert.is_false(f({ "Intermediate", "Build" }))
		end)

		it("rejects Binaries/", function()
			assert.is_false(f({ "Binaries" }))
		end)

		it("rejects Docs/, Tests/, top-level miscellany", function()
			assert.is_false(f({ "Docs" }))
			assert.is_false(f({ "Tests" }))
			assert.is_false(f({ "README.md" }))
		end)

		it("rejects empty input", function()
			assert.is_false(f({}))
		end)
	end)

	describe("engine_top_filter", function()
		local f = tree._engine_top_filter

		it("accepts Platforms, Plugins, Source, Config, Shaders", function()
			assert.is_true(f({ "Platforms" }))
			assert.is_true(f({ "Plugins" }))
			assert.is_true(f({ "Source" }))
			assert.is_true(f({ "Config" }))
			assert.is_true(f({ "Shaders" }))
		end)

		it("accepts grandchildren of allowed top-level dirs", function()
			assert.is_true(f({ "Source", "Runtime", "Core" }))
			assert.is_true(f({ "Plugins", "Online", "OnlineSubsystem" }))
		end)

		it("rejects Binaries", function()
			assert.is_false(f({ "Binaries" }))
		end)

		it("rejects Build, DerivedDataCache, Saved", function()
			assert.is_false(f({ "Build" }))
			assert.is_false(f({ "DerivedDataCache" }))
			assert.is_false(f({ "Saved" }))
		end)

		it("rejects Documentation, Programs, Extras", function()
			assert.is_false(f({ "Documentation" }))
			assert.is_false(f({ "Programs" }))
			assert.is_false(f({ "Extras" }))
		end)

		it("rejects empty input", function()
			assert.is_false(f({ "" }))
			assert.is_false(f({}))
		end)
	end)

	describe("project_sort", function()
		local f = tree._project_sort

		it("returns 1_ prefix for top-level Plugins", function()
			assert.equals("1_Plugins", f({ "Plugins" }, "Plugins"))
		end)

		it("returns 2_ prefix for top-level Source", function()
			assert.equals("2_Source", f({ "Source" }, "Source"))
		end)

		it("returns 3_ prefix for top-level Config", function()
			assert.equals("3_Config", f({ "Config" }, "Config"))
		end)

		it("returns 4_ prefix for top-level .uproject", function()
			assert.equals("4_MyProject.uproject", f({ "MyProject.uproject" }, "MyProject.uproject"))
		end)

		it("returns nil for grandchildren", function()
			assert.is_nil(f({ "Source", "MyProject" }, "MyProject"))
			assert.is_nil(f({ "Plugins", "MyPlugin", "Source" }, "Source"))
		end)

		it("returns nil for unknown top-level entries", function()
			assert.is_nil(f({ "Saved" }, "Saved"))
			assert.is_nil(f({ "README.md" }, "README.md"))
		end)

		it("orders prefixes lexicographically as Plugins < Source < Config < .uproject < .Target.cs", function()
			-- Hoisted .Target.cs items use "5_<name>" directly.
			local plugins = f({ "Plugins" }, "Plugins")
			local source = f({ "Source" }, "Source")
			local config = f({ "Config" }, "Config")
			local uproject = f({ "Foo.uproject" }, "Foo.uproject")
			local target_sort = "5_FooEditor.Target.cs"

			assert.is_true(plugins < source)
			assert.is_true(source < config)
			assert.is_true(config < uproject)
			assert.is_true(uproject < target_sort)
		end)
	end)
end)
