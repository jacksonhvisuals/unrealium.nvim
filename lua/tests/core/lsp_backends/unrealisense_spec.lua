---@module 'luassert'

_TEST = true

describe("core.lsp.backends.unrealisense", function()
	local backend = require("unrealium.core.lsp.backends.unrealisense")
	local tUtil = require("tests.test_util")

	describe("resolve_binary", function()
		it("returns configured path when executable", function()
			local orig = vim.fn.executable
			vim.fn.executable = function(cmd)
				if cmd == "/usr/local/bin/unrealisense" then
					return 1
				end
				return 0
			end

			local result = backend.resolve_binary("/usr/local/bin/unrealisense")
			assert.equals("/usr/local/bin/unrealisense", result)

			vim.fn.executable = orig
		end)

		it("returns nil when configured path is not executable", function()
			local orig = vim.fn.executable
			vim.fn.executable = function(_)
				return 0
			end

			local result = backend.resolve_binary("/nonexistent/unrealisense")
			assert.is_nil(result)

			vim.fn.executable = orig
		end)

		it("falls back to PATH unrealisense when no config", function()
			local orig = vim.fn.executable
			vim.fn.executable = function(cmd)
				if cmd == "unrealisense" then
					return 1
				end
				return 0
			end

			local result = backend.resolve_binary(nil)
			assert.equals("unrealisense", result)

			vim.fn.executable = orig
		end)

		it("returns nil when unrealisense not in PATH and no config", function()
			local orig = vim.fn.executable
			vim.fn.executable = function(_)
				return 0
			end

			local result = backend.resolve_binary(nil)
			assert.is_nil(result)

			vim.fn.executable = orig
		end)
	end)

	describe("build_cmd", function()
		it("builds command with engine path from config", function()
			local orig = vim.fn.executable
			vim.fn.executable = function(_)
				return 1
			end

			local cfg = tUtil.mock_config()
			local cmd = backend.build_cmd(cfg, {})
			assert.truthy(cmd)
			assert.equals("unrealisense", cmd[1])
			assert.equals("--engine-path", cmd[2])
			assert.equals(cfg.Engine.Folder, cmd[3])

			vim.fn.executable = orig
		end)

		it("uses settings.engine_path override", function()
			local orig = vim.fn.executable
			vim.fn.executable = function(_)
				return 1
			end

			local cfg = tUtil.mock_config()
			local cmd = backend.build_cmd(cfg, { engine_path = "/custom/engine" })
			assert.truthy(cmd)
			assert.equals("--engine-path", cmd[2])
			assert.equals("/custom/engine", cmd[3])

			vim.fn.executable = orig
		end)

		it("includes extra_args", function()
			local orig = vim.fn.executable
			vim.fn.executable = function(_)
				return 1
			end

			local cfg = tUtil.mock_config()
			local cmd = backend.build_cmd(cfg, { extra_args = { "--verbose", "--threads=4" } })
			assert.truthy(cmd)
			local flags = table.concat(cmd, " ")
			assert.matches("--verbose", flags)
			assert.matches("--threads=4", flags)

			vim.fn.executable = orig
		end)

		it("returns nil when binary not found", function()
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
		it("stops external clangd and unrealisense clients", function()
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
						name = "unrealisense",
						id = 2,
						stop = function(self)
							table.insert(stopped_ids, self.id)
						end,
					},
					{
						name = "unrealium-unrealisense",
						id = 3,
						stop = function(self)
							table.insert(stopped_ids, self.id)
						end,
					},
					{
						name = "lua_ls",
						id = 4,
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

		it("does not stop unrealium-managed clients", function()
			local stopped_ids = {}
			local orig_get_clients = vim.lsp.get_clients
			vim.lsp.get_clients = function()
				return {
					{
						name = "unrealium-clangd",
						id = 1,
						stop = function(self)
							table.insert(stopped_ids, self.id)
						end,
					},
					{
						name = "unrealium-unrealisense",
						id = 2,
						stop = function(self)
							table.insert(stopped_ids, self.id)
						end,
					},
				}
			end

			local count = backend.stop_external()
			assert.equals(0, count)

			vim.lsp.get_clients = orig_get_clients
		end)
	end)

	describe("client_name", function()
		it("returns unrealium-unrealisense", function()
			assert.equals("unrealium-unrealisense", backend.client_name())
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
