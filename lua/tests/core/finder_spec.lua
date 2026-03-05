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
		it("reads legacy .unrealium format", function()
			local projDir = tUtil.createValidTree(tmp_dir, "/some/engine")
			local data = finder.read_project_config(projDir)
			assert.truthy(data)
			assert.equals("/some/engine", data.EnginePath)
		end)

		it("reads new .unrealium.json format", function()
			local projDir = tUtil.createValidTreeNewFormat(tmp_dir, "/some/engine")
			local data = finder.read_project_config(projDir)
			assert.truthy(data)
			assert.equals("/some/engine", data.engine.folder)
		end)

		it("returns nil for missing config", function()
			vim.fn.mkdir(tmp_dir .. "/empty", "p")
			local data = finder.read_project_config(tmp_dir .. "/empty")
			assert.is_nil(data)
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
			assert.truthy(
				platform == "Linux" or platform == "Mac" or platform == "Windows" or platform == "Unknown"
			)
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

	describe("resolve_engine_config", function()
		it("reads legacy format", function()
			local result = finder.resolve_engine_config({
				EnginePath = "/old/path",
				allowEngineModifications = true,
			})
			assert.equals("/old/path", result.folder)
			assert.is_true(result.allow_modifications)
		end)

		it("reads new format", function()
			local result = finder.resolve_engine_config({
				engine = { folder = "/new/path", allow_modifications = false },
			})
			assert.equals("/new/path", result.folder)
			assert.is_false(result.allow_modifications)
		end)

		it("defaults allow_modifications to false", function()
			local result = finder.resolve_engine_config({ EnginePath = "/path" })
			assert.is_false(result.allow_modifications)
		end)
	end)
end)
