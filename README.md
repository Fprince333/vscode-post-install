# Visual Studio Code Insiders post-install

Reapply local workbench CSS after a VS Code Insiders update, quit it completely, and reopen it through macOS Launch Services.

VS Code Insiders updates replace the application bundle and its workbench CSS. A VS Code user task runs this workflow when a folder opens, but the script only changes the app when the Insiders build identifier differs from the last successful run.

## How it works

The workflow changes this application resource:

```text
/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/out/vs/workbench/workbench.desktop.main.css
```

It replaces everything after VS Code's source-map footer with one marked custom CSS block, asks Insiders to quit by its bundle identity, waits up to 60 seconds for all bundle processes to stop, and reopens it with:

```bash
/usr/bin/open -b com.microsoft.VSCodeInsiders
```

The script deliberately does not re-sign the app or modify `product.json`. Re-signing changes the application's code identity and causes macOS to request access to the existing `Code - Insiders Safe Storage` keychain item. Keeping Microsoft's original designated identity avoids that password prompt.

Because the CSS is intentionally modified, `codesign --verify --deep --strict` reports `a sealed resource is missing or invalid`. For an already installed Insiders app, that diagnostic does not prevent Launch Services from reopening it. Insiders updates restore the original Microsoft-sealed bundle and overwrite the customization, which is why the task runs again after each update.

## Requirements

- macOS with VS Code Insiders installed in `/Applications`
- The `code-insiders` shell command on `PATH`
- A custom stylesheet at `$HOME/source.css`, [Synthwave '84](https://marketplace.visualstudio.com/items?itemName=RobbOwen.synthwave-vscode), or another CSS file supplied through `CUSTOM_CSS_FILE`
- The workbench CSS file must be writable by the current user; the automatic workflow refuses to request an administrator password

The script uses `CUSTOM_CSS_FILE` when set, then `$HOME/source.css` when present. Otherwise, it locates Synthwave '84 with `code-insiders --locate-extension` and applies its `src/css/editor_chrome.css`.

## Setup

1. Keep `vscode-post-install.sh` and `quit_vscode_insiders.applescript` together. For the included task, copy both files to your home directory:

   ```bash
   cp vscode-post-install.sh quit_vscode_insiders.applescript "$HOME/"
   chmod +x "$HOME/vscode-post-install.sh"
   ```

2. Copy `tasks.json` to the VS Code Insiders user directory:

   ```bash
   cp tasks.json "$HOME/Library/Application Support/Code - Insiders/User/tasks.json"
   ```

   If that file already exists, merge only the `Run Post-Install` task into its existing `tasks` array. The task uses `${env:HOME}`, so it does not contain a hard-coded username.

3. Enable automatic tasks. Run `Tasks: Manage Automatic Tasks` from the Command Palette and choose `Allow Automatic Tasks`, or add:

   ```json
   "task.allowAutomaticTasks": "on"
   ```

The build marker is written to `$HOME/.vscode_version` only after the complete quit/relaunch workflow succeeds. A failed run is retried the next time the task starts.

## Configuration

- `CUSTOM_CSS_FILE`: CSS file to apply instead of `$HOME/source.css` or Synthwave '84's stylesheet
- `VSCODE_INSIDERS_APP`: alternate Insiders application path
- `CODE_INSIDERS_BIN`: alternate `code-insiders` executable
- `VSCODE_POST_INSTALL_VERSION_FILE`: alternate successful-build marker
- `VSCODE_POST_INSTALL_LOG_FILE`: alternate log file; default `$HOME/Library/Logs/vscode-post-install.log`
- `SHUTDOWN_TIMEOUT_SECONDS`: quit timeout; default `60`
- `RELAUNCH_TIMEOUT_SECONDS`: relaunch timeout; default `30`

Normal runs remain update-gated. Use `--force` for a manual repair or end-to-end check. Forced recovery also works when Insiders is already stopped:

```bash
"$HOME/vscode-post-install.sh" --force
```

## Viewing logs and errors

Every status and error message is shown in the task terminal and appended to this durable log:

```text
$HOME/Library/Logs/vscode-post-install.log
```

The file is the most reliable place to diagnose an automatic run because the workflow quits VS Code, which can discard the integrated task terminal's visible history. Show the latest messages in any terminal with:

```bash
tail -n 100 "$HOME/Library/Logs/vscode-post-install.log"
```

Follow a run live with:

```bash
tail -f "$HOME/Library/Logs/vscode-post-install.log"
```

Inside VS Code, open **View → Terminal** or press **Control-`**, then select the terminal associated with **Run Post-Install** from the terminal list. The task uses `"reveal": "silent"`, which controls whether VS Code brings the panel forward; do not rely on that terminal as saved history across the full app restart.

For a manual diagnostic run, execute the script with `--force`. The same messages appear in that terminal and in the log file:

```bash
"$HOME/vscode-post-install.sh" --force
```

Errors are prefixed with `vscode-post-install: ERROR:`. The successful build marker is not updated when an error occurs, so the next automatic run retries the workflow.

## Troubleshooting

Confirm that exactly one custom CSS block is installed:

```bash
grep -c 'vscode-post-install:custom-css:start' "/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/out/vs/workbench/workbench.desktop.main.css"
```

Confirm that Microsoft's stable designated identity is still embedded:

```bash
codesign -d -r- "/Applications/Visual Studio Code - Insiders.app" 2>&1
```

Confirm that no Insiders processes remain after shutdown:

```bash
pgrep -afil '^/Applications/Visual Studio Code - Insiders.app/Contents/'
```

If the script reports that the workbench source-map footer is missing, VS Code's internal layout has changed. Do not append CSS blindly; update the target logic for that Insiders build. Reinstalling or updating VS Code Insiders restores the original Microsoft bundle and removes the customization.
