local M = {}

local Path = require("plenary.path")
local utils = require("unrealium.utils")

local uv = vim.loop

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

	Path:new(utils.joinPath(projectDir, "MyTestProject.uproject")):touch()
	Path:new(utils.joinPath(subDir, "MyTestClass.cpp")):touch()

	if engineDir == nil then
		engineDir = utils.joinPath(tmp_dir, "Engine")
	end

	local confFile = Path:new(utils.joinPath(projectDir, ".unrealium"))
	confFile:touch()
	confFile:write('{"EnginePath":"' .. engineDir .. '", "allowEngineModifications":false}', "w")

	return projectDir
end

return M
