--- Declarative config schema, type/enum validation, unknown-key detection.

local M = {}

local log = require("unrealium.core.log").get("schema")

--- Flat schema mapping dot-paths to type specs.
---@type table<string, SchemaEntry>
local SCHEMA = {
	-- engine (valid in user/project config, not in defaults)
	["engine"] = { type = "table", children = true },
	["engine.folder"] = { type = "string" },
	["engine.allow_modifications"] = { type = "boolean" },

	-- logging
	["logging"] = { type = "table", children = true },
	["logging.level"] = { type = "string", enum = { "error", "warn", "info", "debug", "trace" } },

	-- ui
	["ui"] = { type = "table", children = true },
	["ui.picker"] = { type = "table", children = true },
	["ui.picker.prefer"] = { type = "string[]" },

	-- build
	["build"] = { type = "table", children = true },
	["build.configurations"] = { type = "string[]" },
	["build.presets"] = { type = "table[]" },
	["build.output_mode"] = { type = "string", enum = { "terminal", "quickfix" } },
	["build.progress"] = { type = "boolean" },
	["build.completion_ttl"] = { type = "number" },
	["build.default_preset"] = { type = "string", nilable = true },
	["build.extra_args"] = { type = "string[]" },

	-- run
	["run"] = { type = "table", children = true },
	["run.default_type"] = { type = "string" },
	["run.build_first"] = { type = "boolean" },
	["run.extra_args"] = { type = "string[]" },

	-- search
	["search"] = { type = "table", children = true },
	["search.exclude_patterns"] = { type = "string[]" },

	-- intel
	["intel"] = { type = "table", children = true },
	["intel.server"] = { type = "string", enum = { "clangd", "unrealisense" } },
	["intel.clangd"] = { type = "table", children = true },
	["intel.clangd.enabled"] = { type = "boolean" },
	["intel.clangd.exclusive"] = { type = "boolean" },
	["intel.clangd.cmd"] = { type = "string", nilable = true },
	["intel.clangd.extra_flags"] = { type = "string[]" },
	["intel.clangd.auto_start"] = { type = "boolean" },
	["intel.clangd.generate_config"] = { type = "boolean" },
	["intel.clangd.config_gen"] = { type = "table", children = true },
	["intel.clangd.config_gen.exclude_paths"] = { type = "string[]" },
	["intel.clangd.config_gen.extra_compile_flags"] = { type = "string[]" },
	["intel.unrealisense"] = { type = "table", children = true },
	["intel.unrealisense.cmd"] = { type = "string", nilable = true },
	["intel.unrealisense.engine_path"] = { type = "string", nilable = true },
	["intel.unrealisense.extra_args"] = { type = "string[]" },
	["intel.unrealisense.auto_start"] = { type = "boolean" },
	["intel.unrealisense.generate_config"] = { type = "boolean" },

	-- lint
	["lint"] = { type = "table", children = true },
	["lint.default_analyzer"] = { type = "string", nilable = true },

	-- generate
	["generate"] = { type = "table", children = true },
	["generate.default_clang_scope"] = { type = "string", nilable = true },

	-- editor_lock
	["editor_lock"] = { type = "table", children = true },
	["editor_lock.extra_paths"] = { type = "string[]" },

	-- debug
	["debug"] = { type = "table", children = true },
	["debug.adapter"] = { type = "string" },
	["debug.default_preset"] = { type = "string", nilable = true },
	["debug.extra_init_commands"] = { type = "string[]" },
	["debug.extra_args"] = { type = "string[]" },
}

--- Type checker functions.
local type_checkers = {
	["boolean"] = function(v)
		return type(v) == "boolean"
	end,
	["string"] = function(v)
		return type(v) == "string"
	end,
	["number"] = function(v)
		return type(v) == "number"
	end,
	["table"] = function(v)
		return type(v) == "table"
	end,
	["string[]"] = function(v)
		if type(v) ~= "table" then
			return false
		end
		for k, item in pairs(v) do
			if type(k) ~= "number" then
				return false
			end
			if type(item) ~= "string" then
				return false
			end
		end
		return true
	end,
	["table[]"] = function(v)
		if type(v) ~= "table" then
			return false
		end
		for k, item in pairs(v) do
			if type(k) ~= "number" then
				return false
			end
			if type(item) ~= "table" then
				return false
			end
		end
		return true
	end,
}

--- Compute Levenshtein distance between two strings.
---@param s string
---@param t string
---@return integer
local function levenshtein(s, t)
	local m, n = #s, #t
	local d = {}
	for i = 0, m do
		d[i] = { [0] = i }
	end
	for j = 0, n do
		d[0][j] = j
	end
	for i = 1, m do
		for j = 1, n do
			local cost = s:sub(i, i) == t:sub(j, j) and 0 or 1
			d[i][j] = math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
		end
	end
	return d[m][n]
end

--- Suggest a similar key name if one exists within distance 2.
---@param key string
---@param candidates string[]
---@return string|nil
local function suggest_similar(key, candidates)
	local best_dist = 3
	local best_match = nil
	for _, cand in ipairs(candidates) do
		local dist = levenshtein(key, cand)
		if dist < best_dist then
			best_dist = dist
			best_match = cand
		end
	end
	return best_match
end

--- Resolve a dot-path to a value in a nested table.
---@param tbl table
---@param path string
---@return any
local function resolve_path(tbl, path)
	local parts = vim.split(path, ".", { plain = true })
	local current = tbl
	for _, part in ipairs(parts) do
		if type(current) ~= "table" then
			return nil
		end
		current = current[part]
	end
	return current
end

--- Set a value at a dot-path in a nested table.
---@param tbl table
---@param path string
---@param value any
local function set_path(tbl, path, value)
	local parts = vim.split(path, ".", { plain = true })
	local current = tbl
	for i = 1, #parts - 1 do
		if current[parts[i]] == nil then
			current[parts[i]] = {}
		end
		current = current[parts[i]]
	end
	current[parts[#parts]] = value
end

--- Validate a single value against a schema entry.
---@param path string
---@param value any
---@param entry SchemaEntry
---@return string|nil error message or nil if valid
local function validate_value(path, value, entry)
	if value == nil then
		return nil
	end

	-- Container entries only need to be tables
	if entry.children then
		if type(value) ~= "table" then
			return string.format("'%s': expected table, got %s", path, type(value))
		end
		return nil
	end

	local checker = type_checkers[entry.type]
	if not checker then
		return nil
	end

	if not checker(value) then
		return string.format("'%s': expected %s, got %s", path, entry.type, type(value))
	end

	if entry.enum then
		local valid = false
		for _, ev in ipairs(entry.enum) do
			if value == ev then
				valid = true
				break
			end
		end
		if not valid then
			return string.format(
				"'%s': invalid value '%s', expected one of: %s",
				path,
				tostring(value),
				table.concat(entry.enum, ", ")
			)
		end
	end

	return nil
end

--- Validate all settings against the schema.
---@param settings table merged settings
---@param defaults table default settings for fallback
---@return string[] warnings
---@return table sanitized settings
local function validate_settings(settings, defaults)
	local warnings = {}
	local sanitized = vim.deepcopy(settings)

	for path, entry in pairs(SCHEMA) do
		local value = resolve_path(settings, path)
		local err = validate_value(path, value, entry)
		if err then
			table.insert(warnings, err)
			local default_val = resolve_path(defaults, path)
			if default_val ~= nil then
				set_path(sanitized, path, vim.deepcopy(default_val))
			else
				-- Remove invalid value if the path exists in the table
				local parts = vim.split(path, ".", { plain = true })
				local parent = sanitized
				for i = 1, #parts - 1 do
					if type(parent) ~= "table" or parent[parts[i]] == nil then
						parent = nil
						break
					end
					parent = parent[parts[i]]
				end
				if parent and type(parent) == "table" then
					parent[parts[#parts]] = nil
				end
			end
		end
	end

	return warnings, sanitized
end

--- Collect known child key names at a given schema prefix.
---@param prefix string
---@return table<string, boolean>
local function known_children(prefix)
	local children = {}
	local prefix_dot = prefix == "" and "" or (prefix .. ".")
	for path in pairs(SCHEMA) do
		if prefix == "" then
			local first = path:match("^([^.]+)")
			if first then
				children[first] = true
			end
		else
			if vim.startswith(path, prefix_dot) then
				local rest = path:sub(#prefix_dot + 1)
				local next_key = rest:match("^([^.]+)")
				if next_key then
					children[next_key] = true
				end
			end
		end
	end
	return children
end

--- Recursively detect unknown keys in a table.
---@param tbl table
---@param skip_keys? table<string, boolean> keys to skip at top level
---@param prefix? string current dot-path prefix
---@return string[] warnings
local function detect_unknown_keys(tbl, skip_keys, prefix)
	prefix = prefix or ""
	local warnings = {}
	local children = known_children(prefix)

	for key, value in pairs(tbl) do
		local str_key = tostring(key)
		local full_path = prefix == "" and str_key or (prefix .. "." .. str_key)

		if skip_keys and skip_keys[key] and prefix == "" then
			goto continue
		end

		if not children[str_key] then
			local candidates = {}
			for c in pairs(children) do
				table.insert(candidates, c)
			end
			local suggestion = suggest_similar(str_key, candidates)
			local msg = string.format("unknown key '%s'", full_path)
			if suggestion then
				local suggested_path = prefix == "" and suggestion or (prefix .. "." .. suggestion)
				msg = msg .. string.format(" (did you mean '%s'?)", suggested_path)
			end
			table.insert(warnings, msg)
		elseif type(value) == "table" then
			local entry = SCHEMA[full_path]
			if entry and entry.children then
				local sub_warnings = detect_unknown_keys(value, nil, full_path)
				vim.list_extend(warnings, sub_warnings)
			end
		end

		::continue::
	end

	return warnings
end

--- Validate a single key-value pair (for config.set()).
---@param key string dot-separated path
---@param value any
---@return string|nil warning message
function M.validate_key(key, value)
	local entry = SCHEMA[key]
	if not entry then
		return nil
	end
	return validate_value(key, value, entry)
end

--- Top-level validation entry point.
--- Validates merged settings, detects unknown keys in user overrides and project config.
--- Logs all warnings. Returns sanitized settings.
---@param settings table merged settings
---@param user_overrides table user-provided overrides from setup()
---@param project_config table raw project config file contents
---@param ext_namespaces string[] registered extension namespace names
---@param defaults table default settings for fallback
---@return table sanitized settings
function M.validate_and_sanitize(settings, user_overrides, project_config, ext_namespaces, defaults)
	local all_warnings = {}

	-- Validate merged settings
	local type_warnings, sanitized = validate_settings(settings, defaults)
	vim.list_extend(all_warnings, type_warnings)

	-- Build skip-keys set for unknown-key detection
	local skip = {}
	for _, ns in ipairs(ext_namespaces or {}) do
		skip[ns] = true
	end

	-- Detect unknown keys in user overrides
	if user_overrides and next(user_overrides) then
		local uw = detect_unknown_keys(user_overrides, skip, "")
		for _, w in ipairs(uw) do
			table.insert(all_warnings, "setup(): " .. w)
		end
	end

	-- Detect unknown keys in project config
	if project_config and next(project_config) then
		local pw = detect_unknown_keys(project_config, skip, "")
		for _, w in ipairs(pw) do
			table.insert(all_warnings, "project config: " .. w)
		end
	end

	-- Log all warnings
	for _, warning in ipairs(all_warnings) do
		log.warn("config: %s", warning)
	end

	return sanitized
end

if _TEST then
	M._validate_value = validate_value
	M._validate_settings = validate_settings
	M._detect_unknown_keys = detect_unknown_keys
	M._suggest_similar = suggest_similar
	M._resolve_path = resolve_path
	M._known_children = known_children
	M._SCHEMA = SCHEMA
end

return M
