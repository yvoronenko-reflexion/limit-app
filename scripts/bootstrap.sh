#!/bin/bash
# limit-app one-command installer.
#
# Downloads the latest prebuilt Limit.app installer from GitHub Releases and installs
# the app plus its enforcement services (KeepAlive LaunchAgent + root watchdog). No
# Xcode, Homebrew, or source checkout required on the target Mac.
#
# Run it with a single command (must be run as root, hence sudo):
#
#   curl -fsSL https://raw.githubusercontent.com/yvoronenko-reflexion/limit-app/main/scripts/bootstrap.sh | sudo bash -s -- <child-username>
#
# Or, if you've already downloaded this file:
#
#   sudo ./scripts/bootstrap.sh <child-username>
#
# Environment overrides:
#   LIMIT_VERSION   release tag to install (default: latest). e.g. LIMIT_VERSION=v0.1.0
#   LIMIT_REPO      owner/repo to fetch from (default: yvoronenko-reflexion/limit-app)

set -euo pipefail

REPO="${LIMIT_REPO:-yvoronenko-reflexion/limit-app}"
VERSION="${LIMIT_VERSION:-latest}"
ASSET="limit-installer.zip"

if [ "$VERSION" = "latest" ]; then
    ASSET_URL="https://github.com/${REPO}/releases/latest/download/${ASSET}"
else
    ASSET_URL="https://github.com/${REPO}/releases/download/${VERSION}/${ASSET}"
fi

# --- preconditions -----------------------------------------------------------

if [ "$(uname -s)" != "Darwin" ]; then
    echo "error: limit-app only runs on macOS." >&2
    exit 1
fi

TARGET_USER="${1:-}"
if [ -z "$TARGET_USER" ]; then
    echo "usage: sudo $0 <child-username>" >&2
    echo "  (the macOS username whose screen time should be limited)" >&2
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "error: must be run as root. Re-run with sudo, e.g.:" >&2
    echo "  curl -fsSL https://raw.githubusercontent.com/${REPO}/main/scripts/bootstrap.sh | sudo bash -s -- ${TARGET_USER}" >&2
    exit 1
fi

if ! id -u "$TARGET_USER" >/dev/null 2>&1; then
    echo "error: no such macOS user: $TARGET_USER" >&2
    echo "  Available users:" >&2
    dscl . -list /Users 2>/dev/null | grep -vE '^_' | sed 's/^/    /' >&2 || true
    exit 1
fi

# --- download + extract ------------------------------------------------------

TMP="$(mktemp -d /tmp/limit-app.XXXXXX)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

echo "Downloading $ASSET ($VERSION) from $REPO..."
if ! curl -fSL --retry 3 -o "$TMP/$ASSET" "$ASSET_URL"; then
    echo "error: failed to download $ASSET_URL" >&2
    echo "  Make sure a release with the '$ASSET' asset exists (push a v* tag to build one)." >&2
    exit 1
fi

echo "Extracting..."
/usr/bin/ditto -x -k "$TMP/$ASSET" "$TMP/unpacked"

APP_SRC="$(/usr/bin/find "$TMP/unpacked" -maxdepth 2 -name 'Limit.app' -type d | head -n1)"
INSTALL_SH="$(/usr/bin/find "$TMP/unpacked" -maxdepth 2 -name 'install.sh' -type f | head -n1)"
if [ -z "$APP_SRC" ] || [ -z "$INSTALL_SH" ]; then
    echo "error: downloaded archive is missing Limit.app or install.sh." >&2
    exit 1
fi

# The app came over the network, so it carries the com.apple.quarantine flag.
# Strip it so launchd can spawn the binary without a Gatekeeper block.
echo "Clearing quarantine flag..."
/usr/bin/xattr -dr com.apple.quarantine "$APP_SRC" 2>/dev/null || true

# --- run the privileged install (services + watchdog) ------------------------

chmod +x "$INSTALL_SH" "$(dirname "$INSTALL_SH")/watchdog.sh" 2>/dev/null || true

echo "Installing app and enforcement services for user '$TARGET_USER'..."
bash "$INSTALL_SH" "$TARGET_USER" "$APP_SRC"

# Belt-and-suspenders: clear quarantine on the installed copy too.
/usr/bin/xattr -dr com.apple.quarantine /Applications/Limit.app 2>/dev/null || true

echo
echo "✅ limit-app installed."
echo "   Next: open the app's Settings (menu bar → Settings…) to set the parent PIN,"
echo "   daily limit, and turn on 'Lock the screen when time runs out.'"
