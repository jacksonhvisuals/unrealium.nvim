---@class EngineScripts
---@field Build string
---@field GenerateProjectFiles string
---@field RunUBT string
---@field EditorBase string The UnrealEditor binary path (suffixes appended for build targets)

---@class EngineConfig
---@field Folder string
---@field Scripts EngineScripts
---@field AllowEngineModifications boolean

---@class ProjectConfig
---@field Folder string
---@field FullPath string
---@field Name string

---@class UnrealiumConfig
---@field Project ProjectConfig
---@field Engine EngineConfig
---@field PlatformName string

---@class UnrealiumUserConfig
---@field engine? { folder?: string, allow_modifications?: boolean }
---@field logging? { level?: string }
---@field ui? { picker?: { prefer?: string[] } }

---@class UnrealiumModule
---@field name string
---@field commands? table<string, UnrealiumCommandSpec>
---@field setup? fun(config: UnrealiumConfig)

---@class UnrealiumCommandSpec
---@field handler fun(opts: table)
---@field desc string
---@field args? UnrealiumArgSpec[]
---@field subcommands? table<string, UnrealiumCommandSpec>

---@class UnrealiumArgSpec
---@field name string
---@field complete? string[]|fun(): string[]
