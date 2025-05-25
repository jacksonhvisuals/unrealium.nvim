---@module 'luassert'

local Path = require("plenary.path")
local uv = vim.loop

-- Set this so _TEST functions get exposed
_TEST = true
local config = require("unrealium.configuration")

describe("unrealium.configuration", function()
	local tmp_dir = Path:new("./tests/tmp_config"):absolute()

	---@param engineDir? string the engine path to put in the config
	---@return string projectDir directory in which the uproject file lives
	local function createValidTree(engineDir)
		local projectDir = tmp_dir .. "/MyTestProject"
		local unrealiumDir = projectDir .. "/.unrealium"
		local pluginsDir = projectDir .. "/Plugins"
		local subDir = projectDir .. "/Plugins/test"

		vim.fn.mkdir(projectDir, "p")
		vim.fn.mkdir(unrealiumDir, "p")
		vim.fn.mkdir(pluginsDir, "p")
		vim.fn.mkdir(subDir, "p")

		Path:new(projectDir .. "/MyTestProject.uproject"):touch()
		Path:new(projectDir .. "/Plugins/test/MyTestClass.cpp"):touch()

		if engineDir == nil then
			engineDir = tmp_dir .. "/Engine"
		end

		local confFile = Path:new(unrealiumDir .. "/config.json")
		confFile:write('{"EnginePath":"' .. engineDir .. '", "allowEngineModifications":true}', "w")

		return projectDir
	end

	before_each(function()
		vim.fn.mkdir(tmp_dir, "p")
	end)

	after_each(function()
		vim.fn.delete(tmp_dir, "rf")
	end)

	it("returns a Path if a .unrealium/config file exists", function()
		local projDir = createValidTree()
		local confPath = config._getConfigFile(projDir)
		assert.truthy(confPath)

		local content = confPath:read()
		assert.matches("EnginePath", content)
	end)

	it("returns nil if no .unrealium/config file exists", function()
		local confFile = config._getConfigFile(tmp_dir)
		assert.truthy(confFile == nil)
	end)

	it("reads a well-formed config json file", function()
		local enginePath = "Some/Path/Here"
		local projDir = createValidTree(enginePath)
		local confTable = config._readUnrealiumConfig(projDir)
		assert.are.equal(confTable.EnginePath, enginePath)
		assert.are.equal(confTable.allowEngineModifications, true)
	end)

	it("returns the correct platform string", function()
		local platform = config._getPlatformName()
		assert.truthy(platform == "Linux" or platform == "Mac" or platform == "Windows")
	end)

	it("gets script paths correctly", function()
		local scripts = config._getScriptPaths("/Dummy/Unreal", "Linux")
		assert.matches("Build.sh", scripts.GenerateProjectFiles)
		assert.matches("GenerateProjectFiles.sh", scripts.Build)
	end)

	describe("file scanning", function()
		it("finds .uproject in nested dirs", function()
			local projDir = createValidTree()
			local found = config._getDirectoryWithFileExtension(Path:new(projDir .. "/Plugins/test"), "uproject")
			assert.truthy(found)
			assert.matches("MyTestProject.uproject", found.filename)
		end)

		it("returns nil when no .uproject exists", function()
			local projDir = createValidTree()
			local found = config._getDirectoryWithFileExtension(Path:new(projDir .. "/Plugins/test"), "amc")
			assert.falsy(found)
		end)
	end)

	describe("full config", function()
		it("returns complete Unrealium config table", function()
			local UnrealEngineDir = tmp_dir .. "/Engine"
			local UnrealBuildDir = tmp_dir .. "/Engine/Build"
			local UnrealBatchFilesDir = tmp_dir .. "/Engine/Build/BatchFiles"
			vim.fn.mkdir(UnrealEngineDir)
			vim.fn.mkdir(UnrealBuildDir)
			vim.fn.mkdir(UnrealBatchFilesDir)

			local projDir = createValidTree(UnrealEngineDir)
			vim.wait(150)

			local cwd = vim.fn.getcwd()
			vim.loop.chdir(projDir)
			local unrealiumConf = config.get()
			vim.loop.chdir(cwd)

			-- Assert Project fields
			assert.equals("MyTestProject", unrealiumConf.Project.Name)
			assert.matches(projDir, unrealiumConf.Project.Folder)
			assert.matches(projDir .. "/MyTestProject.uproject", unrealiumConf.Project.FullPath)

			-- Assert Engine fields
			assert.equals(UnrealEngineDir, unrealiumConf.Engine.Folder)
			assert.is_true(unrealiumConf.Engine.AllowEngineModifications)
			assert.truthy(unrealiumConf.Engine.Scripts.Build)
			assert.truthy(unrealiumConf.Engine.Scripts.GenerateProjectFiles)
			assert.truthy(unrealiumConf.Engine.Scripts.EditorBase)

			-- Assert Platform
			assert.truthy(
				unrealiumConf.PlatformName == "Linux"
					or unrealiumConf.PlatformName == "Mac"
					or unrealiumConf.PlatformName == "Windows"
			)
		end)
	end)
end)
