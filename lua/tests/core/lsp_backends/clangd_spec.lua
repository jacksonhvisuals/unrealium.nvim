---@module 'luassert'

_TEST = true
local tUtil = require("tests.test_util")

describe("core.lsp.backends.clangd", function()
	local backend = require("unrealium.core.lsp.backends.clangd")

	describe("resolve_binary", function()
		it("returns configured path when executable", function()
			local orig = vim.fn.executable
			vim.fn.executable = function(cmd)
				if cmd == "/usr/bin/clangd-17" then
					return 1
				end
				return 0
			end

			local result = backend.resolve_binary("/usr/bin/clangd-17")
			assert.equals("/usr/bin/clangd-17", result)

			vim.fn.executable = orig
		end)

		it("returns nil when configured path is not executable", function()
			local orig = vim.fn.executable
			vim.fn.executable = function(_)
				return 0
			end

			local result = backend.resolve_binary("/nonexistent/clangd")
			assert.is_nil(result)

			vim.fn.executable = orig
		end)

		it("falls back to PATH clangd when no config", function()
			local orig = vim.fn.executable
			vim.fn.executable = function(cmd)
				if cmd == "clangd" then
					return 1
				end
				return 0
			end

			local result = backend.resolve_binary(nil)
			assert.equals("clangd", result)

			vim.fn.executable = orig
		end)

		it("returns nil when clangd not in PATH and no config", function()
			local orig = vim.fn.executable
			vim.fn.executable = function(_)
				return 0
			end

			local result = backend.resolve_binary(nil)
			assert.is_nil(result)

			vim.fn.executable = orig
		end)
	end)

	describe("find_compile_commands", function()
		it("finds compile_commands.json in project folder", function()
			local tmp = vim.fn.tempname()
			vim.fn.mkdir(tmp, "p")
			local f = io.open(tmp .. "/compile_commands.json", "w")
			f:write("[]")
			f:close()

			local cfg = tUtil.mock_config({ Project = { Folder = tmp } })
			local result = backend._find_compile_commands(cfg)
			assert.equals(tmp, result)

			os.remove(tmp .. "/compile_commands.json")
			vim.fn.delete(tmp, "rf")
		end)

		it("finds compile_commands.json in Intermediate subdir", function()
			local tmp = vim.fn.tempname()
			local intermediate = tmp .. "/Intermediate"
			vim.fn.mkdir(intermediate, "p")
			local f = io.open(intermediate .. "/compile_commands.json", "w")
			f:write("[]")
			f:close()

			local cfg = tUtil.mock_config({ Project = { Folder = tmp } })
			local result = backend._find_compile_commands(cfg)
			assert.equals(intermediate, result)

			vim.fn.delete(tmp, "rf")
		end)

		it("returns nil when not found", function()
			local tmp = vim.fn.tempname()
			vim.fn.mkdir(tmp, "p")

			local cfg = tUtil.mock_config({ Project = { Folder = tmp } })
			local result = backend._find_compile_commands(cfg)
			assert.is_nil(result)

			vim.fn.delete(tmp, "rf")
		end)
	end)

	describe("build_cmd", function()
		it("builds command with base flags", function()
			local orig = vim.fn.executable
			vim.fn.executable = function(_)
				return 1
			end

			local cfg = tUtil.mock_config()
			local cmd = backend.build_cmd(cfg, {})
			assert.truthy(cmd)
			assert.equals("clangd", cmd[1])
			local flags = table.concat(cmd, " ")
			assert.matches("--background%-index", flags)
			assert.matches("--pch%-storage=memory", flags)
			assert.matches("--header%-insertion=never", flags)

			vim.fn.executable = orig
		end)

		it("includes extra_flags from settings", function()
			local orig = vim.fn.executable
			vim.fn.executable = function(_)
				return 1
			end

			local cfg = tUtil.mock_config()
			local cmd = backend.build_cmd(cfg, { extra_flags = { "--log=verbose", "-j=4" } })
			assert.truthy(cmd)
			local flags = table.concat(cmd, " ")
			assert.matches("--log=verbose", flags)
			assert.matches("-j=4", flags)

			vim.fn.executable = orig
		end)

		it("returns nil when clangd not found", function()
			local orig = vim.fn.executable
			vim.fn.executable = function(_)
				return 0
			end

			local cfg = tUtil.mock_config()
			local cmd = backend.build_cmd(cfg, {})
			assert.is_nil(cmd)

			vim.fn.executable = orig
		end)
	end)

	describe("stop_external", function()
		it("stops non-unrealium clangd clients", function()
			local stopped_ids = {}
			local orig_get_clients = vim.lsp.get_clients
			vim.lsp.get_clients = function()
				return {
					{
						name = "clangd",
						id = 1,
						stop = function(self)
							table.insert(stopped_ids, self.id)
						end,
					},
					{
						name = "unrealium-clangd",
						id = 2,
						stop = function(self)
							table.insert(stopped_ids, self.id)
						end,
					},
					{
						name = "lua_ls",
						id = 3,
						stop = function(self)
							table.insert(stopped_ids, self.id)
						end,
					},
				}
			end

			local count = backend.stop_external()
			assert.equals(1, count)
			assert.same({ 1 }, stopped_ids)

			vim.lsp.get_clients = orig_get_clients
		end)

		it("stops multiple clangd variants", function()
			local stopped_ids = {}
			local orig_get_clients = vim.lsp.get_clients
			vim.lsp.get_clients = function()
				return {
					{
						name = "clangd",
						id = 1,
						stop = function(self)
							table.insert(stopped_ids, self.id)
						end,
					},
					{
						name = "clangd-18",
						id = 2,
						stop = function(self)
							table.insert(stopped_ids, self.id)
						end,
					},
				}
			end

			local count = backend.stop_external()
			assert.equals(2, count)
			assert.same({ 1, 2 }, stopped_ids)

			vim.lsp.get_clients = orig_get_clients
		end)

		it("returns zero when no external clangd found", function()
			local orig_get_clients = vim.lsp.get_clients
			vim.lsp.get_clients = function()
				return {
					{ name = "unrealium-clangd", id = 1, stop = function() end },
					{ name = "lua_ls", id = 2, stop = function() end },
				}
			end

			local count = backend.stop_external()
			assert.equals(0, count)

			vim.lsp.get_clients = orig_get_clients
		end)
	end)

	describe("client_name", function()
		it("returns unrealium-clangd", function()
			assert.equals("unrealium-clangd", backend.client_name())
		end)
	end)

	describe("filetypes", function()
		it("includes c and cpp", function()
			local ft = backend.filetypes()
			assert.truthy(vim.tbl_contains(ft, "c"))
			assert.truthy(vim.tbl_contains(ft, "cpp"))
		end)
	end)
end)
