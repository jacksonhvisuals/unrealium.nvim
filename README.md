Heavily WIP. Don't even bother.

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
In order to use Unrealium, you need to set up a `.unrealium/config.json` file inside your Unreal project folder. `allowEngineModifications` is optional and defaults to false.
```json
{ 
    "EnginePath" : "/Aboslute/Path/To/Engine/Install/Folder",
    "allowEngineModifications" : true/false,
}
```

