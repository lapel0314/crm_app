#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SCRIPT="$SCRIPT_DIR/backup_supabase_db_to_gdrive.sh"
LABEL="${CRM_BACKUP_LAUNCHD_LABEL:-com.pinkphone.crm.db-backup}"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs"
HOUR="${CRM_BACKUP_HOUR:-4}"
MINUTE="${CRM_BACKUP_MINUTE:-0}"

[ -x "$BACKUP_SCRIPT" ] || chmod +x "$BACKUP_SCRIPT"
mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR"

cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$BACKUP_SCRIPT</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>$HOUR</integer>
    <key>Minute</key>
    <integer>$MINUTE</integer>
  </dict>
  <key>RunAtLoad</key>
  <false/>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/$LABEL.out.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/$LABEL.err.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl enable "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true

echo "Installed launchd job: $LABEL"
echo "Plist: $PLIST"
echo "Schedule: every day at $(printf '%02d:%02d' "$HOUR" "$MINUTE")"
echo "Check: launchctl print gui/$(id -u)/$LABEL"
