# Phone Notifications for Twitch Categories Using Pushbullet

Oct 18, 2026 · @Rex

## Overview

This setup sends a push to your phone whenever a Twitch streamer you follow goes live in a category you care about, or when a category you watch has Drops enabled. It chains three small pieces on a Linux desktop:

1. **twitch-game-notify** polls the Twitch Helix API every few seconds and raises a normal desktop notification (via D-Bus) when a match is found.
2. **notify-listener.sh** watches the D-Bus `org.freedesktop.Notifications` interface with `dbus-monitor` and grabs the title and body of every notification.
3. **send\_push.sh** forwards that title and body to the Pushbullet API with `curl`, so it lands on your phone.

**PB for Desktop** (an unofficial Pushbullet desktop client) is optional. It handles the reverse direction: phone notifications showing up on Linux.

```
Twitch API --> twitch-game-notify --> D-Bus notification --> notify-listener.sh --> send_push.sh --> Pushbullet --> phone
```

Since the listener forwards **every** desktop notification, not only Twitch ones, you also get a general "mirror my desktop notifications to my phone" tool.

## Prerequisites

You need a Debian-based desktop with a running notification daemon, Python 3, and two free accounts. Tested on Parrot OS (Debian-based) with Python 3.13.

| Item | What it's for | Where to get it |
| --- | --- | --- |
| `curl`, `dbus` (`dbus-monitor`) | Sending pushes, listening for notifications | Usually preinstalled |
| `libnotify-bin` | `notify-send`, for testing | `sudo apt install libnotify-bin` |
| `python3-notify2`, `python3-gi`, `python3-venv` | twitch-game-notify's D-Bus notifications and tray icon | `sudo apt install python3-notify2 python3-gi python3-venv` |
| Pushbullet account + Access Token | Sending pushes to your phone | [pushbullet.com](https://www.pushbullet.com) → Settings → Account → Create Access Token |
| Pushbullet app on your phone | Receiving the pushes | Play Store / App Store |
| Twitch application (Client ID + Client Secret) | Querying the Twitch API | [dev.twitch.tv/console/apps](https://dev.twitch.tv/console/apps) → Register Your Application (OAuth redirect `http://localhost`, category "Application Integration") |
| PB for Desktop (optional) | Seeing phone notifications on Linux | [sidneys/pb-for-desktop releases](https://github.com/sidneys/pb-for-desktop/releases) (`.deb`) |

Your Pushbullet token and Twitch secret are passwords. Keep them out of scripts you share, and out of git. Part 1 and Part 2 show how.

## Part 1: Forward desktop notifications to Pushbullet

Two Bash scripts do the work: one sends a push, the other listens on D-Bus and calls the first. Put both in a folder such as `~/Prog/PB_FOR_LINUX`.

### Step 1: Store your Pushbullet token outside the script

```bash
mkdir -p ~/.config/pushbullet
printf '%s' 'PASTE_YOUR_ACCESS_TOKEN_HERE' > ~/.config/pushbullet/token
chmod 600 ~/.config/pushbullet/token
```

The `chmod 600` makes the file readable only by you.

### Step 2: Create `send_push.sh`

```bash
#!/bin/bash
# Usage: send_push.sh "Title" "Body"

API_TOKEN="$(cat "$HOME/.config/pushbullet/token")"
TITLE="$1"
BODY="$2"

curl -s -u "$API_TOKEN:" https://api.pushbullet.com/v2/pushes \
  -d type=note \
  --data-urlencode title="$TITLE" \
  --data-urlencode body="$BODY"
```

`-u "TOKEN:"` sends the token as the HTTP Basic username with an empty password, which is what the Pushbullet API expects. `--data-urlencode` keeps titles with `&` or `=` from breaking the request.

### Step 3: Create `notify-listener.sh`

```bash
#!/bin/bash
# Forwards every desktop notification to Pushbullet

PUSH_SCRIPT="$HOME/Prog/PB_FOR_LINUX/send_push.sh"

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
```

The `Notify` D-Bus call carries its arguments in a fixed order. Counting only `string` lines skips the numeric `replaces_id`, so the 3rd string is the title and the 4th is the body.

### Step 4: Make them executable and test

```bash
chmod +x ~/Prog/PB_FOR_LINUX/*.sh

# Test the push on its own
~/Prog/PB_FOR_LINUX/send_push.sh "Hello" "Test from Linux"

# Test the full chain: start the listener, then fire a notification from a second terminal
~/Prog/PB_FOR_LINUX/notify-listener.sh
notify-send "Listener test" "This should reach your phone"
```

### Optional: PB for Desktop

To see phone notifications on Linux too, install the client and sign in:

```bash
sudo apt install ./pb-for-desktop-11.0.2-amd64.deb
```

## Part 2: Twitch game notifications

[twitch-game-notify](https://github.com/mwiens91/twitch-game-notify) by mwiens91 raises a desktop notification when a streamer you follow is live in a category you choose. Once Part 1's listener is running, every one of those notifications also goes to your phone.

### Step 1: Clone and set up a virtual environment

```bash
cd ~/Prog
git clone https://github.com/mwiens91/twitch-game-notify.git
cd twitch-game-notify

# --system-site-packages lets the venv use the apt-installed notify2 and PyGObject
python3 -m venv --system-site-packages myenv
myenv/bin/pip install requests PyYAML schema
```

The pinned versions in `requirements.txt` are old and some won't build on Python 3.13. Installing the three pure-Python packages and taking `notify2`, `dbus-python` and `PyGObject` from apt avoids compiling anything.

### Step 2: Create `config.yaml`

```bash
cp config.yaml.example config.yaml
chmod 600 config.yaml
```

The repo's `.gitignore` already excludes `config.yaml`, so real secrets go there and never in `config.yaml.example`. Edit it:

```yaml
# How often to query Twitch, in seconds (limit: 30 queries/minute per client)
query-period: 3

# From dev.twitch.tv/console/apps
twitch-api-client-id: "YOUR_CLIENT_ID"
twitch-api-client-secret: "YOUR_CLIENT_SECRET"

# Streamer login names and the categories to notify about
streamers:
  "some_streamer":
    include:
      - "*"                 # any category...
    exclude:
      - "Just Chatting"     # ...except these
      - "Special Events"

ignore-502-errors-one-shot: false
ignore-502-errors-persistant: true
```

The app also looks for the file at `~/.config/twitch-game-notify/config.yaml`, which keeps it out of the repo folder entirely.

### Step 3: Test it

```bash
# One-shot, print to terminal: checks your credentials and config
myenv/bin/python run_twitchgamenotify.py --one-shot --print-to-terminal

# Normal mode: runs in the tray and sends desktop notifications
myenv/bin/python run_twitchgamenotify.py
```

Run `--help` to confirm flag names on your copy.

### Optional: Watch categories for Twitch Drops

I extended my copy to also alert when any live stream in a chosen category has Drops enabled. This is a local change, not part of the upstream project. The core of it is a new method on `TwitchApi` in `twitch_api.py`:

```python
def get_streams_with_drops(self, game_id):
    response = self.make_http_request(
        TWITCH_STREAM_API_URL + "?first=100&game_id=" + game_id
    )
    drop_streams = []
    for stream in response.json()["data"]:
        tags = stream.get("tags") or []
        # Twitch tags participating streams with "DropsEnabled"
        if any(tag.lower() == "dropsenabled" for tag in tags):
            drop_streams.append(stream)
    return drop_streams
```

Category names are resolved to game IDs once at startup through the `/helix/games?name=` endpoint. Each streamer is remembered after the first alert, so you get one notification per stream until it goes offline. In the config it is an optional list:

```yaml
watch-drops:
  - "Rust"
  - "Elden Ring"
```

To accept the new key, `configuration.py`'s schema marks `streamers` as `Optional` and adds `Optional("watch-drops"): [And(str, len)]`.

## Running automatically at login

Both programs need your graphical session (its D-Bus and notification daemon), so start them at desktop login rather than as system services. A desktop autostart entry per program is enough.

`~/.config/autostart/notify-listener.desktop`:

```ini
[Desktop Entry]
Type=Application
Name=Notification to Pushbullet
Exec=/bin/bash -c "$HOME/Prog/PB_FOR_LINUX/notify-listener.sh"
X-GNOME-Autostart-enabled=true
```

`~/.config/autostart/twitch-game-notify.desktop`:

```ini
[Desktop Entry]
Type=Application
Name=Twitch Game Notify
Path=/home/YOUR_USER/Prog/twitch-game-notify
Exec=/home/YOUR_USER/Prog/twitch-game-notify/myenv/bin/python run_twitchgamenotify.py
X-GNOME-Autostart-enabled=true
```

Replace `YOUR_USER` with your username, since `Path=` and `Exec=` don't expand `~`. Log out and back in, then run `notify-send test test` to check that the chain works.

To run them by hand in the background instead:

```bash
nohup ~/Prog/PB_FOR_LINUX/notify-listener.sh >/dev/null 2>&1 &
(cd ~/Prog/twitch-game-notify && nohup myenv/bin/python run_twitchgamenotify.py >/dev/null 2>&1 &)
```

## Troubleshooting and security

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `send_push.sh` prints `invalid_access_token` | Token wrong, revoked, or has a trailing newline | Recreate it and write it with `printf '%s'`, not `echo` |
| Push works but nothing is forwarded | Listener not running, or the app isn't using D-Bus notifications | `pgrep -af notify-listener`; test with `notify-send` |
| Pushes repeat endlessly | A Pushbullet client re-shows the push as a desktop notification, and the listener forwards it again | Keep the app-name filter in `notify-listener.sh` and add the app's name if yours differs |
| Phone gets every desktop notification | The listener forwards everything by design | Add `case "$APP" in ...` rules to allow only apps you want, e.g. the Twitch notifier |
| twitch-game-notify reports an authentication error | Wrong Client ID/Secret | Check them at dev.twitch.tv/console/apps and generate a new secret if needed |
| `ConfigFileInvalid` on start | YAML typo or missing required key | Compare against `config.yaml.example`; run with `--print-config` |
| Occasional 502 errors | Twitch API hiccups | Normal; leave `ignore-502-errors-persistant: true` |

**Keep secrets out of what you share:**

- Never paste a real token into a script, an example config, or a screenshot. Read it from a `chmod 600` file, as above.
- Put only placeholders in `config.yaml.example`. The real values belong in the git-ignored `config.yaml`.
- Before publishing a fork, run `git diff --cached` and `grep -rni "secret\|token" .` to check what you're about to push.
- If a secret ever leaks, revoke it at once: Pushbullet → Settings → Account; Twitch → your app → New Secret. Removing it from git later doesn't help, because it stays in the history.
