--- Multi-backend picker: Snacks → Telescope → fzf-lua → native (vim.ui.select).

local M = {}

local log = require("unrealium.core.log").get("picker")

--- Check if a module is available without loading it eagerly.
---@param name string
---@return boolean
local function has_module(name)
	local ok = pcall(require, name)
	return ok
end

--- Snacks picker adapter.
local function pick_snacks(opts)
	local snacks = require("snacks")
	local picker_opts = {
		dirs = opts.dirs,
		exclude = opts.exclude,
		search = opts.search,
	}

	if opts.mode == "grep" then
		snacks.picker.grep(picker_opts)
	elseif opts.mode == "files" then
		snacks.picker.files(picker_opts)
	end
end

--- Telescope picker adapter.
local function pick_telescope(opts)
	local builtin = require("telescope.builtin")

	if opts.mode == "grep" then
		builtin.live_grep({
			search_dirs = opts.dirs,
			default_text = opts.search,
		})
	elseif opts.mode == "files" then
		builtin.find_files({
			search_dirs = opts.dirs,
			default_text = opts.search,
		})
	end
end

--- fzf-lua picker adapter.
local function pick_fzf_lua(opts)
	local fzf = require("fzf-lua")

	if opts.mode == "grep" then
		fzf.live_grep({
			search_dirs = opts.dirs,
			query = opts.search,
		})
	elseif opts.mode == "files" then
		fzf.files({
			search_dirs = opts.dirs,
			query = opts.search,
		})
	end
end

--- Native fallback using vim.ui.select (very limited).
local function pick_native(opts)
	if opts.mode == "grep" then
		vim.notify("[unrealium] grep requires a picker plugin (snacks, telescope, or fzf-lua)", vim.log.levels.WARN)
		return
	end

	-- For files mode, at least try to show files in dirs
	local files = {}
	for _, dir in ipairs(opts.dirs or {}) do
		local handle = vim.uv.fs_scandir(dir)
		if handle then
			while true do
				local name, typ = vim.uv.fs_scandir_next(handle)
				if not name then
					break
				end
				if typ == "file" then
					table.insert(files, vim.fs.joinpath(dir, name))
				end
			end
		end
	end

	vim.ui.select(files, { prompt = opts.title or "Select file:" }, function(choice)
		if choice then
			vim.cmd("edit " .. vim.fn.fnameescape(choice))
		end
	end)
end

--- Backend priority order with their checkers and pickers.
local BACKENDS = {
	{ name = "snacks", check = function() return has_module("snacks") end, pick = pick_snacks },
	{ name = "telescope", check = function() return has_module("telescope") end, pick = pick_telescope },
	{ name = "fzf_lua", check = function() return has_module("fzf-lua") end, pick = pick_fzf_lua },
	{ name = "native", check = function() return true end, pick = pick_native },
}

--- Get configured preference order, or use default.
---@return string[]
local function get_prefer_order()
	-- Try to read from config without circular dependency
	local ok, config = pcall(require, "unrealium.core.config")
	if ok then
		local cfg = config.get()
		if cfg and cfg.settings and cfg.settings.ui and cfg.settings.ui.picker then
			return cfg.settings.ui.picker.prefer or { "snacks", "telescope", "fzf_lua", "native" }
		end
	end
	return { "snacks", "telescope", "fzf_lua", "native" }
end

--- Find the best available backend.
---@return { name: string, pick: fun(opts: table) }
local function resolve_backend()
	local order = get_prefer_order()
	for _, preferred in ipairs(order) do
		for _, backend in ipairs(BACKENDS) do
			if backend.name == preferred and backend.check() then
				return backend
			end
		end
	end
	-- Fallback to native
	return BACKENDS[#BACKENDS]
end

--- Pick using the best available backend.
---@param opts { mode: string, dirs?: string[], title?: string, search?: string, exclude?: string[] }
function M.pick(opts)
	local backend = resolve_backend()
	log.debug("Using picker backend: %s", backend.name)
	backend.pick(opts)
end

--- Get the name of the active picker backend.
---@return string
function M.active_backend()
	return resolve_backend().name
end

if _TEST then
	M._resolve_backend = resolve_backend
	M._BACKENDS = BACKENDS
end

return M
