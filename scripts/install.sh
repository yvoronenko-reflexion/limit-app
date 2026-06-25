#!/bin/bash
# limit-app v2 enforcement installer. Installs:
#   1. /Applications/Limit.app                        (the app, copied from a build)
#   2. /Library/LaunchAgents/com.yscale.limitapp.plist   (KeepAlive agent, root-owned)
#   3. /Library/LaunchDaemons/com.yscale.limitapp.watchdog.plist  (root watchdog)
#   4. /usr/local/limit-app/watchdog.sh
#
# Root ownership of the plists means the child (a non-admin user) can't remove them.
# Run once, as an admin, with sudo:
#
#   sudo ./scripts/install.sh <child-username> [/path/to/Limit.app]
#
# If the app path is omitted, the most recent Debug build in DerivedData is used.

set -euo pipefail

LABEL="com.yscale.limitapp"
WATCHDOG_LABEL="com.yscale.limitapp.watchdog"
AGENT_PLIST="/Library/LaunchAgents/${LABEL}.plist"
DAEMON_PLIST="/Library/LaunchDaemons/${WATCHDOG_LABEL}.plist"
HELPER_DIR="/usr/local/limit-app"
WATCHDOG_DST="${HELPER_DIR}/watchdog.sh"
APP_DST="/Applications/Limit.app"

if [ "$(id -u)" -ne 0 ]; then
    echo "error: must be run as root (use sudo)." >&2
    exit 1
fi

TARGET_USER="${1:-}"
if [ -z "$TARGET_USER" ]; then
    echo "usage: sudo $0 <child-username> [/path/to/Limit.app]" >&2
    exit 1
fi
if ! id -u "$TARGET_USER" >/dev/null 2>&1; then
    echo "error: no such user: $TARGET_USER" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Locate the app bundle to install.
APP_SRC="${2:-}"
if [ -z "$APP_SRC" ]; then
    APP_SRC="$(ls -dt "$HOME"/Library/Developer/Xcode/DerivedData/LimitApp-*/Build/Products/Debug/Limit.app 2>/dev/null | head -n1 || true)"
    # When invoked via sudo, $HOME is root's; also try the invoking user's DerivedData.
    if [ -z "$APP_SRC" ] && [ -n "${SUDO_USER:-}" ]; then
        SUDO_HOME="$(eval echo "~${SUDO_USER}")"
        APP_SRC="$(ls -dt "$SUDO_HOME"/Library/Developer/Xcode/DerivedData/LimitApp-*/Build/Products/Debug/Limit.app 2>/dev/null | head -n1 || true)"
    fi
fi
if [ -z "$APP_SRC" ] || [ ! -d "$APP_SRC" ]; then
    echo "error: could not find Limit.app. Build first, or pass the path explicitly." >&2
    exit 1
fi

echo "Installing $APP_SRC -> $APP_DST"
rm -rf "$APP_DST"
cp -R "$APP_SRC" "$APP_DST"
chown -R root:wheel "$APP_DST"

APP_BIN="${APP_DST}/Contents/MacOS/Limit"
[ -x "$APP_BIN" ] || { echo "error: app binary not found at $APP_BIN" >&2; exit 1; }

# Helper dir + watchdog script (with the target user substituted in).
echo "Installing watchdog -> $WATCHDOG_DST"
mkdir -p "$HELPER_DIR"
sed "s/@TARGET_USER@/${TARGET_USER}/g" "${SCRIPT_DIR}/watchdog.sh" > "$WATCHDOG_DST"
chown root:wheel "$WATCHDOG_DST"
chmod 755 "$WATCHDOG_DST"

# LaunchAgent: relaunches the app in the GUI session if quit/killed.
echo "Installing LaunchAgent -> $AGENT_PLIST"
cat > "$AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${APP_BIN}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
PLIST
chown root:wheel "$AGENT_PLIST"
chmod 644 "$AGENT_PLIST"

# LaunchDaemon: root watchdog that keeps the agent bootstrapped.
echo "Installing watchdog daemon -> $DAEMON_PLIST"
cat > "$DAEMON_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${WATCHDOG_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${WATCHDOG_DST}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>60</integer>
</dict>
</plist>
PLIST
chown root:wheel "$DAEMON_PLIST"
chmod 644 "$DAEMON_PLIST"

# Bootstrap the watchdog daemon now.
launchctl bootout system "$DAEMON_PLIST" 2>/dev/null || true
launchctl bootstrap system "$DAEMON_PLIST"

# Bootstrap the agent into the target user's GUI session if they're logged in.
UID_NUM="$(id -u "$TARGET_USER")"
if [ "$(stat -f%Su /dev/console 2>/dev/null)" = "$TARGET_USER" ]; then
    launchctl bootout "gui/${UID_NUM}/${LABEL}" 2>/dev/null || true
    launchctl bootstrap "gui/${UID_NUM}" "$AGENT_PLIST" || true
    launchctl enable "gui/${UID_NUM}/${LABEL}" || true
    echo "Agent bootstrapped for $TARGET_USER (uid $UID_NUM)."
else
    echo "Note: $TARGET_USER isn't the console user right now; the watchdog will bootstrap the agent when they next log in."
fi

echo "Done. Remember to enable enforcement in the app's Settings."
