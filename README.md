### Installation
Unrealium has dependencies to two plugins - Telescope & Vim-Dispatch (for neovim). Telescope is used for USearch, and Vim-Dispatch is used to execute the various build / run & generate commands. 
```lua
return {
  'jacksonhvisuals/unrealium.nvim',
  dependencies = {
    { 'nvim-telescope/telescope.nvim', dependencies = { 'nvim-lua/plenary.nvim' }, },
    { 'radenling/vim-dispatch-neovim', dependencies = { 'tpope/vim-dispatch' } },
  },
}
```
### Available User Commands
Unrealium will automatically initialize if it detects that the CWD is within a Unreal Project directory. When it initializes,
it will register the following commands.
```
UBuild
URun
UGenProjectFiles
USearch
```

### Project Configuration
In order to use Unrealium, you need to set up a `.unrealium/config.json` file inside your Unreal project folder.
```json
{ 
    "EnginePath" : "/Aboslute/Path/To/Engine/Install/Folder",
    "allowEngineModifications" : true/false,
}
```
`allowEngineModifications` is optional and defaults to false.

