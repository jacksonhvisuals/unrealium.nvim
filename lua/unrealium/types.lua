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
---@field build? { configurations?: string[], presets?: UnrealiumPreset[], output_mode?: string, progress_enabled?: boolean, extra_args?: string[] }
---@field run? { extra_args?: string[] }
---@field debug? { adapter?: string, default_preset?: string, extra_init_commands?: string[], extra_args?: string[] }

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

---@class UnrealiumBuildTarget
---@field name string           e.g. "MyProjectEditor"
---@field file string           path to .Target.cs
---@field type string           "Editor"|"Server"|"Client"|"Game"

---@class UnrealiumPreset
---@field name string           display name, e.g. "MyProjectEditor Linux Development"
---@field target_name string    Target.cs base name
---@field platform string       "Linux"|"Mac"|"Win64"
---@field configuration string  "Development"|"Debug"|"DebugGame"|"Shipping"|"Test"
---@field is_editor boolean
---@field extra_args? string[]

---@class UnrealiumDiagnostic
---@field file string
---@field lnum integer
---@field col? integer
---@field text string
---@field type string           "error"|"warning"

---@class UnrealiumDebugPreset
---@field name string           display name, e.g. "MyProjectEditor (DebugGame)"
---@field target_name string    Target.cs base name
---@field target_type string    "Editor"|"Server"|"Client"|"Game"
---@field configuration string  "Debug"|"DebugGame"|"Development"
