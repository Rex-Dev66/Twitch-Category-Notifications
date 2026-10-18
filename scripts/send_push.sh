#!/bin/bash
# Usage: send_push.sh "Title" "Body"
# Reads the Pushbullet access token from a private file, never from this script.

API_TOKEN="$(cat "$HOME/.config/pushbullet/token")"
TITLE="$1"
BODY="$2"

curl -s -u "$API_TOKEN:" https://api.pushbullet.com/v2/pushes \
  -d type=note \
  --data-urlencode title="$TITLE" \
  --data-urlencode body="$BODY"
