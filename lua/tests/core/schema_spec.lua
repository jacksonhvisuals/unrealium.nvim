---@module 'luassert'

_TEST = true
local schema = require("unrealium.core.schema")

describe("unrealium.core.schema", function()
	describe("validate_value", function()
		it("accepts valid boolean", function()
			local err = schema._validate_value("build.progress", true, { type = "boolean" })
			assert.is_nil(err)
		end)

		it("accepts valid string", function()
			local err = schema._validate_value("logging.level", "info", { type = "string" })
			assert.is_nil(err)
		end)

		it("accepts valid number", function()
			local err = schema._validate_value("build.completion_ttl", 5, { type = "number" })
			assert.is_nil(err)
		end)

		it("rejects wrong type (string instead of boolean)", function()
			local err = schema._validate_value("build.progress", "yes", { type = "boolean" })
			assert.truthy(err)
			assert.matches("expected boolean", err)
			assert.matches("got string", err)
		end)

		it("rejects wrong type (number instead of string)", function()
			local err = schema._validate_value("logging.level", 42, { type = "string" })
			assert.truthy(err)
			assert.matches("expected string", err)
		end)

		it("accepts nil for nilable field", function()
			local err = schema._validate_value("build.default_preset", nil, { type = "string", nilable = true })
			assert.is_nil(err)
		end)

		it("accepts nil for non-nilable field (means using default)", function()
			local err = schema._validate_value("build.progress", nil, { type = "boolean" })
			assert.is_nil(err)
		end)

		it("accepts valid string[]", function()
			local err = schema._validate_value("build.extra_args", { "-foo", "-bar" }, { type = "string[]" })
			assert.is_nil(err)
		end)

		it("accepts empty string[]", function()
			local err = schema._validate_value("build.extra_args", {}, { type = "string[]" })
			assert.is_nil(err)
		end)

		it("rejects string[] with non-string elements", function()
			local err = schema._validate_value("build.extra_args", { "foo", 42 }, { type = "string[]" })
			assert.truthy(err)
			assert.matches("expected string%[%]", err)
		end)

		it("rejects string when string[] expected", function()
			local err = schema._validate_value("build.extra_args", "single", { type = "string[]" })
			assert.truthy(err)
		end)

		it("accepts valid table[]", function()
			local err = schema._validate_value(
				"build.presets",
				{ { name = "a" }, { name = "b" } },
				{ type = "table[]" }
			)
			assert.is_nil(err)
		end)

		it("accepts empty table[]", function()
			local err = schema._validate_value("build.presets", {}, { type = "table[]" })
			assert.is_nil(err)
		end)

		it("rejects table[] with non-table elements", function()
			local err = schema._validate_value("build.presets", { "not a table" }, { type = "table[]" })
			assert.truthy(err)
		end)

		it("accepts valid table for container", function()
			local err = schema._validate_value("build", { progress = true }, { type = "table", children = true })
			assert.is_nil(err)
		end)

		it("rejects non-table for container", function()
			local err = schema._validate_value("build", "wrong", { type = "table", children = true })
			assert.truthy(err)
			assert.matches("expected table", err)
		end)
	end)

	describe("validate_enum", function()
		it("accepts valid enum value", function()
			local entry = { type = "string", enum = { "terminal", "quickfix" } }
			local err = schema._validate_value("build.output_mode", "terminal", entry)
			assert.is_nil(err)
		end)

		it("accepts all valid log levels", function()
			local entry = { type = "string", enum = { "error", "warn", "info", "debug", "trace" } }
			for _, level in ipairs({ "error", "warn", "info", "debug", "trace" }) do
				local err = schema._validate_value("logging.level", level, entry)
				assert.is_nil(err)
			end
		end)

		it("rejects invalid enum value", function()
			local entry = { type = "string", enum = { "terminal", "quickfix" } }
			local err = schema._validate_value("build.output_mode", "popup", entry)
			assert.truthy(err)
			assert.matches("invalid value 'popup'", err)
			assert.matches("terminal", err)
			assert.matches("quickfix", err)
		end)
	end)

	describe("validate_settings", function()
		local defaults = {
			logging = { level = "info" },
			build = {
				configurations = { "Development", "DebugGame", "Debug", "Shipping", "Test" },
				presets = {},
				output_mode = "terminal",
				progress = true,
				completion_ttl = 5,
				extra_args = {},
			},
			run = { default_type = "Development", extra_args = {} },
			search = { exclude_patterns = {} },
			ui = { picker = { prefer = { "snacks", "telescope", "fzf_lua", "native" } } },
			intel = {
				clangd = {
					enabled = true,
					exclusive = false,
					extra_flags = {},
					auto_start = true,
					generate_config = true,
					config_gen = { exclude_paths = {}, extra_compile_flags = {} },
				},
			},
			lint = {},
			generate = {},
			editor_lock = { extra_paths = {} },
			debug = { adapter = "codelldb", extra_init_commands = {}, extra_args = {} },
		}

		it("returns no warnings for valid settings", function()
			local settings = vim.deepcopy(defaults)
			local warnings = schema._validate_settings(settings, defaults)
			assert.equals(0, #warnings)
		end)

		it("warns and sanitizes type mismatch", function()
			local settings = vim.deepcopy(defaults)
			settings.build.progress = "yes"
			local warnings, sanitized = schema._validate_settings(settings, defaults)
			assert.is_true(#warnings > 0)
			assert.equals(true, sanitized.build.progress)
		end)

		it("warns on invalid enum value and restores default", function()
			local settings = vim.deepcopy(defaults)
			settings.build.output_mode = "popup"
			local warnings, sanitized = schema._validate_settings(settings, defaults)
			assert.is_true(#warnings > 0)
			assert.equals("terminal", sanitized.build.output_mode)
		end)

		it("warns on invalid log level", function()
			local settings = vim.deepcopy(defaults)
			settings.logging.level = "verbose"
			local warnings, sanitized = schema._validate_settings(settings, defaults)
			assert.is_true(#warnings > 0)
			assert.equals("info", sanitized.logging.level)
		end)

		it("does not warn for nil nilable fields", function()
			local settings = vim.deepcopy(defaults)
			settings.build.default_preset = nil
			local warnings = schema._validate_settings(settings, defaults)
			-- No warnings for nil on nilable field
			local found = false
			for _, w in ipairs(warnings) do
				if w:match("default_preset") then
					found = true
				end
			end
			assert.is_false(found)
		end)
	end)

	describe("detect_unknown_keys", function()
		it("catches unknown top-level key", function()
			local tbl = { bild = { progress = true } }
			local warnings = schema._detect_unknown_keys(tbl, nil, "")
			assert.is_true(#warnings > 0)
			assert.matches("unknown key 'bild'", warnings[1])
		end)

		it("suggests similar key for typo", function()
			local tbl = { bild = {} }
			local warnings = schema._detect_unknown_keys(tbl, nil, "")
			assert.matches("did you mean 'build'", warnings[1])
		end)

		it("catches unknown nested key", function()
			local tbl = { build = { progres = true } }
			local warnings = schema._detect_unknown_keys(tbl, nil, "")
			assert.is_true(#warnings > 0)
			assert.matches("build%.progres", warnings[1])
		end)

		it("suggests similar nested key", function()
			local tbl = { build = { progres = true } }
			local warnings = schema._detect_unknown_keys(tbl, nil, "")
			assert.matches("did you mean 'build%.progress'", warnings[1])
		end)

		it("skips extension namespaces", function()
			local tbl = { uep = { scan_interval = 5000 } }
			local skip = { uep = true }
			local warnings = schema._detect_unknown_keys(tbl, skip, "")
			assert.equals(0, #warnings)
		end)

		it("passes for valid config", function()
			local tbl = { logging = { level = "debug" }, build = { progress = false } }
			local warnings = schema._detect_unknown_keys(tbl, nil, "")
			assert.equals(0, #warnings)
		end)

		it("handles deeply nested unknown key", function()
			local tbl = { intel = { clangd = { config_gen = { exlude_paths = {} } } } }
			local warnings = schema._detect_unknown_keys(tbl, nil, "")
			assert.is_true(#warnings > 0)
			assert.matches("intel%.clangd%.config_gen%.exlude_paths", warnings[1])
		end)

		it("no false positive for valid deep key", function()
			local tbl = { intel = { clangd = { config_gen = { exclude_paths = {} } } } }
			local warnings = schema._detect_unknown_keys(tbl, nil, "")
			assert.equals(0, #warnings)
		end)
	end)

	describe("suggest_similar", function()
		it("suggests close match", function()
			local result = schema._suggest_similar("progres", { "progress", "presets", "output_mode" })
			assert.equals("progress", result)
		end)

		it("suggests match at distance 1", function()
			local result = schema._suggest_similar("bild", { "build", "run", "search" })
			assert.equals("build", result)
		end)

		it("returns nil for distant keys", function()
			local result = schema._suggest_similar("xyz", { "progress", "presets", "output_mode" })
			assert.is_nil(result)
		end)

		it("returns nil for empty candidates", function()
			local result = schema._suggest_similar("foo", {})
			assert.is_nil(result)
		end)
	end)

	describe("validate_and_sanitize", function()
		local defaults = {
			logging = { level = "info" },
			build = {
				configurations = { "Development" },
				presets = {},
				output_mode = "terminal",
				progress = true,
				completion_ttl = 5,
				extra_args = {},
			},
		}

		it("returns sanitized settings for mixed valid/invalid config", function()
			local settings = vim.deepcopy(defaults)
			settings.build.progress = "yes"

			local user_overrides = { build = { progres = "yes" } }
			local project_config = {}

			local sanitized = schema.validate_and_sanitize(settings, user_overrides, project_config, {}, defaults)
			assert.equals(true, sanitized.build.progress)
		end)

		it("passes through valid settings unchanged", function()
			local settings = vim.deepcopy(defaults)
			local sanitized = schema.validate_and_sanitize(settings, {}, {}, {}, defaults)
			assert.equals("terminal", sanitized.build.output_mode)
			assert.equals(true, sanitized.build.progress)
			assert.equals("info", sanitized.logging.level)
		end)

		it("skips extension namespaces in user overrides", function()
			local settings = vim.deepcopy(defaults)
			settings.uep = { scan_interval = 5000 }
			local user_overrides = { uep = { scan_interval = 5000 } }

			-- Should not warn about "uep" when it's a registered extension
			local sanitized = schema.validate_and_sanitize(settings, user_overrides, {}, { "uep" }, defaults)
			assert.truthy(sanitized)
		end)

		it("warns on unknown keys in project config", function()
			local settings = vim.deepcopy(defaults)
			local project_config = { EnginePath = "/path", allowEngineModifications = false }

			-- These are now unknown keys (no longer legacy-skipped)
			local sanitized = schema.validate_and_sanitize(settings, {}, project_config, {}, defaults)
			assert.truthy(sanitized)
		end)
	end)

	describe("validate_key", function()
		it("returns nil for valid key-value", function()
			local warning = schema.validate_key("build.progress", true)
			assert.is_nil(warning)
		end)

		it("returns warning for invalid type", function()
			local warning = schema.validate_key("build.progress", "yes")
			assert.truthy(warning)
			assert.matches("expected boolean", warning)
		end)

		it("returns warning for invalid enum", function()
			local warning = schema.validate_key("logging.level", "verbose")
			assert.truthy(warning)
			assert.matches("invalid value", warning)
		end)

		it("returns nil for unknown key (may be extension)", function()
			local warning = schema.validate_key("uep.scan_interval", 5000)
			assert.is_nil(warning)
		end)

		it("returns nil for valid enum value", function()
			local warning = schema.validate_key("build.output_mode", "quickfix")
			assert.is_nil(warning)
		end)
	end)
end)
