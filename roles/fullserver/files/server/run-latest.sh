#!/bin/bash
GITHUB_REPO="https://raw.githubusercontent.com/Somniac2103/ansible-vps/main/roles/fullserver/files"

SCRIPT_NAME="${SCRIPT_NAME:-backup.sh}"
SCRIPT_PATH="/opt/scripts/${SCRIPT_NAME}"

curl -fsSL "$GITHUB_REPO/$SCRIPT_NAME" -o "$SCRIPT_PATH"
chmod +x "$SCRIPT_PATH"

if [ -f "$SCRIPT_PATH" ]; then
  "$SCRIPT_PATH"
else
  echo "Script $SCRIPT_NAME failed to download or does not exist."
  exit 1
fi

