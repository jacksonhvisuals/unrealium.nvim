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
	local module_api = snippets.get_module_api(context.bufnr)

	local kind = vim.lsp.protocol.CompletionItemKind.Snippet

	local items = {
		{
			label = "ULOG",
			kind = kind,
			insertTextFormat = 2,
			insertText = snippets.build_uelog_snippet(categories),
			documentation = {
				kind = "markdown",
				value = "UE_LOG macro with discovered log categories",
			},
		},
		{
			label = "ULOGFMT",
			kind = kind,
			insertTextFormat = 2,
			insertText = snippets.build_uelogfmt_snippet(categories),
			documentation = {
				kind = "markdown",
				value = "UE_LOGFMT structured logging macro with discovered log categories",
			},
		},
		{
			label = "UENUM",
			kind = kind,
			insertTextFormat = 2,
			insertText = snippets.build_uenum_snippet(),
			documentation = {
				kind = "markdown",
				value = "UENUM declaration with BlueprintType and UMETA display names",
			},
		},
		{
			label = "USTRUCT",
			kind = kind,
			insertTextFormat = 2,
			insertText = snippets.build_ustruct_snippet(),
			documentation = {
				kind = "markdown",
				value = "USTRUCT with GENERATED_BODY() and a UPROPERTY member",
			},
		},
		{
			label = "UCLASS",
			kind = kind,
			insertTextFormat = 2,
			insertText = snippets.build_uclass_snippet(module_api),
			documentation = {
				kind = "markdown",
				value = "UCLASS with MODULE_API (auto-detected from *.Build.cs), parent class choices, and mirrored constructor",
			},
		},
		{
			label = "UINTERFACE",
			kind = kind,
			insertTextFormat = 2,
			insertText = snippets.build_uinterface_snippet(module_api),
			documentation = {
				kind = "markdown",
				value = "UINTERFACE with U-prefixed UObject class and I-prefixed abstract interface (names mirrored)",
			},
		},
		{
			label = "UCAST",
			kind = kind,
			insertTextFormat = 2,
			insertText = snippets.build_ucast_snippet(),
			documentation = {
				kind = "markdown",
				value = "Cast<TargetClass>(Source) with mirrored type name",
			},
		},
		{
			label = "UFUNCTION",
			kind = kind,
			insertTextFormat = 2,
			insertText = snippets.build_ufunction_snippet(),
			documentation = {
				kind = "markdown",
				value = "UFUNCTION macro with common specifier choices",
			},
		},
		{
			label = "UPROPERTY",
			kind = kind,
			insertTextFormat = 2,
			insertText = snippets.build_uproperty_snippet(),
			documentation = {
				kind = "markdown",
				value = "UPROPERTY macro with visibility, Blueprint access, and category",
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
