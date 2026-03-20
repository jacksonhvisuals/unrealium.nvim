--- UE_LOG / UE_LOGFMT snippet support with smart category discovery.

local M = {}

local log = require("unrealium.core.log").get("snippets")

M.name = "snippets"

--- Directory scan cache: dir_path → { categories = {cat → count}, mtime = number }
---@type table<string, { categories: table<string, integer>, mtime: number }>
local _dir_cache = {}

--- Extract UE_LOG/UE_LOGFMT category names from lines.
---@param lines string[]
---@return table<string, integer> categories map of category → count
local function scan_lines(lines)
	local categories = {}
	for _, line in ipairs(lines) do
		for cat in line:gmatch("UE_LOG[A-Z]*%((%w+),") do
			categories[cat] = (categories[cat] or 0) + 1
		end
	end
	return categories
end

--- Scan a buffer for UE_LOG categories.
---@param bufnr integer
---@return table<string, integer>
local function scan_buffer(bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	return scan_lines(lines)
end

--- Scan sibling C++ files in the same directory for categories.
---@param filepath string
---@return table<string, integer>
local function scan_directory(filepath)
	local dir = vim.fn.fnamemodify(filepath, ":h")
	local cached = _dir_cache[dir]
	if cached then
		return cached.categories
	end

	local categories = {}
	local handle = vim.uv.fs_scandir(dir)
	if not handle then
		return categories
	end

	while true do
		local name, typ = vim.uv.fs_scandir_next(handle)
		if not name then
			break
		end
		if typ == "file" and name:match("%.[ch]pp$") or name:match("%.h$") or name:match("%.cpp$") then
			local full = vim.fs.joinpath(dir, name)
			-- Skip the current file (it's scanned live via scan_buffer)
			if full ~= filepath then
				local ok, lines = pcall(vim.fn.readfile, full)
				if ok then
					for cat, count in pairs(scan_lines(lines)) do
						categories[cat] = (categories[cat] or 0) + count
					end
				end
			end
		end
	end

	_dir_cache[dir] = { categories = categories, mtime = os.time() }
	return categories
end

--- Merge two frequency tables.
---@param a table<string, integer>
---@param b table<string, integer>
---@return table<string, integer>
local function merge_frequencies(a, b)
	local result = {}
	for cat, count in pairs(a) do
		result[cat] = (result[cat] or 0) + count
	end
	for cat, count in pairs(b) do
		result[cat] = (result[cat] or 0) + count
	end
	return result
end

--- Rank categories by frequency descending, alphabetical tiebreak.
---@param freq table<string, integer>
---@return string[]
local function rank_categories(freq)
	local items = {}
	for cat, count in pairs(freq) do
		table.insert(items, { cat = cat, count = count })
	end
	table.sort(items, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.cat < b.cat
	end)
	local result = {}
	for _, item in ipairs(items) do
		table.insert(result, item.cat)
	end
	return result
end

--- Get ranked categories for a buffer, with LogTemp fallback.
---@param bufnr integer
---@return string[]
function M.get_categories(bufnr)
	local buf_cats = scan_buffer(bufnr)
	local filepath = vim.api.nvim_buf_get_name(bufnr)
	local dir_cats = {}
	if filepath ~= "" then
		dir_cats = scan_directory(filepath)
	end
	local merged = merge_frequencies(buf_cats, dir_cats)
	local ranked = rank_categories(merged)

	if #ranked == 0 then
		return { "LogTemp" }
	end

	-- Ensure LogTemp is present (append at end if missing)
	local has_logtemp = false
	for _, cat in ipairs(ranked) do
		if cat == "LogTemp" then
			has_logtemp = true
			break
		end
	end
	if not has_logtemp then
		table.insert(ranked, "LogTemp")
	end

	return ranked
end

--- Build LSP snippet string for UE_LOG.
---@param categories string[]
---@return string
function M.build_uelog_snippet(categories)
	local cat_choices = table.concat(categories, ",")
	return string.format(
		'UE_LOG(${1|%s|}, ${2|Log,Warning,Error,Display,Verbose,VeryVerbose,Fatal|}, TEXT("${3}"));$0',
		cat_choices
	)
end

--- Build LSP snippet string for UE_LOGFMT.
---@param categories string[]
---@return string
function M.build_uelogfmt_snippet(categories)
	local cat_choices = table.concat(categories, ",")
	return string.format(
		'UE_LOGFMT(${1|%s|}, ${2|Log,Warning,Error,Display,Verbose,VeryVerbose,Fatal|}, "${3}");$0',
		cat_choices
	)
end

--- Module API cache: dir_path → MODULE_API string
---@type table<string, string>
local _api_cache = {}

--- Walk up from filepath looking for *.Build.cs to derive MODULE_API.
---@param filepath string
---@return string|nil
local function find_build_cs(filepath)
	local dir = vim.fn.fnamemodify(filepath, ":h")
	while dir and dir ~= "" do
		local cached = _api_cache[dir]
		if cached then
			return cached
		end

		local handle = vim.uv.fs_scandir(dir)
		if handle then
			while true do
				local name, typ = vim.uv.fs_scandir_next(handle)
				if not name then
					break
				end
				if typ == "file" and name:match("%.Build%.cs$") then
					local module_name = name:match("^(.+)%.Build%.cs$")
					if module_name then
						local api = module_name:upper() .. "_API"
						_api_cache[dir] = api
						return api
					end
				end
			end
		end

		local parent = vim.fn.fnamemodify(dir, ":h")
		if parent == dir then
			break
		end
		dir = parent
	end
	return nil
end

--- Scan sibling C++ files for SOMETHING_API patterns in class declarations.
---@param filepath string
---@return string|nil
local function scan_api_macros(filepath)
	local dir = vim.fn.fnamemodify(filepath, ":h")
	local freq = {}

	local handle = vim.uv.fs_scandir(dir)
	if not handle then
		return nil
	end

	while true do
		local name, typ = vim.uv.fs_scandir_next(handle)
		if not name then
			break
		end
		if typ == "file" and (name:match("%.[ch]pp$") or name:match("%.h$") or name:match("%.cpp$")) then
			local full = vim.fs.joinpath(dir, name)
			if full ~= filepath then
				local ok, lines = pcall(vim.fn.readfile, full)
				if ok then
					for _, line in ipairs(lines) do
						for api in line:gmatch("(%w+_API)") do
							freq[api] = (freq[api] or 0) + 1
						end
					end
				end
			end
		end
	end

	-- Return the most frequent match
	local best, best_count = nil, 0
	for api, count in pairs(freq) do
		if count > best_count then
			best = api
			best_count = count
		end
	end
	return best
end

--- Get the MODULE_API macro for the current buffer's module.
---@param bufnr integer
---@return string
function M.get_module_api(bufnr)
	local filepath = vim.api.nvim_buf_get_name(bufnr)
	if filepath == "" then
		return "PROJECTNAME_API"
	end
	return find_build_cs(filepath) or scan_api_macros(filepath) or "PROJECTNAME_API"
end

--- Build LSP snippet string for UENUM.
---@return string
function M.build_uenum_snippet()
	return table.concat({
		"UENUM(BlueprintType)",
		"enum class ${1:EName} : ${2|uint8,uint16,uint32,int32|}",
		"{",
		'\t${3:Name1} UMETA(DisplayName="${4:DisplayName}")',
		"};$0",
	}, "\n")
end

--- Build LSP snippet string for USTRUCT.
---@return string
function M.build_ustruct_snippet()
	return table.concat({
		"USTRUCT(BlueprintType)",
		"struct ${1:FMyStruct}",
		"{",
		"\tGENERATED_BODY()",
		"",
		"\tUPROPERTY(EditAnywhere, BlueprintReadWrite, Category=${2:Default})",
		"\t${3:float MyProperty};",
		"};$0",
	}, "\n")
end

--- Build LSP snippet string for UCLASS.
---@param module_api string
---@return string
function M.build_uclass_snippet(module_api)
	return table.concat({
		"UCLASS()",
		"class "
			.. module_api
			.. " ${1:AMyActor} : public ${2|AActor,ACharacter,APawn,AGameModeBase,APlayerController,UObject,UActorComponent,USceneComponent|}",
		"{",
		"\tGENERATED_BODY()",
		"public:",
		"\t$1();",
		"protected:",
		"private:",
		"};$0",
	}, "\n")
end

--- Build LSP snippet string for UINTERFACE.
---@param module_api string
---@return string
function M.build_uinterface_snippet(module_api)
	return table.concat({
		"UINTERFACE()",
		"class " .. module_api .. " U${1:MyInterface} : public UInterface",
		"{",
		"\tGENERATED_BODY()",
		"};",
		"",
		"class " .. module_api .. " I$1",
		"{",
		"\tGENERATED_BODY()",
		"public:",
		"\t$2",
		"};$0",
	}, "\n")
end

--- Build LSP snippet string for Cast<>.
---@return string
function M.build_ucast_snippet()
	return "${1:AMyClass}* ${2:CastResult} = Cast<$1>(${3:SourceActor});$0"
end

--- Build LSP snippet string for UFUNCTION.
---@return string
function M.build_ufunction_snippet()
	return "UFUNCTION(${1|BlueprintCallable,BlueprintPure,BlueprintNativeEvent,BlueprintImplementableEvent,Server,Client,NetMulticast|})$0"
end

--- Build LSP snippet string for UPROPERTY.
---@return string
function M.build_uproperty_snippet()
	return 'UPROPERTY(${1|EditAnywhere,VisibleAnywhere,EditDefaultsOnly,EditInstanceOnly,VisibleDefaultsOnly,VisibleInstanceOnly|}, ${2|BlueprintReadWrite,BlueprintReadOnly|}, Category="${3:Default}")$0'
end

--- Invalidate directory cache for a given file's directory.
---@param filepath string
local function invalidate_cache(filepath)
	local dir = vim.fn.fnamemodify(filepath, ":h")
	_dir_cache[dir] = nil
	_api_cache[dir] = nil
end

--- Module setup: register autocmd to invalidate cache on save.
---@param cfg UnrealiumConfig
function M.setup(cfg)
	if cfg.settings and cfg.settings.snippets and cfg.settings.snippets.enabled == false then
		log.debug("Snippets module disabled by config")
		return
	end

	vim.api.nvim_create_autocmd("BufWritePost", {
		group = vim.api.nvim_create_augroup("UnrealiumSnippets", { clear = true }),
		pattern = { "*.cpp", "*.h", "*.hpp" },
		callback = function()
			local filepath = vim.api.nvim_buf_get_name(0)
			invalidate_cache(filepath)
		end,
	})

	log.debug("Snippets module initialized")
end

if _TEST then
	M._scan_lines = scan_lines
	M._scan_buffer = scan_buffer
	M._scan_directory = scan_directory
	M._merge_frequencies = merge_frequencies
	M._rank_categories = rank_categories
	M._invalidate_cache = invalidate_cache
	M._dir_cache = _dir_cache
	M._api_cache = _api_cache
	M._find_build_cs = find_build_cs
	M._scan_api_macros = scan_api_macros
end

return M
