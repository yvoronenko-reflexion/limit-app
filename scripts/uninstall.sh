#!/bin/bash
# Reverses scripts/install.sh. Run as an admin:
#
#   sudo ./scripts/uninstall.sh <child-username>

set -uo pipefail

LABEL="com.yscale.limitapp"
WATCHDOG_LABEL="com.yscale.limitapp.watchdog"
AGENT_PLIST="/Library/LaunchAgents/${LABEL}.plist"
DAEMON_PLIST="/Library/LaunchDaemons/${WATCHDOG_LABEL}.plist"
HELPER_DIR="/usr/local/limit-app"
APP_DST="/Applications/Limit.app"

if [ "$(id -u)" -ne 0 ]; then
    echo "error: must be run as root (use sudo)." >&2
    exit 1
fi

TARGET_USER="${1:-}"

# Stop and remove the watchdog daemon.
launchctl bootout system "$DAEMON_PLIST" 2>/dev/null || true
rm -f "$DAEMON_PLIST"

# Stop the agent in the target user's GUI session (if we know who / they're logged in).
if [ -n "$TARGET_USER" ] && id -u "$TARGET_USER" >/dev/null 2>&1; then
    UID_NUM="$(id -u "$TARGET_USER")"
    launchctl bootout "gui/${UID_NUM}/${LABEL}" 2>/dev/null || true
fi
rm -f "$AGENT_PLIST"

rm -rf "$HELPER_DIR"

echo "Removed LaunchAgent, watchdog daemon, and helper. Left $APP_DST in place."
echo "Delete the app manually if you also want it gone: rm -rf '$APP_DST'"
