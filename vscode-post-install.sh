#!/bin/bash

# File to store the current VSCode version
VERSION_FILE="$HOME/.vscode_version"

# Get the current VSCode version
CURRENT_VERSION=$(code-insiders --version | head -2 | tail -1)

# Check if VSCode is running
if ! pgrep -f "Visual Studio Code" > /dev/null
then
    echo "VSCode is not running. Exiting script."
    exit 0
fi

# Check if the version file exists
if [ -f "$VERSION_FILE" ]; then
    # Read the stored version
    STORED_VERSION=$(cat "$VERSION_FILE")
else
    # If the file does not exist, consider it the first run
    STORED_VERSION=""
fi

# Compare versions
if [ "$CURRENT_VERSION" != "$STORED_VERSION" ]; then
    echo "VSCode has been updated."

    # Update the stored version
    echo "$CURRENT_VERSION" > "$VERSION_FILE"

    # Run the AppleScript from wherever you want to keep it
    osascript /Users/willsmith/reload_custom_style.applescript
else
    echo "VSCode is up-to-date."
fi
