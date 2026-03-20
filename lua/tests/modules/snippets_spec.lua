---@module 'luassert'

_TEST = true

describe("modules.snippets", function()
	local snippets

	before_each(function()
		package.loaded["unrealium.modules.snippets"] = nil
		snippets = require("unrealium.modules.snippets")
	end)

	it("module loads without error", function()
		assert.equals("snippets", snippets.name)
		assert.is_function(snippets.get_categories)
		assert.is_function(snippets.build_uelog_snippet)
		assert.is_function(snippets.build_uelogfmt_snippet)
		assert.is_function(snippets.get_module_api)
		assert.is_function(snippets.build_uenum_snippet)
		assert.is_function(snippets.build_ustruct_snippet)
		assert.is_function(snippets.build_uclass_snippet)
		assert.is_function(snippets.build_uinterface_snippet)
		assert.is_function(snippets.build_ucast_snippet)
		assert.is_function(snippets.build_ufunction_snippet)
		assert.is_function(snippets.build_uproperty_snippet)
	end)

	describe("build_uelog_snippet", function()
		it("builds snippet with single category", function()
			local result = snippets.build_uelog_snippet({ "LogTemp" })
			assert.is_truthy(result:find("LogTemp", 1, true))
			assert.is_truthy(result:find("UE_LOG", 1, true))
			assert.is_truthy(result:find('TEXT("${3}"));$0', 1, true))
			assert.is_truthy(result:find("${1|LogTemp|}", 1, true))
		end)

		it("builds snippet with multiple categories", function()
			local result = snippets.build_uelog_snippet({ "LogMyGame", "LogNet", "LogTemp" })
			assert.is_truthy(result:find("${1|LogMyGame,LogNet,LogTemp|}", 1, true))
		end)

		it("includes verbosity choices", function()
			local result = snippets.build_uelog_snippet({ "LogTemp" })
			assert.is_truthy(result:find("Log,Warning,Error,Display,Verbose,VeryVerbose,Fatal", 1, true))
		end)
	end)

	describe("build_uelogfmt_snippet", function()
		it("builds snippet without TEXT wrapper", function()
			local result = snippets.build_uelogfmt_snippet({ "LogTemp" })
			assert.is_truthy(result:find("UE_LOGFMT", 1, true))
			assert.is_falsy(result:find("TEXT", 1, true))
			assert.is_truthy(result:find('"${3}");$0', 1, true))
		end)

		it("builds snippet with multiple categories", function()
			local result = snippets.build_uelogfmt_snippet({ "LogMyGame", "LogTemp" })
			assert.is_truthy(result:find("${1|LogMyGame,LogTemp|}", 1, true))
		end)
	end)

	describe("build_uenum_snippet", function()
		it("builds UENUM with BlueprintType and base type choices", function()
			local result = snippets.build_uenum_snippet()
			assert.is_truthy(result:find("UENUM(BlueprintType)", 1, true))
			assert.is_truthy(result:find("enum class ${1:EName}", 1, true))
			assert.is_truthy(result:find("${2|uint8,uint16,uint32,int32|}", 1, true))
			assert.is_truthy(result:find("UMETA(DisplayName=", 1, true))
			assert.is_truthy(result:find("};$0", 1, true))
		end)
	end)

	describe("build_ustruct_snippet", function()
		it("builds USTRUCT with GENERATED_BODY and UPROPERTY", function()
			local result = snippets.build_ustruct_snippet()
			assert.is_truthy(result:find("USTRUCT(BlueprintType)", 1, true))
			assert.is_truthy(result:find("struct ${1:FMyStruct}", 1, true))
			assert.is_truthy(result:find("GENERATED_BODY()", 1, true))
			assert.is_truthy(result:find("UPROPERTY(EditAnywhere, BlueprintReadWrite", 1, true))
			assert.is_falsy(result:find("GENERATED_USTRUCT_BODY", 1, true))
		end)
	end)

	describe("build_uclass_snippet", function()
		it("includes module_api in class declaration", function()
			local result = snippets.build_uclass_snippet("MYMODULE_API")
			assert.is_truthy(result:find("class MYMODULE_API", 1, true))
			assert.is_truthy(result:find("UCLASS()", 1, true))
			assert.is_truthy(result:find("GENERATED_BODY()", 1, true))
		end)

		it("has parent class choices", function()
			local result = snippets.build_uclass_snippet("TEST_API")
			assert.is_truthy(result:find("AActor,ACharacter,APawn", 1, true))
			assert.is_truthy(result:find("UObject,UActorComponent,USceneComponent", 1, true))
		end)

		it("mirrors class name into constructor via $1", function()
			local result = snippets.build_uclass_snippet("TEST_API")
			assert.is_truthy(result:find("${1:AMyActor}", 1, true))
			assert.is_truthy(result:find("\t$1();", 1, true))
		end)
	end)

	describe("build_uinterface_snippet", function()
		it("includes module_api and mirrors interface name", function()
			local result = snippets.build_uinterface_snippet("MYMODULE_API")
			assert.is_truthy(result:find("class MYMODULE_API U${1:MyInterface}", 1, true))
			assert.is_truthy(result:find("class MYMODULE_API I$1", 1, true))
			assert.is_truthy(result:find("UINTERFACE()", 1, true))
		end)

		it("has both UObject and abstract interface classes", function()
			local result = snippets.build_uinterface_snippet("TEST_API")
			assert.is_truthy(result:find(": public UInterface", 1, true))
			-- Two GENERATED_BODY() calls
			local _, first_end = result:find("GENERATED_BODY()", 1, true)
			assert.is_truthy(first_end)
			assert.is_truthy(result:find("GENERATED_BODY()", first_end + 1, true))
		end)
	end)

	describe("build_ucast_snippet", function()
		it("builds Cast<> with mirrored type", function()
			local result = snippets.build_ucast_snippet()
			assert.is_truthy(result:find("${1:AMyClass}", 1, true))
			assert.is_truthy(result:find("Cast<$1>", 1, true))
			assert.is_truthy(result:find("${3:SourceActor}", 1, true))
		end)
	end)

	describe("build_ufunction_snippet", function()
		it("builds UFUNCTION with specifier choices", function()
			local result = snippets.build_ufunction_snippet()
			assert.is_truthy(result:find("UFUNCTION(${1|", 1, true))
			assert.is_truthy(result:find("BlueprintCallable", 1, true))
			assert.is_truthy(result:find("BlueprintPure", 1, true))
			assert.is_truthy(result:find("Server", 1, true))
			assert.is_truthy(result:find("NetMulticast", 1, true))
			assert.is_truthy(result:find("|})$0", 1, true))
		end)
	end)

	describe("build_uproperty_snippet", function()
		it("builds UPROPERTY with visibility, access, and category", function()
			local result = snippets.build_uproperty_snippet()
			assert.is_truthy(result:find("UPROPERTY(${1|", 1, true))
			assert.is_truthy(result:find("EditAnywhere", 1, true))
			assert.is_truthy(result:find("VisibleAnywhere", 1, true))
			assert.is_truthy(result:find("${2|BlueprintReadWrite,BlueprintReadOnly|}", 1, true))
			assert.is_truthy(result:find('Category="${3:Default}"', 1, true))
		end)
	end)

	describe("get_categories", function()
		it("returns LogTemp for empty buffer", function()
			local buf = vim.api.nvim_create_buf(false, true)
			local cats = snippets.get_categories(buf)
			assert.same({ "LogTemp" }, cats)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("discovers categories from buffer content", function()
			local buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
				'UE_LOG(LogMyGame, Warning, TEXT("test"));',
				'UE_LOG(LogMyGame, Error, TEXT("test2"));',
				'UE_LOG(LogTemp, Log, TEXT("temp"));',
			})
			local cats = snippets.get_categories(buf)
			-- LogMyGame should be first (count=2), LogTemp second (count=1)
			assert.equals("LogMyGame", cats[1])
			assert.equals("LogTemp", cats[2])
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("appends LogTemp if not found in buffer", function()
			local buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
				'UE_LOG(LogMyGame, Warning, TEXT("test"));',
			})
			local cats = snippets.get_categories(buf)
			assert.equals("LogMyGame", cats[1])
			assert.equals("LogTemp", cats[2])
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("does not duplicate LogTemp if already present", function()
			local buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
				'UE_LOG(LogTemp, Warning, TEXT("test"));',
			})
			local cats = snippets.get_categories(buf)
			assert.equals(1, #cats)
			assert.equals("LogTemp", cats[1])
			vim.api.nvim_buf_delete(buf, { force = true })
		end)
	end)

	describe("directory scanning", function()
		local tmp_dir

		before_each(function()
			tmp_dir = vim.fn.tempname()
			vim.fn.mkdir(tmp_dir, "p")
		end)

		after_each(function()
			vim.fn.delete(tmp_dir, "rf")
		end)

		it("scans sibling cpp files", function()
			-- Create a sibling file with UE_LOG calls
			local sibling = vim.fs.joinpath(tmp_dir, "Sibling.cpp")
			local f = io.open(sibling, "w")
			f:write('UE_LOG(LogSibling, Warning, TEXT("hello"));\n')
			f:write('UE_LOG(LogSibling, Error, TEXT("world"));\n')
			f:close()

			-- Create the "current" file (empty)
			local current = vim.fs.joinpath(tmp_dir, "Current.cpp")
			local f2 = io.open(current, "w")
			f2:write("")
			f2:close()

			local dir_cats = snippets._scan_directory(current)
			assert.equals(2, dir_cats["LogSibling"])
		end)

		it("cache is invalidated after invalidate_cache", function()
			local sibling = vim.fs.joinpath(tmp_dir, "File.cpp")
			local f = io.open(sibling, "w")
			f:write('UE_LOG(LogOld, Log, TEXT("old"));\n')
			f:close()

			local current = vim.fs.joinpath(tmp_dir, "Main.cpp")
			local f2 = io.open(current, "w")
			f2:write("")
			f2:close()

			-- First scan populates cache
			local cats1 = snippets._scan_directory(current)
			assert.equals(1, cats1["LogOld"])

			-- Modify sibling
			local f3 = io.open(sibling, "w")
			f3:write('UE_LOG(LogNew, Log, TEXT("new"));\n')
			f3:close()

			-- Cache still returns old data
			local cats2 = snippets._scan_directory(current)
			assert.equals(1, cats2["LogOld"])

			-- Invalidate cache
			snippets._invalidate_cache(current)

			-- Now should pick up new data
			local cats3 = snippets._scan_directory(current)
			assert.is_nil(cats3["LogOld"])
			assert.equals(1, cats3["LogNew"])
		end)
	end)

	describe("get_module_api", function()
		local tmp_dir

		before_each(function()
			tmp_dir = vim.fn.tempname()
			vim.fn.mkdir(tmp_dir, "p")
			-- Clear api cache between tests
			for k in pairs(snippets._api_cache) do
				snippets._api_cache[k] = nil
			end
		end)

		after_each(function()
			vim.fn.delete(tmp_dir, "rf")
		end)

		it("discovers module API from Build.cs file", function()
			-- Create a Build.cs file
			local build_cs = vim.fs.joinpath(tmp_dir, "MyModule.Build.cs")
			local f = io.open(build_cs, "w")
			f:write("// build file\n")
			f:close()

			-- Create a source file in the same directory
			local source_file = vim.fs.joinpath(tmp_dir, "MyActor.cpp")
			local f2 = io.open(source_file, "w")
			f2:write("")
			f2:close()

			local buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_name(buf, source_file)

			local api = snippets.get_module_api(buf)
			assert.equals("MYMODULE_API", api)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("walks up directories to find Build.cs", function()
			-- Create nested structure: tmp_dir/Source/MyModule/Private/
			local module_dir = vim.fs.joinpath(tmp_dir, "Source", "MyModule")
			local private_dir = vim.fs.joinpath(module_dir, "Private")
			vim.fn.mkdir(private_dir, "p")

			-- Build.cs at module level
			local build_cs = vim.fs.joinpath(module_dir, "ShooterGame.Build.cs")
			local f = io.open(build_cs, "w")
			f:write("// build file\n")
			f:close()

			-- Source file in Private/
			local source_file = vim.fs.joinpath(private_dir, "MyActor.cpp")
			local f2 = io.open(source_file, "w")
			f2:write("")
			f2:close()

			local buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_name(buf, source_file)

			local api = snippets.get_module_api(buf)
			assert.equals("SHOOTERGAME_API", api)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("falls back to scanning API macros from sibling files", function()
			-- No Build.cs, but sibling files have API macros
			local sibling = vim.fs.joinpath(tmp_dir, "OtherActor.h")
			local f = io.open(sibling, "w")
			f:write("class MYGAME_API AOtherActor : public AActor\n")
			f:write("{\n")
			f:write("};\n")
			f:close()

			local source_file = vim.fs.joinpath(tmp_dir, "MyActor.cpp")
			local f2 = io.open(source_file, "w")
			f2:write("")
			f2:close()

			local buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_name(buf, source_file)

			local api = snippets.get_module_api(buf)
			assert.equals("MYGAME_API", api)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("returns PROJECTNAME_API as final fallback", function()
			-- Empty directory, no Build.cs, no sibling files
			local source_file = vim.fs.joinpath(tmp_dir, "Lonely.cpp")
			local f = io.open(source_file, "w")
			f:write("")
			f:close()

			local buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_name(buf, source_file)

			local api = snippets.get_module_api(buf)
			assert.equals("PROJECTNAME_API", api)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)

		it("returns PROJECTNAME_API for unnamed buffer", function()
			local buf = vim.api.nvim_create_buf(false, true)
			local api = snippets.get_module_api(buf)
			assert.equals("PROJECTNAME_API", api)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)
	end)
end)
