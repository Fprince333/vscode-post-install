-- Open Visual Studio Code
tell application "Visual Studio Code - Insiders"
    activate
end tell

-- Wait for VSCode to open (adjust the delay if necessary)
delay 3

-- Use AppleScript to simulate the keystrokes for opening the command palette
tell application "System Events"
    keystroke "p" using {command down, shift down}
    delay 0.5
    keystroke "Enable Neon Dreams"
    delay 0.5
    keystroke return
    keystroke "p" using {command down, shift down}
    delay 0.5
    keystroke "Reload Custom CSS and JS"
    delay 0.5
    keystroke return
    delay 0.5
    keystroke "r" using {command down}
end tell
