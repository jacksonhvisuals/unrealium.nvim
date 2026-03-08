local M = {}

local Path = require("plenary.path")

---@param tmp_dir string the tmp path to put everything in
---@param engineDir? string the engine path to put in the config
---@return string projectDir directory in which the uproject file lives
function M.createValidTree(tmp_dir, engineDir)
	local projectDir = tmp_dir .. "/MyTestProject"
	local pluginsDir = projectDir .. "/Plugins"
	local subDir = projectDir .. "/Plugins/test"

	vim.fn.mkdir(projectDir, "p")
	vim.fn.mkdir(pluginsDir, "p")
	vim.fn.mkdir(subDir, "p")

	Path:new(vim.fs.joinpath(projectDir, "MyTestProject.uproject")):touch()
	Path:new(vim.fs.joinpath(subDir, "MyTestClass.cpp")):touch()

	if engineDir == nil then
		engineDir = vim.fs.joinpath(tmp_dir, "Engine")
	end

	local confFile = Path:new(vim.fs.joinpath(projectDir, "unrealium.json"))
	confFile:touch()
	confFile:write('{"EnginePath":"' .. engineDir .. '"}', "w")

	return projectDir
end

--- Create a valid tree with the new .unrealium.json format.
---@param tmp_dir string
---@param engineDir? string
---@return string projectDir
function M.createValidTreeNewFormat(tmp_dir, engineDir)
	local projectDir = tmp_dir .. "/MyTestProject"
	local pluginsDir = projectDir .. "/Plugins"
	local subDir = projectDir .. "/Plugins/test"

	vim.fn.mkdir(projectDir, "p")
	vim.fn.mkdir(pluginsDir, "p")
	vim.fn.mkdir(subDir, "p")

	Path:new(vim.fs.joinpath(projectDir, "MyTestProject.uproject")):touch()
	Path:new(vim.fs.joinpath(subDir, "MyTestClass.cpp")):touch()

	if engineDir == nil then
		engineDir = vim.fs.joinpath(tmp_dir, "Engine")
	end

	local confFile = Path:new(vim.fs.joinpath(projectDir, "unrealium.json"))
	confFile:touch()
	local json =
		string.format('{"engine":{"folder":"%s","allow_modifications":false},"logging":{"level":"info"}}', engineDir)
	confFile:write(json, "w")

	return projectDir
end

--- Create a mock UnrealiumConfig for testing.
---@param overrides? table
---@return UnrealiumConfig
function M.mock_config(overrides)
	local cfg = {
		Project = {
			Folder = "/tmp/test/MyProject",
			FullPath = "/tmp/test/MyProject/MyProject.uproject",
			Name = "MyProject",
		},
		Engine = {
			Folder = "/tmp/test/Engine",
			Scripts = {
				Build = "/tmp/test/Engine/Engine/Build/BatchFiles/Linux/Build.sh",
				GenerateProjectFiles = "/tmp/test/Engine/Engine/Build/BatchFiles/Linux/GenerateProjectFiles.sh",
				RunUBT = "/tmp/test/Engine/Engine/Build/BatchFiles/RunUBT.sh",
				EditorBase = "/tmp/test/Engine/Engine/Binaries/Linux/UnrealEditor",
			},
			AllowEngineModifications = false,
		},
		PlatformName = "Linux",
		settings = {
			logging = { level = "info" },
			ui = { picker = { prefer = { "snacks", "telescope", "fzf_lua", "native" } } },
			build = {
				configurations = { "Development", "DebugGame", "Debug", "Shipping", "Test" },
				presets = {},
				output_mode = "terminal",
				progress = true,
			},
		},
	}

	if overrides then
		cfg = vim.tbl_deep_extend("force", cfg, overrides)
	end

	return cfg
end

return M
