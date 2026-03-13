---@module 'luassert'

_TEST = true

--- Check if the C++ treesitter parser is available.
---@return boolean
local function has_cpp_parser()
	local ok = pcall(vim.treesitter.language.inspect, "cpp")
	return ok
end

--- Create a scratch buffer with the given C++ content.
---@param lines string[]
---@return integer bufnr
local function make_cpp_buffer(lines)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].filetype = "cpp"
	return buf
end

describe("core.ts", function()
	local ts

	before_each(function()
		package.loaded["unrealium.core.ts"] = nil
		ts = require("unrealium.core.ts")
	end)

	it("module loads without error", function()
		assert.is_table(ts)
		assert.is_function(ts.get_enclosing_function)
		assert.is_function(ts.find_function_in_buffer)
	end)

	if not has_cpp_parser() then
		return
	end

	describe("get_enclosing_function", function()
		it("finds a simple function", function()
			local buf = make_cpp_buffer({
				"void MyFunction() {",
				"    int x = 1;",
				"}",
			})
			local result = ts.get_enclosing_function(buf, 1, 4)
			assert.is_not_nil(result)
			assert.equals("MyFunction", result.name)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("finds a qualified member function", function()
			local buf = make_cpp_buffer({
				"void AMyActor::BeginPlay() {",
				"    Super::BeginPlay();",
				"}",
			})
			local result = ts.get_enclosing_function(buf, 1, 4)
			assert.is_not_nil(result)
			assert.equals("BeginPlay", result.name)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("returns nil when cursor is outside a function", function()
			local buf = make_cpp_buffer({
				"#include <iostream>",
				"",
				"void Foo() {}",
			})
			local result = ts.get_enclosing_function(buf, 0, 0)
			assert.is_nil(result)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("finds the outer function when inside a lambda", function()
			local buf = make_cpp_buffer({
				"void OuterFunc() {",
				"    auto fn = [](int x) {",
				"        return x + 1;",
				"    };",
				"}",
			})
			-- Cursor inside the lambda body (line 2, inside the return)
			local result = ts.get_enclosing_function(buf, 2, 8)
			assert.is_not_nil(result)
			assert.equals("OuterFunc", result.name)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("returns nil when no treesitter parser is available", function()
			local buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "hello world" })
			vim.bo[buf].filetype = "plaintext"
			local result = ts.get_enclosing_function(buf, 0, 0)
			assert.is_nil(result)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)
	end)

	describe("find_function_in_buffer", function()
		it("finds a definition by name", function()
			local buf = make_cpp_buffer({
				"void AMyActor::BeginPlay() {",
				"    Super::BeginPlay();",
				"}",
				"",
				"void AMyActor::Tick(float DeltaTime) {",
				"    // tick",
				"}",
			})
			local line = ts.find_function_in_buffer(buf, "Tick", "definition")
			assert.equals(5, line)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("finds a declaration by name", function()
			local buf = make_cpp_buffer({
				"class AMyActor {",
				"    void BeginPlay();",
				"    void Tick(float DeltaTime);",
				"};",
			})
			local line = ts.find_function_in_buffer(buf, "Tick", "declaration")
			assert.is_not_nil(line)
			assert.equals(3, line)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("returns nil when function not found", function()
			local buf = make_cpp_buffer({
				"void Foo() {}",
			})
			local line = ts.find_function_in_buffer(buf, "Bar", "definition")
			assert.is_nil(line)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("finds the correct function among multiple", function()
			local buf = make_cpp_buffer({
				"void Alpha() {}",
				"void Beta() {}",
				"void Gamma() {}",
			})
			local line = ts.find_function_in_buffer(buf, "Beta", "definition")
			assert.equals(2, line)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)
	end)

	describe("extract_function_name", function()
		it("extracts simple name", function()
			local buf = make_cpp_buffer({
				"void MyFunc() {}",
			})
			local parser = vim.treesitter.get_parser(buf, "cpp")
			local root = parser:parse()[1]:root()
			local func_node = root:child(0)
			assert.equals("function_definition", func_node:type())
			local name = ts._extract_function_name(func_node, buf)
			assert.equals("MyFunc", name)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("extracts qualified name (strips class prefix)", function()
			local buf = make_cpp_buffer({
				"void AMyActor::BeginPlay() {}",
			})
			local parser = vim.treesitter.get_parser(buf, "cpp")
			local root = parser:parse()[1]:root()
			local func_node = root:child(0)
			local name = ts._extract_function_name(func_node, buf)
			assert.equals("BeginPlay", name)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("extracts destructor name", function()
			local buf = make_cpp_buffer({
				"AMyActor::~AMyActor() {}",
			})
			local parser = vim.treesitter.get_parser(buf, "cpp")
			local root = parser:parse()[1]:root()
			local func_node = root:child(0)
			local name = ts._extract_function_name(func_node, buf)
			assert.equals("~AMyActor", name)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)
	end)
end)
