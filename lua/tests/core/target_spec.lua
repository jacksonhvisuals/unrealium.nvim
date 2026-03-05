---@module 'luassert'

_TEST = true
local target = require("unrealium.core.target")

describe("core.target", function()
	describe("classify_target", function()
		it("classifies Editor targets", function()
			assert.equals("Editor", target._classify_target("MyProjectEditor.Target.cs"))
		end)

		it("classifies Server targets", function()
			assert.equals("Server", target._classify_target("MyProjectServer.Target.cs"))
		end)

		it("classifies Client targets", function()
			assert.equals("Client", target._classify_target("MyProjectClient.Target.cs"))
		end)

		it("classifies Game targets", function()
			assert.equals("Game", target._classify_target("MyProject.Target.cs"))
		end)

		it("handles non-matching filenames as Game", function()
			assert.equals("Game", target._classify_target("SomethingElse.cs"))
		end)
	end)

	describe("discover", function()
		local tmp_dir

		before_each(function()
			tmp_dir = vim.fn.tempname()
			vim.fn.mkdir(tmp_dir, "p")
		end)

		after_each(function()
			vim.fn.delete(tmp_dir, "rf")
		end)

		it("discovers targets in Source/", function()
			local source_dir = vim.fs.joinpath(tmp_dir, "Source")
			vim.fn.mkdir(source_dir, "p")

			-- Create target files
			local f1 = io.open(vim.fs.joinpath(source_dir, "MyProjectEditor.Target.cs"), "w")
			f1:write("// target")
			f1:close()

			local f2 = io.open(vim.fs.joinpath(source_dir, "MyProject.Target.cs"), "w")
			f2:write("// target")
			f2:close()

			local targets = target.discover(tmp_dir)
			assert.equals(2, #targets)

			-- Sort by name for stable assertions
			table.sort(targets, function(a, b)
				return a.name < b.name
			end)

			assert.equals("MyProject", targets[1].name)
			assert.equals("Game", targets[1].type)
			assert.equals("MyProjectEditor", targets[2].name)
			assert.equals("Editor", targets[2].type)
		end)

		it("returns empty table when no Source/ exists", function()
			local targets = target.discover(tmp_dir)
			assert.equals(0, #targets)
		end)
	end)
end)
