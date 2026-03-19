---@module 'luassert'

_TEST = true

describe("core.snippets (scanning)", function()
	local snippets

	before_each(function()
		package.loaded["unrealium.modules.snippets"] = nil
		snippets = require("unrealium.modules.snippets")
	end)

	describe("scan_lines", function()
		it("extracts UE_LOG categories", function()
			local lines = {
				'UE_LOG(LogMyGame, Warning, TEXT("something"));',
				'UE_LOG(LogTemp, Log, TEXT("debug"));',
				'UE_LOG(LogMyGame, Error, TEXT("oops"));',
			}
			local result = snippets._scan_lines(lines)
			assert.equals(2, result["LogMyGame"])
			assert.equals(1, result["LogTemp"])
		end)

		it("extracts UE_LOGFMT categories", function()
			local lines = {
				'UE_LOGFMT(LogNet, Warning, "packet lost {Id}", Id);',
			}
			local result = snippets._scan_lines(lines)
			assert.equals(1, result["LogNet"])
		end)

		it("extracts both UE_LOG and UE_LOGFMT from mixed content", function()
			local lines = {
				'UE_LOG(LogMyGame, Log, TEXT("hello"));',
				'UE_LOGFMT(LogMyGame, Warning, "structured {Val}", Val);',
				'UE_LOG(LogTemp, Error, TEXT("temp"));',
			}
			local result = snippets._scan_lines(lines)
			assert.equals(2, result["LogMyGame"])
			assert.equals(1, result["LogTemp"])
		end)

		it("returns empty table for no matches", function()
			local lines = {
				"// just a comment",
				"int x = 42;",
			}
			local result = snippets._scan_lines(lines)
			assert.same({}, result)
		end)

		it("ignores commented-out log calls", function()
			-- scan_lines doesn't parse comments — it still matches
			-- This documents the behavior: comment stripping is not implemented
			local lines = {
				'// UE_LOG(LogTemp, Log, TEXT("commented"));',
			}
			local result = snippets._scan_lines(lines)
			assert.equals(1, result["LogTemp"])
		end)

		it("handles multiple categories on one line", function()
			-- Unusual but possible in macros or preprocessor expansions
			local lines = {
				'UE_LOG(LogA, Log, TEXT("a")); UE_LOG(LogB, Warning, TEXT("b"));',
			}
			local result = snippets._scan_lines(lines)
			assert.equals(1, result["LogA"])
			assert.equals(1, result["LogB"])
		end)
	end)

	describe("rank_categories", function()
		it("ranks by frequency descending", function()
			local freq = { LogMyGame = 5, LogTemp = 1, LogNet = 3 }
			local ranked = snippets._rank_categories(freq)
			assert.equals("LogMyGame", ranked[1])
			assert.equals("LogNet", ranked[2])
			assert.equals("LogTemp", ranked[3])
		end)

		it("uses alphabetical tiebreak", function()
			local freq = { LogAlpha = 2, LogBeta = 2, LogGamma = 2 }
			local ranked = snippets._rank_categories(freq)
			assert.equals("LogAlpha", ranked[1])
			assert.equals("LogBeta", ranked[2])
			assert.equals("LogGamma", ranked[3])
		end)

		it("returns empty for empty input", function()
			local ranked = snippets._rank_categories({})
			assert.equals(0, #ranked)
		end)
	end)

	describe("merge_frequencies", function()
		it("sums counts from both tables", function()
			local a = { LogMyGame = 3, LogTemp = 1 }
			local b = { LogMyGame = 2, LogNet = 5 }
			local merged = snippets._merge_frequencies(a, b)
			assert.equals(5, merged["LogMyGame"])
			assert.equals(1, merged["LogTemp"])
			assert.equals(5, merged["LogNet"])
		end)

		it("handles empty first table", function()
			local merged = snippets._merge_frequencies({}, { LogTemp = 3 })
			assert.equals(3, merged["LogTemp"])
		end)

		it("handles empty second table", function()
			local merged = snippets._merge_frequencies({ LogTemp = 3 }, {})
			assert.equals(3, merged["LogTemp"])
		end)

		it("handles both empty", function()
			local merged = snippets._merge_frequencies({}, {})
			assert.same({}, merged)
		end)
	end)
end)
