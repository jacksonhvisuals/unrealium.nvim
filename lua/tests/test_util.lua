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

--- Create a plugin directory structure under a project's Plugins/ dir.
---@param project_dir string project root (must exist)
---@param plugin_name string e.g. "MyPlugin"
---@param opts? { subdirs?: string[], content_python?: boolean }
---@return string plugin_dir the created plugin directory path
function M.createPluginTree(project_dir, plugin_name, opts)
	opts = opts or {}
	local plugin_dir = vim.fs.joinpath(project_dir, "Plugins", plugin_name)
	vim.fn.mkdir(plugin_dir, "p")

	-- Create .uplugin file
	Path:new(vim.fs.joinpath(plugin_dir, plugin_name .. ".uplugin")):touch()

	-- Create standard subdirs
	local subdirs = opts.subdirs or { "Source", "Resources", "Config" }
	for _, subdir in ipairs(subdirs) do
		vim.fn.mkdir(vim.fs.joinpath(plugin_dir, subdir), "p")
	end

	-- Optionally create Content/Python
	if opts.content_python then
		vim.fn.mkdir(vim.fs.joinpath(plugin_dir, "Content", "Python"), "p")
		Path:new(vim.fs.joinpath(plugin_dir, "Content", "Python", "init.py")):touch()
	end

	return plugin_dir
end

return M
