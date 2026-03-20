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

describe("core.ts_symbols", function()
	local ts_symbols

	before_each(function()
		package.loaded["unrealium.core.ts_symbols"] = nil
		ts_symbols = require("unrealium.core.ts_symbols")
	end)

	it("module loads without error", function()
		assert.is_table(ts_symbols)
		assert.is_function(ts_symbols.extract_symbols)
		assert.is_function(ts_symbols.merge_symbols)
		assert.is_function(ts_symbols.get_symbols_for_buffer)
	end)

	it("returns empty for non-cpp buffer", function()
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "hello world" })
		vim.bo[buf].filetype = "plaintext"
		local symbols = ts_symbols.extract_symbols(buf)
		assert.same({}, symbols)
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	if not has_cpp_parser() then
		return
	end

	describe("extract_symbols", function()
		it("extracts a simple class", function()
			local buf = make_cpp_buffer({
				"class MyClass {",
				"};",
			})
			local symbols = ts_symbols.extract_symbols(buf)
			assert.equals(1, #symbols)
			assert.equals("MyClass", symbols[1].name)
			assert.equals("Class", symbols[1].kind)
			assert.same({ 1, 0 }, symbols[1].pos)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("extracts a struct with fields", function()
			local buf = make_cpp_buffer({
				"struct FMyStruct {",
				"    float X;",
				"    float Y;",
				"};",
			})
			local symbols = ts_symbols.extract_symbols(buf)
			assert.equals(1, #symbols)
			assert.equals("FMyStruct", symbols[1].name)
			assert.equals("Struct", symbols[1].kind)
			assert.equals(2, #symbols[1].children)
			assert.equals("X", symbols[1].children[1].name)
			assert.equals("Field", symbols[1].children[1].kind)
			assert.equals("public", symbols[1].children[1].access)
			assert.equals("Y", symbols[1].children[2].name)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("extracts an enum with enumerators", function()
			local buf = make_cpp_buffer({
				"enum class EMyEnum {",
				"    Value1,",
				"    Value2,",
				"    Value3",
				"};",
			})
			local symbols = ts_symbols.extract_symbols(buf)
			assert.equals(1, #symbols)
			assert.equals("EMyEnum", symbols[1].name)
			assert.equals("Enum", symbols[1].kind)
			assert.equals(3, #symbols[1].children)
			assert.equals("Value1", symbols[1].children[1].name)
			assert.equals("EnumMember", symbols[1].children[1].kind)
			assert.equals("Value2", symbols[1].children[2].name)
			assert.equals("Value3", symbols[1].children[3].name)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("tracks access specifiers in class", function()
			local buf = make_cpp_buffer({
				"class MyClass {",
				"    int PrivateField;",
				"public:",
				"    void PublicMethod();",
				"protected:",
				"    int ProtectedField;",
				"};",
			})
			local symbols = ts_symbols.extract_symbols(buf)
			assert.equals(1, #symbols)
			local children = symbols[1].children
			assert.equals(3, #children)
			assert.equals("PrivateField", children[1].name)
			assert.equals("private", children[1].access)
			assert.equals("PublicMethod", children[2].name)
			assert.equals("public", children[2].access)
			assert.equals("ProtectedField", children[3].name)
			assert.equals("protected", children[3].access)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("extracts a free function", function()
			local buf = make_cpp_buffer({
				"void FreeFunction() {",
				"    int x = 1;",
				"}",
			})
			local symbols = ts_symbols.extract_symbols(buf)
			assert.equals(1, #symbols)
			assert.equals("FreeFunction", symbols[1].name)
			assert.equals("Function", symbols[1].kind)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("extracts qualified ClassName::Method", function()
			local buf = make_cpp_buffer({
				"void AMyActor::BeginPlay() {",
				"    Super::BeginPlay();",
				"}",
			})
			local symbols = ts_symbols.extract_symbols(buf)
			assert.equals(1, #symbols)
			assert.equals("BeginPlay", symbols[1].name)
			assert.equals("Method", symbols[1].kind)
			assert.equals("AMyActor", symbols[1].class_name)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("extracts namespace with children", function()
			local buf = make_cpp_buffer({
				"namespace MyNS {",
				"    void Helper() {}",
				"}",
			})
			local symbols = ts_symbols.extract_symbols(buf)
			assert.equals(1, #symbols)
			assert.equals("MyNS", symbols[1].name)
			assert.equals("Namespace", symbols[1].kind)
			assert.equals(1, #symbols[1].children)
			assert.equals("Helper", symbols[1].children[1].name)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("extracts class with methods and fields", function()
			local buf = make_cpp_buffer({
				"class AMyActor {",
				"public:",
				"    void BeginPlay();",
				"    void Tick(float DeltaTime);",
				"    float Health;",
				"};",
			})
			local symbols = ts_symbols.extract_symbols(buf)
			assert.equals(1, #symbols)
			assert.equals("AMyActor", symbols[1].name)
			local children = symbols[1].children
			assert.equals(3, #children)
			assert.equals("BeginPlay", children[1].name)
			assert.equals("Method", children[1].kind)
			assert.equals("Tick", children[2].name)
			assert.equals("Method", children[2].kind)
			assert.equals("Health", children[3].name)
			assert.equals("Field", children[3].kind)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("extracts function prototype", function()
			local buf = make_cpp_buffer({
				"void FreeFunc();",
			})
			local symbols = ts_symbols.extract_symbols(buf)
			assert.equals(1, #symbols)
			assert.equals("FreeFunc", symbols[1].name)
			assert.equals("Function", symbols[1].kind)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)
	end)

	describe("UE macro detection", function()
		it("detects UCLASS macro on class", function()
			local buf = make_cpp_buffer({
				"UCLASS(BlueprintType)",
				"class AMyActor {",
				"};",
			})
			local symbols = ts_symbols.extract_symbols(buf)
			assert.equals(1, #symbols)
			assert.equals("AMyActor", symbols[1].name)
			assert.equals("Class", symbols[1].kind)
			assert.equals("UCLASS", symbols[1].ue_macro)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("detects USTRUCT macro on struct", function()
			local buf = make_cpp_buffer({
				"USTRUCT(BlueprintType)",
				"struct FMyStruct {",
				"    float X;",
				"};",
			})
			local symbols = ts_symbols.extract_symbols(buf)
			assert.equals(1, #symbols)
			assert.equals("USTRUCT", symbols[1].ue_macro)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("detects UENUM macro on enum", function()
			local buf = make_cpp_buffer({
				"UENUM(BlueprintType)",
				"enum class EMyEnum {",
				"    Value1",
				"};",
			})
			local symbols = ts_symbols.extract_symbols(buf)
			assert.equals(1, #symbols)
			assert.equals("UENUM", symbols[1].ue_macro)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("detects UFUNCTION macro on method", function()
			local buf = make_cpp_buffer({
				"class AMyActor {",
				"public:",
				"    UFUNCTION(BlueprintCallable)",
				"    void MyFunc();",
				"};",
			})
			local symbols = ts_symbols.extract_symbols(buf)
			assert.equals(1, #symbols)
			local methods = symbols[1].children
			assert.equals(1, #methods)
			assert.equals("MyFunc", methods[1].name)
			assert.equals("UFUNCTION", methods[1].ue_macro)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("detects UPROPERTY macro on field", function()
			local buf = make_cpp_buffer({
				"class AMyActor {",
				"public:",
				"    UPROPERTY(EditAnywhere)",
				"    float Health;",
				"};",
			})
			local symbols = ts_symbols.extract_symbols(buf)
			assert.equals(1, #symbols)
			local fields = symbols[1].children
			assert.equals(1, #fields)
			assert.equals("Health", fields[1].name)
			assert.equals("UPROPERTY", fields[1].ue_macro)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("does not detect macro on undecorated members", function()
			local buf = make_cpp_buffer({
				"class Foo {",
				"    int x;",
				"    void bar();",
				"};",
			})
			local symbols = ts_symbols.extract_symbols(buf)
			for _, child in ipairs(symbols[1].children) do
				assert.is_nil(child.ue_macro)
			end
			vim.api.nvim_buf_delete(buf, { force = true })
		end)
	end)

	describe("merge_symbols", function()
		it("merges source implementation into header class", function()
			local header = {
				{
					name = "AMyActor",
					kind = "Class",
					pos = { 1, 0 },
					end_pos = { 10, 0 },
					children = {
						{
							name = "BeginPlay",
							kind = "Method",
							pos = { 3, 0 },
							end_pos = { 3, 20 },
							access = "public",
							children = {},
						},
					},
				},
			}
			local source = {
				{
					name = "BeginPlay",
					kind = "Method",
					pos = { 5, 0 },
					end_pos = { 8, 0 },
					class_name = "AMyActor",
					source_file = "/test.cpp",
					children = {},
				},
			}

			local merged = ts_symbols.merge_symbols(header, source)
			assert.equals(1, #merged)
			assert.equals("AMyActor", merged[1].name)
			assert.equals(1, #merged[1].children)
			assert.equals("BeginPlay", merged[1].children[1].name)
			assert.truthy(merged[1].children[1].has_impl)
		end)

		it("adds source-only methods with access=impl", function()
			local header = {
				{
					name = "AMyActor",
					kind = "Class",
					pos = { 1, 0 },
					end_pos = { 5, 0 },
					children = {},
				},
			}
			local source = {
				{
					name = "CustomInit",
					kind = "Method",
					pos = { 3, 0 },
					end_pos = { 6, 0 },
					class_name = "AMyActor",
					source_file = "/test.cpp",
					children = {},
				},
			}

			local merged = ts_symbols.merge_symbols(header, source)
			assert.equals(1, #merged[1].children)
			assert.equals("CustomInit", merged[1].children[1].name)
			assert.equals("impl", merged[1].children[1].access)
		end)

		it("adds free functions from source to top level", function()
			local header = {
				{
					name = "MyClass",
					kind = "Class",
					pos = { 1, 0 },
					end_pos = { 5, 0 },
					children = {},
				},
			}
			local source = {
				{
					name = "HelperFunc",
					kind = "Function",
					pos = { 1, 0 },
					end_pos = { 3, 0 },
					source_file = "/test.cpp",
					children = {},
				},
			}

			local merged = ts_symbols.merge_symbols(header, source)
			assert.equals(2, #merged)
			assert.equals("MyClass", merged[1].name)
			assert.equals("HelperFunc", merged[2].name)
		end)
	end)
end)
