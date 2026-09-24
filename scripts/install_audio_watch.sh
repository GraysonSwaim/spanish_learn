#!/bin/bash
# Install (or reinstall) the launchd agent that runs audio_watch.sh whenever a Cinco backup changes.
#   bash scripts/install_audio_watch.sh            install
#   bash scripts/install_audio_watch.sh --remove   uninstall
# Log: ~/Library/Logs/cinco-audio.log
set -eu
LABEL=com.cinco.audio-watch
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SCRIPT="$(cd "$(dirname "$0")" && pwd)/audio_watch.sh"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
if [ "${1:-}" = "--remove" ]; then rm -f "$PLIST"; echo "Removed."; exit 0; fi

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$SCRIPT</string></array>
  <key>WatchPaths</key>
  <array>
    <string>$HOME/Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents/Spanish/backups</string>
    <string>$HOME/Library/Mobile Documents/com~apple~CloudDocs/Spanish/backups</string>
    <!-- The files too: an in-place overwrite changes the file but not always its folder. -->
    <string>$HOME/Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents/Spanish/backups/cinco-backup.txt</string>
    <string>$HOME/Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents/Spanish/backups/cinco-backup.json</string>
  </array>
  <key>ThrottleInterval</key><integer>60</integer>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/cinco-audio.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/cinco-audio.log</string>
</dict>
</plist>
EOF
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed. Watching both backup folders; log at ~/Library/Logs/cinco-audio.log"
