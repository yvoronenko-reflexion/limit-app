# Limit

A simple macOS menu-bar app that limits a child's **total daily screen time** — a leaner
alternative to built-in Screen Time, which mis-attributes Java-launcher apps and keeps
counting during sleep.

Instead of tracking individual apps, Limit enforces one daily budget (default 2h) that
only counts down while the Mac is *actively used* (display on, unlocked, your session in
the foreground, and not idle).

## Status

**v1** is implemented:

- Menu-bar countdown that ticks only during active use
- 5 / 3 / 1-minute and "time's up" notifications
- Usage logging (`start`, `end`, `duration`)
- Configurable daily limit, reset time, and idle threshold
- Parent-PIN–gated settings

Planned: **v2** parent-PIN lock screen at expiry + tamper-resistance; **v3** one-way
iMessage notifications to parents. See [`REQUIREMENTS.md`](REQUIREMENTS.md).

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
