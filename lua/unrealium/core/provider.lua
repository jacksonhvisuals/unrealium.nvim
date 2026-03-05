--- Capability registry: register/resolve pattern with priority.

local M = {}

---@class UnrealiumProvider
---@field name string
---@field impl any
---@field priority? number Higher wins (default 0)

---@type table<string, UnrealiumProvider[]>
local _registry = {}

--- Register a capability provider.
---@param capability string e.g. "class_introspection"
---@param provider { name: string, impl: any, priority?: number }
function M.register(capability, provider)
	if not _registry[capability] then
		_registry[capability] = {}
	end
	provider.priority = provider.priority or 0
	table.insert(_registry[capability], provider)
	-- Sort by priority descending
	table.sort(_registry[capability], function(a, b)
		return (a.priority or 0) > (b.priority or 0)
	end)
end

--- Resolve the highest-priority provider for a capability.
---@param capability string
---@return any|nil impl The implementation, or nil if none registered
function M.resolve(capability)
	local providers = _registry[capability]
	if providers and #providers > 0 then
		return providers[1].impl
	end
	return nil
end

--- List all providers for a capability.
---@param capability string
---@return UnrealiumProvider[]
function M.list(capability)
	return _registry[capability] or {}
end

--- Clear all registrations (useful for testing).
function M.clear()
	_registry = {}
end

if _TEST then
	M._registry = function()
		return _registry
	end
end

return M
