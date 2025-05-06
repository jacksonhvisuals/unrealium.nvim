# IDE Actions
ULM or UDE will be the namespace
so actions will be called ULM.ActionName

We will have base actions like:
1. GenerateProjectFiles
2. Build
3. Setup
4. Run
5. Debug

And we (maybe?) also provide a UI interface for it all (see how Lazy supplies an interface, perhaps?).

### Setup functionality
1. Attempt to intelligently parse where the the UnrealEditor lives. (.vscode folder, Makefile, finally, XDG_ROOT Epic engine association)
2. If we're missing that, prompt the user to put in the path.
3. If no config, offer to create one.

### Commands by UE
Running "Generate Visutal Studio Code Project" in UE equates to:
`$UNREAL_ROOT_PATH/Engine/Build/BatchFiles/Linux/Build.sh -projectfiles -project="$PATH_TO_UPROJECT" -game -engine -progress`

Running the "Development Editor" configuration from Rider equates to:
`$UNREAL_ROOT_PATH/Engine/Build/BatchFiles/Linux/Build.sh LinuxPluginDevEditor Linux Development -Project="PROJECT DIR" -buildscw`
and then
`$EDITOR_PATH $PROJECT_PATH`

