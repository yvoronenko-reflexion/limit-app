# Limit

A simple macOS menu-bar app that limits a child's **total daily screen time** — a leaner
alternative to built-in Screen Time, which mis-attributes Java-launcher apps and keeps
counting during sleep.

Instead of tracking individual apps, Limit enforces one daily budget (default 2h) that
only counts down while the Mac is *actively used* (display on, unlocked, your session in
the foreground, and not idle).

## Status

**v1 + v2** are implemented:

- Menu-bar countdown that ticks only during active use
- 5 / 3 / 1-minute and "time's up" notifications
- Usage logging (`start`, `end`, `duration`)
- Configurable daily limit, reset time, and idle threshold
- Parent-PIN–gated settings
- **(v2)** Optional parent-PIN **lock overlay** at expiry, with PIN-gated
  +15/+30/+60-min extension, plus tamper-resistance (KeepAlive LaunchAgent + root
  watchdog) installed via `scripts/install.sh`
- A friendly look: a playful weather glyph in the menu bar (sunny → cloudy → hourglass →
  night as time winds down), a circular budget ring in the dropdown, and a warm
  "see you tomorrow" lock screen rather than a stern lockdown

Planned: **v3** one-way iMessage notifications to parents. See
[`REQUIREMENTS.md`](REQUIREMENTS.md).

## Install (one command)

On any Mac, install the app **and** its enforcement services with a single command —
no Xcode, Homebrew, or source checkout needed. Replace `<child-username>` with the macOS
account whose screen time you want to limit:

```sh
curl -fsSL https://raw.githubusercontent.com/yvoronenko-reflexion/limit-app/main/scripts/bootstrap.sh | sudo bash -s -- <child-username>
```

This downloads the latest prebuilt `Limit.app` from
[Releases](https://github.com/yvoronenko-reflexion/limit-app/releases), copies it to
`/Applications`, and installs the root-owned `KeepAlive` LaunchAgent + watchdog daemon.
Pin a specific version with `LIMIT_VERSION=v0.1.0` in front of the command.

Then open the app's Settings (menu bar → Settings…) to set the parent PIN and daily
limit, and turn on **"Lock the screen when time runs out."**

To uninstall: `sudo ./scripts/uninstall.sh <child-username>` (or grab `uninstall.sh`
from the repo).

### How releases are built

Pushing a `v*` tag triggers `.github/workflows/release.yml`, which builds `Limit.app` on
a macOS runner and publishes `limit-installer.zip` to a GitHub Release — that's the asset
the one-command installer downloads:

```sh
git tag v0.1.0 && git push origin v0.1.0
```

## Enabling enforcement (v2)

Enforcement is **off by default** — the app is a passive timer until you opt in.

1. In Settings (menu bar → Settings…, parent PIN required), turn on **"Lock the screen
   when time runs out."**
2. The one-command installer above already installs the watchdog. If you built from source
   instead, install it once as an admin:

   ```sh
   sudo ./scripts/install.sh <child-username>   # optionally pass /path/to/Limit.app
   ```

   This copies the app to `/Applications`, installs a root-owned `KeepAlive` LaunchAgent
   and a root LaunchDaemon watchdog. Reverse with `sudo ./scripts/uninstall.sh <child-username>`.

The overlay + watchdog stop in-session evasion (quitting/killing the app). They do **not**
stop an admin account, Recovery mode, or direct edits to the budget file — see
[`REQUIREMENTS.md`](REQUIREMENTS.md) for the full tamper scope.

## Build & run

Requires Xcode and [XcodeGen](https://github.com/yonyz/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # if xcode-select points at CLT
xcodebuild -project LimitApp.xcodeproj -scheme LimitApp -destination 'platform=macOS' build
open ~/Library/Developer/Xcode/DerivedData/LimitApp-*/Build/Products/Debug/Limit.app
```

The app is menu-bar only (no Dock icon). See [`CLAUDE.md`](CLAUDE.md) for architecture and
test commands.
