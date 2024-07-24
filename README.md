# Visual Studio Code - Post Install
Auto-run commands after VS Code updates

https://github.com/user-attachments/assets/8c10a8b3-303c-4169-8c1b-94701aeb0f81

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

<p align="center"><img src="https://github-production-user-asset-6210df.s3.amazonaws.com/1648240/339787019-2593fe28-9a0f-4d68-884b-afd3b6259794.gif?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAVCODYLSA53PQK4ZA%2F20240614%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20240614T134726Z&X-Amz-Expires=300&X-Amz-Signature=d513683ef498058394e93b230d389fb158ade3eaaf6c349c99fc8bfc2c81f7fa&X-Amz-SignedHeaders=host&actor_id=1648240&key_id=0&repo_id=815147224" alt="That's...that's about it." width="80%" /></p>

