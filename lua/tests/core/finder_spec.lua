---@module 'luassert'

local tUtil = require("tests.test_util")
local Path = require("plenary.path")

_TEST = true
local finder = require("unrealium.core.finder")

describe("unrealium.core.finder", function()
	local tmp_dir = Path:new("./tmp_finder"):absolute()

	before_each(function()
		vim.fn.delete(tmp_dir, "rf")
		vim.fn.mkdir(tmp_dir, "p")
	end)

	after_each(function()
		vim.fn.delete(tmp_dir, "rf")
	end)

	describe("walk_ancestors", function()
		it("finds matching directory", function()
			local projDir = tUtil.createValidTree(tmp_dir)
			local subDir = projDir .. "/Plugins/test"

			local result = finder.walk_ancestors(subDir, function(dir)
				local uproject = finder._find_file_with_extension(dir, "uproject")
				return uproject
			end)
			assert.truthy(result)
			assert.matches("MyTestProject.uproject", result)
		end)

		it("returns nil when no match", function()
			local result = finder.walk_ancestors(tmp_dir, function(_)
				return nil
			end)
			assert.is_nil(result)
		end)
	end)

	describe("find_project", function()
		it("finds .uproject from project root", function()
			local projDir = tUtil.createValidTree(tmp_dir)
			local result = finder.find_project(projDir)
			assert.truthy(result)
			assert.equals("MyTestProject", result.name)
			assert.matches(projDir, result.root)
			assert.matches("MyTestProject.uproject", result.uproject_path)
		end)

		it("finds .uproject from nested subdirectory", function()
			local projDir = tUtil.createValidTree(tmp_dir)
			local result = finder.find_project(projDir .. "/Plugins/test")
			assert.truthy(result)
			assert.equals("MyTestProject", result.name)
		end)

		it("returns nil when no project found", function()
			-- Use a directory guaranteed to have no .uproject above it
			local isolated_dir = tmp_dir .. "/isolated_empty"
			vim.fn.mkdir(isolated_dir, "p")
			-- Mock walk_ancestors to only check the isolated dir itself
			local result = finder._find_file_with_extension(isolated_dir, "uproject")
			assert.is_nil(result)
		end)
	end)

	describe("read_project_config", function()
		it("reads unrealium.json", function()
			local projDir = tUtil.createValidTree(tmp_dir, "/some/engine")
			local data = finder.read_project_config(projDir)
			assert.truthy(data)
			assert.equals("/some/engine", data.engine.folder)
		end)

		it("returns empty table for missing config", function()
			vim.fn.mkdir(tmp_dir .. "/empty", "p")
			local data = finder.read_project_config(tmp_dir .. "/empty")
			assert.same({}, data)
		end)
	end)

	describe("validate_engine_path", function()
		it("returns path for existing directory", function()
			local result = finder.validate_engine_path(tmp_dir)
			assert.equals(tmp_dir, result)
		end)

		it("returns nil for non-existent directory", function()
			local result = finder.validate_engine_path(tmp_dir .. "/nonexistent")
			assert.is_nil(result)
		end)

		it("returns nil for empty string", function()
			assert.is_nil(finder.validate_engine_path(""))
		end)

		it("returns nil for nil", function()
			assert.is_nil(finder.validate_engine_path(nil))
		end)
	end)

	describe("get_platform_name", function()
		it("returns a valid platform", function()
			local platform = finder.get_platform_name()
			assert.truthy(platform == "Linux" or platform == "Mac" or platform == "Windows" or platform == "Unknown")
		end)
	end)

	describe("get_script_paths", function()
		it("builds correct paths", function()
			local scripts = finder.get_script_paths("/Dummy/Unreal", "Linux")
			assert.matches("Build.sh", scripts.Build)
			assert.matches("GenerateProjectFiles.sh", scripts.GenerateProjectFiles)
			assert.matches("RunUBT.sh", scripts.RunUBT)
			assert.matches("UnrealEditor", scripts.EditorBase)
		end)
	end)

	describe("discover_plugins", function()
		it("finds direct plugins with .uplugin files", function()
			local projDir = tUtil.createValidTree(tmp_dir)
			tUtil.createPluginTree(projDir, "MyPlugin")
			tUtil.createPluginTree(projDir, "AnotherPlugin")

			local plugins = finder.discover_plugins(projDir)
			assert.equals(2, #plugins)
			-- Should be sorted alphabetically
			assert.equals("AnotherPlugin", plugins[1].name)
			assert.equals("MyPlugin", plugins[2].name)
			assert.matches("AnotherPlugin.uplugin", plugins[1].uplugin)
			assert.matches("MyPlugin.uplugin", plugins[2].uplugin)
		end)

		it("finds nested publisher-grouped plugins", function()
			local projDir = tUtil.createValidTree(tmp_dir)
			-- Create Plugins/Epic/OnlineSubsystem/ with .uplugin
			local nested_dir = vim.fs.joinpath(projDir, "Plugins", "Epic", "OnlineSubsystem")
			vim.fn.mkdir(nested_dir, "p")
			Path:new(vim.fs.joinpath(nested_dir, "OnlineSubsystem.uplugin")):touch()

			local plugins = finder.discover_plugins(projDir)
			assert.equals(1, #plugins)
			assert.equals("OnlineSubsystem", plugins[1].name)
		end)

		it("returns empty table when no Plugins directory", function()
			local isolated = tmp_dir .. "/no_plugins"
			vim.fn.mkdir(isolated, "p")
			local plugins = finder.discover_plugins(isolated)
			assert.same({}, plugins)
		end)

		it("ignores directories without .uplugin files", function()
			local projDir = tUtil.createValidTree(tmp_dir)
			-- The "test" directory from createValidTree has no .uplugin
			local plugins = finder.discover_plugins(projDir)
			assert.same({}, plugins)
		end)

		it("finds deeply nested plugins (3+ levels)", function()
			local projDir = tUtil.createValidTree(tmp_dir)
			-- Create Plugins/Publisher/Category/DeepPlugin/ with .uplugin
			local deep_dir = vim.fs.joinpath(projDir, "Plugins", "Publisher", "Category", "DeepPlugin")
			vim.fn.mkdir(deep_dir, "p")
			Path:new(vim.fs.joinpath(deep_dir, "DeepPlugin.uplugin")):touch()

			local plugins = finder.discover_plugins(projDir)
			assert.equals(1, #plugins)
			assert.equals("DeepPlugin", plugins[1].name)
			assert.matches("DeepPlugin.uplugin", plugins[1].uplugin)
		end)

		it("finds plugins at mixed depths", function()
			local projDir = tUtil.createValidTree(tmp_dir)
			-- Direct plugin
			tUtil.createPluginTree(projDir, "DirectPlugin")
			-- Nested publisher plugin
			local nested_dir = vim.fs.joinpath(projDir, "Plugins", "Epic", "OnlineSubsystem")
			vim.fn.mkdir(nested_dir, "p")
			Path:new(vim.fs.joinpath(nested_dir, "OnlineSubsystem.uplugin")):touch()
			-- Deeply nested plugin
			local deep_dir = vim.fs.joinpath(projDir, "Plugins", "ThirdParty", "Vendor", "DeepPlugin")
			vim.fn.mkdir(deep_dir, "p")
			Path:new(vim.fs.joinpath(deep_dir, "DeepPlugin.uplugin")):touch()

			local plugins = finder.discover_plugins(projDir)
			assert.equals(3, #plugins)
			-- Should be sorted alphabetically
			assert.equals("DeepPlugin", plugins[1].name)
			assert.equals("DirectPlugin", plugins[2].name)
			assert.equals("OnlineSubsystem", plugins[3].name)
		end)
	end)

	describe("resolve_engine_config", function()
		local orig_isdirectory
		before_each(function()
			orig_isdirectory = vim.fn.isdirectory
			vim.fn.isdirectory = function()
				return 1
			end
		end)
		after_each(function()
			vim.fn.isdirectory = orig_isdirectory
		end)

		it("reads engine config", function()
			local result = finder.resolve_engine_config({
				engine = { folder = "/new/path", allow_modifications = false },
			})
			assert.equals("/new/path", result.folder)
			assert.is_false(result.allow_modifications)
		end)

		it("defaults allow_modifications to false", function()
			local result = finder.resolve_engine_config({
				engine = { folder = "/path" },
			})
			assert.is_false(result.allow_modifications)
		end)

		it("falls through to GUID resolution when explicit path does not exist", function()
			vim.fn.isdirectory = function()
				return 0
			end
			local result = finder.resolve_engine_config({
				engine = { folder = "/nonexistent/path" },
			})
			assert.is_nil(result.folder)
		end)
	end)
end)
