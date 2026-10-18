#!/bin/bash
# Forwards every desktop notification to Pushbullet

# TODO: set this to the folder where you saved send_push.sh
PUSH_SCRIPT="$HOME/YOUR_FOLDER/send_push.sh"

capture=0
string_count=0
APP=""
TITLE=""
BODY=""

dbus-monitor "interface='org.freedesktop.Notifications'" |
while read -r line; do
  # A new Notify call starts a new notification
  if echo "$line" | grep -q "method call.*Notify"; then
    capture=1; string_count=0; APP=""; TITLE=""; BODY=""
    continue
  fi

  if [ $capture -eq 1 ] && echo "$line" | grep -q 'string "'; then
    text=$(echo "$line" | sed -n 's/.*string "\(.*\)"/\1/p')
    string_count=$((string_count + 1))

    # String order in a Notify call: 1 = app_name, 2 = icon, 3 = summary, 4 = body
    case $string_count in
      1) APP="$text" ;;
      3) TITLE="$text" ;;
      4) BODY="$text"
         capture=0
         # Skip Pushbullet's own notifications to avoid a loop
         case "$APP" in *"PB for Desktop"*|*ushbullet*) continue ;; esac
         if [ -n "$TITLE" ] || [ -n "$BODY" ]; then
           echo "Sending: $TITLE -- $BODY"
           "$PUSH_SCRIPT" "$TITLE" "$BODY"
         fi ;;
    esac
  fi
done
