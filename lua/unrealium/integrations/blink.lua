--- blink.cmp custom source for UE_LOG / UE_LOGFMT snippets.
--- Register in blink.cmp config as:
---   sources = { providers = { unrealium = { module = "unrealium.integrations.blink" } } }

local source = {}

function source.new(opts)
	return setmetatable({}, { __index = source })
end

function source:enabled()
	local ft = vim.bo.filetype
	if ft ~= "cpp" and ft ~= "c" then
		return false
	end
	local ok, config = pcall(require, "unrealium.core.config")
	if not ok then
		return false
	end
	local cfg = config.get()
	if not cfg then
		return false
	end
	if cfg.settings and cfg.settings.snippets and cfg.settings.snippets.enabled == false then
		return false
	end
	return true
end

function source:get_completions(context, callback)
	local snippets = require("unrealium.modules.snippets")
	local categories = snippets.get_categories(context.bufnr)

	local items = {
		{
			label = "ULOG",
			kind = vim.lsp.protocol.CompletionItemKind.Snippet,
			insertTextFormat = 2, -- Snippet
			insertText = snippets.build_uelog_snippet(categories),
			documentation = {
				kind = "markdown",
				value = "UE_LOG macro with discovered log categories",
			},
		},
		{
			label = "ULOGFMT",
			kind = vim.lsp.protocol.CompletionItemKind.Snippet,
			insertTextFormat = 2, -- Snippet
			insertText = snippets.build_uelogfmt_snippet(categories),
			documentation = {
				kind = "markdown",
				value = "UE_LOGFMT structured logging macro with discovered log categories",
			},
		},
	}

	callback({
		is_incomplete_forward = false,
		is_incomplete_backward = false,
		items = items,
	})
end

return source
