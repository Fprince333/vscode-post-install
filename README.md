# Visual Studio Code - Post Install
Auto-run commands after VS Code updates

## Why would I need this?
If your VS Code theme requires settings to be re-enabled after an update, manually triggering the Command Palette can get tiresome. We can avoid this by leveraging 
- [Tasks in Visual Studio Code](https://code.visualstudio.com/Docs/editor/tasks)
- [AppleScript](https://developer.apple.com/library/archive/documentation/AppleScript/Conceptual/AppleScriptLangGuide/introduction/ASLR_intro.html)
- [Bash Scripting](https://www.gnu.org/savannah-checkouts/gnu/bash/manual/bash.html)

## How do I do it?
1. Copy ```vscode-post-install.sh``` and paste it somewhere you won't forget (e.g. your `$HOME` directory)
2. Copy ```reload_custom_stuff.applescript``` and paste it in the same place you put your shell script above. Or wherever you want to put it, but it's nice to keep things together.
3. Copy ```tasks.json``` and paste it into your VS Code's `User` directory. 
   - In my case, it's `/Users/willsmith/Library/Application Support/Code - Insiders/User`. 
   - If you already have this file and you want to keep what's in there, only copy the task and paste it into the array of ```"tasks"```
    ```
    "tasks": [
      {...someTask},
      {...someOtherTask},
      {
        "label": "Run Post-Install",
        "type": "shell",
        "command": "/Users/willsmith/vscode-post-install.sh",
        "presentation": {
          "reveal": "never",
          "panel": "shared"
        },
        "runOptions": {
          "runOn": "folderOpen"
        },
        "problemMatcher": []
      }
    ]
    ```
4. Modify whatever you want to modify to fit your needs
5. Enable automatic tasks in VS Code by either
   1. Opening the Command Palette [Cmd–Shift–P] and selecting `Tasks: Manage Automatic Tasks`, then `Allow Automatic Tasks`
   2. Opening `settings.json` and adding ```"task.allowAutomaticTasks": "on"```

That's about it
