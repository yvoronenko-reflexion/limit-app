#!/bin/bash
# limit-app watchdog — runs as root from a LaunchDaemon (see install.sh).
#
# Purpose: keep the per-user LaunchAgent bootstrapped so the child can't permanently
# evade the limit by booting it out of their own GUI session. The agent's KeepAlive
# relaunches the app if it's merely quit/killed; this re-bootstraps the agent itself if
# it's been unloaded. Runs every StartInterval seconds.
#
# Tamper scope (be honest): this defends against in-session evasion (quit, kill,
# launchctl bootout). It does NOT defend against an admin account, Recovery mode, or a
# user directly editing the budget state file. Fully authoritative state requires a
# privileged helper owning the budget (tracked for a later milestone).

set -u

LABEL="com.yscale.limitapp"
AGENT_PLIST="/Library/LaunchAgents/${LABEL}.plist"
TARGET_USER="@TARGET_USER@"

[ -f "$AGENT_PLIST" ] || exit 0

# Resolve the target user's UID; bail quietly if the user doesn't exist.
UID_NUM="$(id -u "$TARGET_USER" 2>/dev/null)" || exit 0
[ -n "$UID_NUM" ] || exit 0

# Only act when that user actually owns an active GUI (Aqua) session — otherwise there's
# no domain to bootstrap into.
CONSOLE_USER="$(stat -f%Su /dev/console 2>/dev/null)"
[ "$CONSOLE_USER" = "$TARGET_USER" ] || exit 0

# Re-bootstrap if the agent isn't currently loaded in the user's GUI domain.
if ! launchctl print "gui/${UID_NUM}/${LABEL}" >/dev/null 2>&1; then
    launchctl bootstrap "gui/${UID_NUM}" "$AGENT_PLIST" 2>/dev/null
fi

# Make sure it's enabled (a bootout/disable would otherwise stick).
launchctl enable "gui/${UID_NUM}/${LABEL}" 2>/dev/null

exit 0
