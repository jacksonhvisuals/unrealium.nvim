--- Declarative command builder. Creates :UE with subcommands and tab completion.

local M = {}

--- Flatten a command spec tree into a lookup table keyed by subcommand path.
--- Example: { build = { handler = fn } } → { ["build"] = spec }
--- Nested: { generate = { subcommands = { ["project-files"] = { handler = fn } } } }
---   → { ["generate project-files"] = spec }
---@param spec table<string, UnrealiumCommandSpec>
---@param prefix? string
---@return table<string, UnrealiumCommandSpec> flat
local function flatten(spec, prefix)
	local result = {}
	prefix = prefix or ""

	for name, cmd in pairs(spec) do
		local path = prefix == "" and name or (prefix .. " " .. name)
		if cmd.subcommands then
			-- This node has subcommands; merge them in
			local nested = flatten(cmd.subcommands, path)
			for k, v in pairs(nested) do
				result[k] = v
			end
			-- Also register this node if it has a handler
			if cmd.handler then
				result[path] = cmd
			end
		else
			result[path] = cmd
		end
	end

	return result
end

--- Build completion function for a command spec tree.
---@param subcommands table<string, UnrealiumCommandSpec>
---@return fun(arg_lead: string, cmd_line: string, cursor_pos: integer): string[]
local function build_completer(subcommands)
	local flat = flatten(subcommands)

	return function(_, cmd_line, _)
		local parts = vim.split(cmd_line, "%s+")
		-- Remove the command name (e.g., "UE")
		table.remove(parts, 1)

		local results = {}

		-- Try to match progressively longer subcommand paths
		local matched_path = ""
		local matched_depth = 0

		for i = 1, #parts do
			local try_path = table.concat(parts, " ", 1, i)
			if flat[try_path] or has_prefix(flat, try_path) then
				matched_path = try_path
				matched_depth = i
			end
		end

		-- If we have a matched command with args, complete args
		local cmd = flat[matched_path]
		if cmd and cmd.args then
			local arg_index = #parts - matched_depth
			if arg_index >= 1 and arg_index <= #cmd.args then
				local arg_spec = cmd.args[arg_index]
				local completions = {}
				if type(arg_spec.complete) == "function" then
					completions = arg_spec.complete()
				elseif type(arg_spec.complete) == "table" then
					completions = arg_spec.complete
				end

				local partial = parts[#parts] or ""
				for _, c in ipairs(completions) do
					if vim.startswith(c, partial) then
						table.insert(results, c)
					end
				end
				return results
			end
		end

		-- Otherwise, complete subcommand names
		local prefix = #parts > 0 and table.concat(parts, " ", 1, #parts - 1) or ""
		local partial = parts[#parts] or ""

		-- Find all direct children of the current prefix
		for path, _ in pairs(flat) do
			local candidate
			if prefix == "" then
				-- Top-level: only show first word
				candidate = vim.split(path, " ")[1]
			else
				-- Nested: show next word after prefix
				if vim.startswith(path, prefix .. " ") then
					local rest = path:sub(#prefix + 2)
					candidate = vim.split(rest, " ")[1]
				end
			end

			if candidate and vim.startswith(candidate, partial) then
				-- Deduplicate
				local found = false
				for _, r in ipairs(results) do
					if r == candidate then
						found = true
						break
					end
				end
				if not found then
					table.insert(results, candidate)
				end
			end
		end

		-- Also check top-level subcommand keys for unmatched prefix
		if prefix == "" then
			for name, _ in pairs(subcommands) do
				if vim.startswith(name, partial) then
					local found = false
					for _, r in ipairs(results) do
						if r == name then
							found = true
							break
						end
					end
					if not found then
						table.insert(results, name)
					end
				end
			end
		end

		table.sort(results)
		return results
	end
end

--- Check if any key in a table starts with a given prefix.
---@param tbl table
---@param prefix string
---@return boolean
function has_prefix(tbl, prefix)
	for k, _ in pairs(tbl) do
		if vim.startswith(k, prefix .. " ") then
			return true
		end
	end
	return false
end

--- Create a vim user command from a declarative spec.
---@param opts { name: string, subcommands: table<string, UnrealiumCommandSpec> }
function M.create(opts)
	local flat = flatten(opts.subcommands)
	local completer = build_completer(opts.subcommands)

	vim.api.nvim_create_user_command(opts.name, function(cmd_opts)
		local args = cmd_opts.fargs

		-- Try to match the longest subcommand path
		local best_path = nil
		local best_depth = 0

		for i = #args, 1, -1 do
			local try_path = table.concat(args, " ", 1, i)
			if flat[try_path] and flat[try_path].handler then
				best_path = try_path
				best_depth = i
				break
			end
		end

		if best_path then
			local remaining_args = {}
			for i = best_depth + 1, #args do
				table.insert(remaining_args, args[i])
			end
			flat[best_path].handler({
				args = remaining_args,
				fargs = cmd_opts.fargs,
				bang = cmd_opts.bang,
			})
		else
			-- Show help: list available subcommands
			local names = {}
			for name, _ in pairs(opts.subcommands) do
				table.insert(names, name)
			end
			table.sort(names)
			vim.notify(
				"Usage: :" .. opts.name .. " <subcommand>\nAvailable: " .. table.concat(names, ", "),
				vim.log.levels.INFO
			)
		end
	end, {
		nargs = "*",
		complete = completer,
		desc = "Unrealium Engine commands",
	})
end

--- Add subcommands to an existing spec table (for extension modules).
---@param target table<string, UnrealiumCommandSpec>
---@param namespace string
---@param commands table<string, UnrealiumCommandSpec>
function M.add_subcommands(target, namespace, commands)
	if not target[namespace] then
		target[namespace] = { subcommands = {} }
	end
	if not target[namespace].subcommands then
		target[namespace].subcommands = {}
	end
	for name, spec in pairs(commands) do
		target[namespace].subcommands[name] = spec
	end
end

if _TEST then
	M._flatten = flatten
	M._build_completer = build_completer
end

return M
