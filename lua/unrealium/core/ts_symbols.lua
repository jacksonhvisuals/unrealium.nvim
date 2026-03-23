--- Treesitter-based C++ symbol extraction with UE macro detection.

local M = {}

--- UE macros we recognize.
local UE_MACROS = {
	UCLASS = true,
	USTRUCT = true,
	UENUM = true,
	UFUNCTION = true,
	UPROPERTY = true,
}

--- Get the text of a treesitter node.
---@param node userdata
---@param bufnr integer
---@return string
local function node_text(node, bufnr)
	return vim.treesitter.get_node_text(node, bufnr)
end

--- Get 1-indexed start/end positions from a treesitter node.
---@param node userdata
---@return integer[] pos {line_1indexed, col_0indexed}
---@return integer[] end_pos {line_1indexed, col_0indexed}
local function get_pos(node)
	local sr, sc = node:start()
	local er, ec = node:end_()
	return { sr + 1, sc }, { er + 1, ec }
end

--- Detect a UE macro in previous siblings of a node.
--- Scans up to 3 previous named siblings. Checks text before stop conditions
--- so that UE macros parsed as declarations are still detected.
---@param node userdata
---@param bufnr integer
---@return string|nil macro name (e.g. "UCLASS", "UFUNCTION")
local function detect_ue_macro(node, bufnr)
	local sibling = node:prev_named_sibling()
	local count = 0
	while sibling and count < 3 do
		-- Check text first (before stop conditions) so macros parsed as
		-- declarations or other node types are still detected
		local text = node_text(sibling, bufnr)
		local macro_name = text:match("^(U[A-Z]+)%s*%(")
		if macro_name and UE_MACROS[macro_name] then
			return macro_name
		end
		-- Stop at real code constructs
		local stype = sibling:type()
		if
			stype == "field_declaration"
			or stype == "function_definition"
			or stype == "access_specifier"
			or stype == "class_specifier"
			or stype == "struct_specifier"
			or stype == "enum_specifier"
			or stype == "declaration"
			or stype == "namespace_definition"
		then
			break
		end
		sibling = sibling:prev_named_sibling()
		count = count + 1
	end
	return nil
end

--- Extract the class/struct name from a specifier node.
--- Handles the MYPROJECT_API pattern by skipping _API suffixed identifiers.
---@param node userdata class_specifier or struct_specifier or enum_specifier
---@param bufnr integer
---@return string|nil
local function extract_class_name(node, bufnr)
	local candidates = {}
	for child in node:iter_children() do
		local ct = child:type()
		-- Stop at body or base_class_clause to avoid picking up base class names
		if ct == "field_declaration_list" or ct == "base_class_clause" or ct == "enumerator_list" then
			break
		end
		if ct == "type_identifier" then
			table.insert(candidates, node_text(child, bufnr))
		end
	end
	-- Prefer names that don't look like API export macros
	for _, name in ipairs(candidates) do
		if not name:match("_API$") then
			return name
		end
	end
	return candidates[1]
end

--- Extract function name and optional class qualifier from a node with a declarator field.
---@param node userdata function_definition, declaration, or field_declaration
---@param bufnr integer
---@return string|nil name
---@return string|nil class_name (for qualified Class::Method)
local function extract_function_info(node, bufnr)
	local declarators = node:field("declarator")
	local declarator = declarators and declarators[1]
	if not declarator then
		return nil, nil
	end

	if declarator:type() == "function_declarator" then
		local name_nodes = declarator:field("declarator")
		local name_node = name_nodes and name_nodes[1]
		if not name_node then
			return nil, nil
		end

		local ntype = name_node:type()

		if ntype == "qualified_identifier" then
			local parts = {}
			for child in name_node:iter_children() do
				local ct = child:type()
				if
					ct == "identifier"
					or ct == "destructor_name"
					or ct == "type_identifier"
					or ct == "namespace_identifier"
				then
					table.insert(parts, node_text(child, bufnr))
				end
			end
			if #parts >= 2 then
				return parts[#parts], parts[#parts - 1]
			elseif #parts == 1 then
				return parts[1], nil
			end
			return nil, nil
		end

		if
			ntype == "identifier"
			or ntype == "field_identifier"
			or ntype == "destructor_name"
			or ntype == "operator_name"
		then
			return node_text(name_node, bufnr), nil
		end
	end

	return nil, nil
end

--- Extract field or method info from a field_declaration.
---@param node userdata field_declaration node
---@param bufnr integer
---@return string|nil name
---@return boolean is_method
local function extract_field_info(node, bufnr)
	local declarators = node:field("declarator")
	local declarator = declarators and declarators[1]
	if not declarator then
		return nil, false
	end

	if declarator:type() == "function_declarator" then
		local name_nodes = declarator:field("declarator")
		local name_node = name_nodes and name_nodes[1]
		if name_node then
			return node_text(name_node, bufnr), true
		end
		return nil, true
	end

	if declarator:type() == "field_identifier" or declarator:type() == "identifier" then
		return node_text(declarator, bufnr), false
	end

	return nil, false
end

--- Extract enum members from an enumerator_list node.
---@param list_node userdata enumerator_list node
---@param bufnr integer
---@return UnrealiumSymbol[]
local function extract_enumerators(list_node, bufnr)
	local members = {}
	for child in list_node:iter_children() do
		if child:type() == "enumerator" then
			local name_nodes = child:field("name")
			local name_node = name_nodes and name_nodes[1]
			if name_node then
				local pos, end_pos = get_pos(child)
				table.insert(members, {
					name = node_text(name_node, bufnr),
					kind = "EnumMember",
					pos = pos,
					end_pos = end_pos,
					children = {},
				})
			end
		end
	end
	return members
end

--- Extract members from a field_declaration_list (class/struct body).
---@param body_node userdata field_declaration_list node
---@param bufnr integer
---@param default_access string "public"|"private"
---@return UnrealiumSymbol[]
local function extract_members(body_node, bufnr, default_access)
	local members = {}
	local current_access = default_access

	--- Process a single child node within a class/struct body.
	--- Extracted as a local function so ERROR node recovery can reuse it.
	---@param child userdata treesitter node
	local function process_member_node(child)
		local ctype = child:type()

		if ctype == "access_specifier" then
			current_access = node_text(child, bufnr):gsub("%s*:%s*$", ""):match("%w+") or current_access
		elseif ctype == "field_declaration" then
			local name, is_method = extract_field_info(child, bufnr)
			if name then
				local pos, end_pos = get_pos(child)
				local ue_macro = detect_ue_macro(child, bufnr)
				table.insert(members, {
					name = name,
					kind = is_method and "Method" or "Field",
					pos = pos,
					end_pos = end_pos,
					ue_macro = ue_macro,
					access = current_access,
					children = {},
				})
			end
		elseif ctype == "function_definition" then
			local name = extract_function_info(child, bufnr)
			if name then
				local pos, end_pos = get_pos(child)
				local ue_macro = detect_ue_macro(child, bufnr)
				table.insert(members, {
					name = name,
					kind = "Method",
					pos = pos,
					end_pos = end_pos,
					ue_macro = ue_macro,
					access = current_access,
					children = {},
				})
			end
		elseif ctype == "declaration" then
			local name = extract_function_info(child, bufnr)
			if name then
				local pos, end_pos = get_pos(child)
				local ue_macro = detect_ue_macro(child, bufnr)
				table.insert(members, {
					name = name,
					kind = "Method",
					pos = pos,
					end_pos = end_pos,
					ue_macro = ue_macro,
					access = current_access,
					children = {},
				})
			end
		elseif ctype == "enum_specifier" then
			local enum_name = extract_class_name(child, bufnr)
			if enum_name then
				local pos, end_pos = get_pos(child)
				local body = child:field("body")
				local enum_children = body and body[1] and extract_enumerators(body[1], bufnr) or {}
				table.insert(members, {
					name = enum_name,
					kind = "Enum",
					pos = pos,
					end_pos = end_pos,
					access = current_access,
					children = enum_children,
				})
			end
		elseif ctype == "class_specifier" or ctype == "struct_specifier" then
			local nested_name = extract_class_name(child, bufnr)
			if nested_name then
				local pos, end_pos = get_pos(child)
				local nested_default = ctype == "class_specifier" and "private" or "public"
				local body = child:field("body")
				local nested_children = body and body[1] and extract_members(body[1], bufnr, nested_default) or {}
				table.insert(members, {
					name = nested_name,
					kind = ctype == "class_specifier" and "Class" or "Struct",
					pos = pos,
					end_pos = end_pos,
					access = current_access,
					children = nested_children,
				})
			end
		elseif ctype == "ERROR" then
			-- WORKAROUND: GENERATED_BODY() and similar UE macros produce ERROR nodes in the
			-- standard C++ treesitter grammar, which can absorb subsequent real declarations
			-- as children. Recurse into the error node to recover them.
			-- TODO: Replace with a custom UE-aware treesitter grammar/parser.
			for err_child in child:iter_children() do
				process_member_node(err_child)
			end
		end
	end

	for child in body_node:iter_children() do
		process_member_node(child)
	end

	return members
end

--- Walk top-level nodes and extract symbols.
---@param root userdata translation_unit or compound_statement node
---@param bufnr integer
---@return UnrealiumSymbol[]
local function walk_top_level(root, bufnr)
	local symbols = {}

	--- Process a single top-level node.
	--- Extracted as a local function so ERROR node recovery can reuse it.
	---@param child userdata treesitter node
	local function process_top_level_node(child)
		local ctype = child:type()

		if ctype == "declaration" then
			-- A declaration can wrap class/struct/enum specifiers or be a function prototype
			local type_nodes = child:field("type")
			local type_node = type_nodes and type_nodes[1]

			if type_node then
				local ttype = type_node:type()
				if ttype == "class_specifier" or ttype == "struct_specifier" then
					local name = extract_class_name(type_node, bufnr)
					if name then
						local pos, end_pos = get_pos(type_node)
						local ue_macro = detect_ue_macro(child, bufnr)
						local is_class = ttype == "class_specifier"
						local default_access = is_class and "private" or "public"
						local body = type_node:field("body")
						local children = body and body[1] and extract_members(body[1], bufnr, default_access) or {}
						table.insert(symbols, {
							name = name,
							kind = is_class and "Class" or "Struct",
							pos = pos,
							end_pos = end_pos,
							ue_macro = ue_macro,
							children = children,
						})
					end
				elseif ttype == "enum_specifier" then
					local name = extract_class_name(type_node, bufnr)
					if name then
						local pos, end_pos = get_pos(type_node)
						local ue_macro = detect_ue_macro(child, bufnr)
						local body = type_node:field("body")
						local enum_children = body and body[1] and extract_enumerators(body[1], bufnr) or {}
						table.insert(symbols, {
							name = name,
							kind = "Enum",
							pos = pos,
							end_pos = end_pos,
							ue_macro = ue_macro,
							children = enum_children,
						})
					end
				else
					-- Check for function prototype
					local name, class_name = extract_function_info(child, bufnr)
					if name then
						local pos, end_pos = get_pos(child)
						table.insert(symbols, {
							name = name,
							kind = class_name and "Method" or "Function",
							pos = pos,
							end_pos = end_pos,
							class_name = class_name,
							children = {},
						})
					end
				end
			else
				-- No type field; might still be a function prototype
				local name, class_name = extract_function_info(child, bufnr)
				if name then
					local pos, end_pos = get_pos(child)
					table.insert(symbols, {
						name = name,
						kind = class_name and "Method" or "Function",
						pos = pos,
						end_pos = end_pos,
						class_name = class_name,
						children = {},
					})
				end
			end
		elseif ctype == "function_definition" then
			local name, class_name = extract_function_info(child, bufnr)
			if name then
				local pos, end_pos = get_pos(child)
				table.insert(symbols, {
					name = name,
					kind = class_name and "Method" or "Function",
					pos = pos,
					end_pos = end_pos,
					class_name = class_name,
					children = {},
				})
			end
		elseif ctype == "namespace_definition" then
			local name_nodes = child:field("name")
			local name_node = name_nodes and name_nodes[1]
			local ns_name = name_node and node_text(name_node, bufnr) or "(anonymous)"
			local pos, end_pos = get_pos(child)
			local body = child:field("body")
			local ns_children = body and body[1] and walk_top_level(body[1], bufnr) or {}
			table.insert(symbols, {
				name = ns_name,
				kind = "Namespace",
				pos = pos,
				end_pos = end_pos,
				children = ns_children,
			})
		elseif ctype == "class_specifier" or ctype == "struct_specifier" then
			-- Direct specifier at top level (without wrapping declaration)
			local name = extract_class_name(child, bufnr)
			if name then
				local pos, end_pos = get_pos(child)
				local ue_macro = detect_ue_macro(child, bufnr)
				local is_class = ctype == "class_specifier"
				local default_access = is_class and "private" or "public"
				local body = child:field("body")
				local children = body and body[1] and extract_members(body[1], bufnr, default_access) or {}
				table.insert(symbols, {
					name = name,
					kind = is_class and "Class" or "Struct",
					pos = pos,
					end_pos = end_pos,
					ue_macro = ue_macro,
					children = children,
				})
			end
		elseif ctype == "enum_specifier" then
			local name = extract_class_name(child, bufnr)
			if name then
				local pos, end_pos = get_pos(child)
				local ue_macro = detect_ue_macro(child, bufnr)
				local body = child:field("body")
				local enum_children = body and body[1] and extract_enumerators(body[1], bufnr) or {}
				table.insert(symbols, {
					name = name,
					kind = "Enum",
					pos = pos,
					end_pos = end_pos,
					ue_macro = ue_macro,
					children = enum_children,
				})
			end
		elseif ctype == "ERROR" then
			-- WORKAROUND: UE macros (UCLASS, USTRUCT, etc.) at the top level can produce
			-- ERROR nodes in the standard C++ treesitter grammar, which may absorb subsequent
			-- real declarations as children. Recurse into the error node to recover them.
			-- TODO: Replace with a custom UE-aware treesitter grammar/parser.
			for err_child in child:iter_children() do
				process_top_level_node(err_child)
			end
		end
	end

	for child in root:iter_children() do
		process_top_level_node(child)
	end

	return symbols
end

--- Extract hierarchical symbols from a buffer using treesitter.
---@param bufnr integer
---@return UnrealiumSymbol[]
function M.extract_symbols(bufnr)
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "cpp")
	if not ok or not parser then
		return {}
	end

	local trees = parser:parse()
	if not trees or #trees == 0 then
		return {}
	end

	return walk_top_level(trees[1]:root(), bufnr)
end

--- Merge header symbols with source implementations.
--- Header provides the class hierarchy; source provides method implementations.
---@param header_symbols UnrealiumSymbol[]
---@param source_symbols UnrealiumSymbol[]
---@return UnrealiumSymbol[]
function M.merge_symbols(header_symbols, source_symbols)
	local merged = vim.deepcopy(header_symbols)

	-- Index header classes by name for quick lookup
	local class_index = {}
	local function index_classes(syms)
		for _, sym in ipairs(syms) do
			if sym.kind == "Class" or sym.kind == "Struct" then
				class_index[sym.name] = sym
			end
			if sym.children then
				index_classes(sym.children)
			end
		end
	end
	index_classes(merged)

	-- Process source symbols
	for _, sym in ipairs(source_symbols) do
		if sym.class_name and class_index[sym.class_name] then
			-- Method implementation — find existing declaration or add
			local class_sym = class_index[sym.class_name]
			local found = false
			for _, child in ipairs(class_sym.children) do
				if child.name == sym.name and (child.kind == "Method" or child.kind == "Function") then
					child.has_impl = true
					child.impl_file = sym.source_file
					child.impl_pos = sym.pos
					found = true
					break
				end
			end
			if not found then
				local new_sym = vim.deepcopy(sym)
				new_sym.access = "impl"
				new_sym.class_name = nil
				table.insert(class_sym.children, new_sym)
			end
		elseif not sym.class_name then
			-- Free function from source
			table.insert(merged, sym)
		end
	end

	return merged
end

--- Get merged symbols for current buffer + companion.
---@param bufnr integer
---@return UnrealiumSymbol[] symbols
---@return string|nil companion_path
function M.get_symbols_for_buffer(bufnr)
	local symbols = M.extract_symbols(bufnr)

	local filepath = vim.api.nvim_buf_get_name(bufnr)
	if filepath == "" then
		return symbols, nil
	end

	-- Find companion file
	local switch_ok, switch = pcall(require, "unrealium.modules.switch")
	if not switch_ok then
		return symbols, nil
	end

	local companion_path = switch.find_companion(filepath)
	if not companion_path then
		return symbols, nil
	end

	-- Load companion buffer for treesitter parsing (non-destructive)
	local companion_buf = vim.fn.bufadd(companion_path)
	vim.fn.bufload(companion_buf)

	local companion_symbols = M.extract_symbols(companion_buf)

	-- Determine header vs source
	local ext = vim.fn.fnamemodify(filepath, ":e"):lower()
	local header_symbols, source_symbols
	if ext == "h" or ext == "hpp" then
		header_symbols = symbols
		source_symbols = companion_symbols
		-- Mark source symbols with companion file info for cross-file jump
		for _, sym in ipairs(source_symbols) do
			sym.source_file = companion_path
		end
	else
		header_symbols = companion_symbols
		source_symbols = symbols
		-- Mark header symbols with companion file info
		local function mark_file(syms, file)
			for _, sym in ipairs(syms) do
				sym.source_file = file
				if sym.children then
					mark_file(sym.children, file)
				end
			end
		end
		mark_file(header_symbols, companion_path)
	end

	local merged = M.merge_symbols(header_symbols, source_symbols)
	return merged, companion_path
end

if _TEST then
	M._detect_ue_macro = detect_ue_macro
	M._extract_class_name = extract_class_name
	M._extract_function_info = extract_function_info
	M._extract_field_info = extract_field_info
	M._extract_members = extract_members
	M._walk_top_level = walk_top_level
end

return M
