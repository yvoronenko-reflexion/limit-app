# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A native macOS menu-bar app (Swift + SwiftUI) that enforces a single **total daily
active-use budget** for a child's macOS user, as a simpler replacement for built-in
Screen Time. See `REQUIREMENTS.md` for the full spec and the v1/v2/v3 milestones. v1
(timer, detection, menu bar, warnings, logging, PIN-gated settings) and v2 (opt-in
parent-PIN lock overlay at expiry, PIN-gated extension, LaunchAgent + root-watchdog
tamper-resistance) are implemented; iMessage (v3) is a later phase.

## Toolchain note (important)

The Xcode project is **generated** by [XcodeGen](https://github.com/yonyz/XcodeGen) from
`project.yml`; `LimitApp.xcodeproj` is git-ignored. Always edit `project.yml` (targets,
settings, bundle ids) and re-run `xcodegen generate` — never hand-edit the `.xcodeproj`.

On this machine the active developer dir is Command Line Tools, but full Xcode is
installed. Prefix `xcodebuild` invocations with `DEVELOPER_DIR` (avoids needing `sudo
xcode-select`):

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

## Commands

```sh
# Regenerate the Xcode project after changing project.yml or adding/removing files
xcodegen generate

# Build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project LimitApp.xcodeproj -scheme LimitApp -destination 'platform=macOS' build

# Run all unit tests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project LimitApp.xcodeproj -scheme LimitApp -destination 'platform=macOS' test

# Run a single test (class or method)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project LimitApp.xcodeproj -scheme LimitApp -destination 'platform=macOS' \
  test -only-testing:LimitCoreTests/TimerEngineTests
# ...or a method: -only-testing:LimitCoreTests/TimerEngineTests/testRolloverResetsBudgetOnNewDay

# Launch the built app (menu-bar only — look in the menu bar, no Dock icon)
open ~/Library/Developer/Xcode/DerivedData/LimitApp-*/Build/Products/Debug/Limit.app
```

## Architecture

Two modules (so the logic is unit-testable headlessly, without a GUI host):

- **`LimitCore`** (framework, no SwiftUI) — pure logic + thin system wrappers:
  - `TimerEngine` — the budget countdown. Pure/synchronous: `tickActive()` consumes one
    second, `rolloverIfNeeded(now:)` resets on a new budget day, `extend(by:)` grants time.
  - `DayBoundary` — maps an instant to a `yyyy-MM-dd` "budget day" key that rolls at the
    configured reset time. Date-string keys (not stored `Date`s) keep state DST-robust.
  - `ActivityMonitor` — combines event-driven flags (lock/unlock via
    `DistributedNotificationCenter`, display sleep + fast-user-switch via `NSWorkspace`)
    with a poll-time on-console (`SessionState`) + idle (`IdleTime`) check into a single
    `snapshot(idleThreshold:)`.
  - `SessionState` (CGSession on-console), `IdleTime` (IOKit `HIDIdleTime`, no
    Accessibility permission), `WarningScheduler` (which thresholds are due),
    `UsageLogger` (append-only JSONL sessions), `Settings`/`DayState`, `SettingsStore` +
    `JSONFile` + `AppPaths` (persistence), `ParentPIN` (salted-hash gate),
    `NotificationManager`, `Enforcement` (pure `shouldLock(remaining:enabled:)` decision).
- **`LimitApp`** (the app) — SwiftUI + the coordinator:
  - `AppModel` — the **heartbeat**. A 1 Hz `Timer` drives `tick()`: roll the day over,
    sample activity, decrement only when active, fire due warnings, open/close usage
    sessions, and persist (debounced every 5s; forced on rollover/settings/quit). Owns all
    `LimitCore` pieces and publishes observable state.
  - `LimitAppApp` (`@main`, `MenuBarExtra` + `Settings` scenes), `AppDelegate`
    (start/flush), `MenuContentView`, `SettingsView` (PIN-gated).
  - **(v2) `Lock/LockController` + `Lock/LockOverlayView`** — the enforcement overlay.
    Each `tick()` calls `Enforcement.shouldLock(...)`; when true, `LockController` puts a
    borderless shielding window (`CGShieldingWindowLevel()`) on every screen, sets kiosk
    `presentationOptions` (hide dock/menu bar, disable process-switch/force-quit), and
    re-asserts key/front on resign or display change. The primary screen's overlay hosts
    the parent-PIN field + +15/+30/+60-min extend buttons (→ `model.verifyPIN`/`extend`).
    Dismisses automatically once the budget goes positive (extension or daily rollover).
- **tamper-resistance (`scripts/`)** — `install.sh` (run once with `sudo <child-user>`)
  copies `Limit.app` to `/Applications` and installs a root-owned `KeepAlive` LaunchAgent
  (relaunches the app if quit/killed) plus a root LaunchDaemon running `watchdog.sh` every
  60s (re-bootstraps the agent if booted out of the GUI session). `uninstall.sh` reverses
  it. These defend against *in-session* evasion only — not admin/Recovery/state-file edits.
- **one-command install (`scripts/bootstrap.sh` + `.github/workflows/release.yml`)** — a
  `v*` tag push builds `Limit.app` (Release) on a macOS CI runner and publishes
  `limit-installer.zip` (app + `install.sh` + `watchdog.sh`) to a GitHub Release.
  `bootstrap.sh` is the curl-pipe-to-`sudo bash` entrypoint: it downloads that asset,
  strips the quarantine flag, and hands the extracted app to `install.sh`. Family Macs
  install with one command and need no Xcode/Homebrew/checkout. Repo is public so no token
  is needed; `LIMIT_VERSION`/`LIMIT_REPO` env vars override the tag/source.

Key design decisions:
- **Warnings fire reactively** as the budget crosses 300/180/60/0s, *not* pre-scheduled by
  wall-clock — because the countdown pauses whenever the Mac isn't actively used.
- The app is **`LSUIElement`** (no Dock icon); UI lives entirely in the menu bar.
- Not sandboxed (`Sources/LimitApp/LimitApp.entitlements`): needs IOKit/CGSession now and
  AppleScript→Messages later.

## Data locations

`~/Library/Application Support/limit-app/`: `settings.json`, `state.json` (current budget
day + remaining + fired thresholds), `usage.jsonl` (one JSON session record per line).

## Conventions

- Put new pure/testable logic in `LimitCore` and unit-test it under `Tests/LimitCoreTests`;
  keep SwiftUI/`AppKit`-only code in `LimitApp`.
- `Settings` (our model) collides with SwiftUI's `Settings` scene — qualify as
  `LimitCore.Settings` in files that import both.
- After adding a Swift file, re-run `xcodegen generate` so it's included in the project.
