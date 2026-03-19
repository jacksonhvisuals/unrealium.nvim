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
	end)

	describe("build_uelog_snippet", function()
		it("builds snippet with single category", function()
			local result = snippets.build_uelog_snippet({ "LogTemp" })
			assert.is_truthy(result:find("LogTemp", 1, true))
			assert.is_truthy(result:find("UE_LOG", 1, true))
			assert.is_truthy(result:find('TEXT("$0")', 1, true))
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
			assert.is_truthy(result:find('"$0"', 1, true))
		end)

		it("builds snippet with multiple categories", function()
			local result = snippets.build_uelogfmt_snippet({ "LogMyGame", "LogTemp" })
			assert.is_truthy(result:find("${1|LogMyGame,LogTemp|}", 1, true))
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
end)
