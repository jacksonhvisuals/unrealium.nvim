if 1 ~= vim.fn.has("nvim-0.10.0") then
	vim.api.nvim_echo({ { "Unrealium requires at least nvim-0.10.0" } }, true, {})
	return
end

-- Ensure that Unrealium hasn't already initialized
if vim.g.unrealium_loaded == 1 then
	return
end
vim.g.unrealium_loaded = 1
