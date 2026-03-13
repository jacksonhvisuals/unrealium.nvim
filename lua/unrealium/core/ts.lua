--- Treesitter helpers for C++ function detection and matching.

local M = {}

--- Extract the function name from a function_definition node.
---@param node userdata treesitter node (function_definition)
---@param bufnr integer
---@return string|nil
local function extract_function_name(node, bufnr)
	local declarator = node:field("declarator")[1]
	if not declarator or declarator:type() ~= "function_declarator" then
		return nil
	end

	local name_node = declarator:field("declarator")[1]
	if not name_node then
		return nil
	end

	local ntype = name_node:type()

	if ntype == "qualified_identifier" then
		-- e.g. AMyActor::BeginPlay — take the rightmost identifier
		local last_id
		for child in name_node:iter_children() do
			local ct = child:type()
			if ct == "identifier" or ct == "destructor_name" or ct == "operator_name" then
				last_id = child
			end
		end
		if last_id then
			return vim.treesitter.get_node_text(last_id, bufnr)
		end
		return nil
	end

	if
		ntype == "identifier"
		or ntype == "field_identifier"
		or ntype == "destructor_name"
		or ntype == "operator_name"
	then
		return vim.treesitter.get_node_text(name_node, bufnr)
	end

	return nil
end

--- Get the enclosing function at the given cursor position.
---@param bufnr integer
---@param row integer 0-indexed
---@param col integer 0-indexed
---@return { name: string, node: userdata }|nil
function M.get_enclosing_function(bufnr, row, col)
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "cpp")
	if not ok or not parser then
		return nil
	end

	local trees = parser:parse()
	if not trees or #trees == 0 then
		return nil
	end

	local root = trees[1]:root()
	local node = root:named_descendant_for_range(row, col, row, col)
	if not node then
		return nil
	end

	-- Walk up; keep overwriting result so outermost function_definition wins.
	-- lambda_expression nodes are skipped because they aren't function_definition.
	local result
	local cur = node
	while cur do
		if cur:type() == "function_definition" then
			local name = extract_function_name(cur, bufnr)
			if name then
				result = { name = name, node = cur }
			end
		end
		cur = cur:parent()
	end

	return result
end

--- Find the line of a function by name in a buffer.
---@param bufnr integer
---@param name string function name to search for
---@param search_type "definition"|"declaration"
---@return integer|nil 1-indexed line number, or nil if not found
function M.find_function_in_buffer(bufnr, name, search_type)
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "cpp")
	if not ok or not parser then
		return nil
	end

	parser:parse()

	local query_str
	if search_type == "definition" then
		query_str = "(function_definition declarator: (function_declarator) @decl) @func"
	else
		query_str = [[
			[
				(declaration declarator: (function_declarator) @decl) @func
				(field_declaration declarator: (function_declarator) @decl) @func
			]
		]]
	end

	local query_ok, query = pcall(vim.treesitter.query.parse, "cpp", query_str)
	if not query_ok or not query then
		return nil
	end

	local root = parser:parse()[1]:root()
	for id, node in query:iter_captures(root, bufnr, 0, -1) do
		if query.captures[id] == "func" then
			local func_name = extract_function_name(node, bufnr)
			if func_name == name then
				local row = node:start()
				return row + 1
			end
		end
	end

	return nil
end

if _TEST then
	M._extract_function_name = extract_function_name
end

return M
