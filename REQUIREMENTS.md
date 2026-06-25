# limit-app — Requirements

## Problem

macOS's built-in Screen Time is unreliable for enforcing a child's **total** daily
screen time:

- Per-app trackers collapse many downloaded apps that use Java launchers into a single
  "java" bucket, so per-app limits don't map to what the child actually uses.
- macOS's own background Java usage keeps "java" time accruing even while the Mac is
  asleep, producing nonsensical totals (e.g. ~24h/day).

## Goal

A simpler tool that **ignores per-app accounting** and enforces a single **total daily
active-use budget** (default 2 hours) for a specific macOS user. Time counts only while
the Mac is genuinely being used by that user.

## Deployment context

- Runs on the **family's own Macs**, administered by the parents.
- The privileged enforcement component (v2+) is installed via a one-time `sudo` setup
  script — no App Store, MDM, or Apple notarization required.
- Local ad-hoc code signing is sufficient.

---

## Definitions

**Actively used** (the budget only counts down when ALL are true):

- The Mac's display is on (not asleep).
- The screen is unlocked.
- This user's session owns the active console (not switched out via fast user switching).
- There has been keyboard/mouse input within the **idle threshold** (default 60s).

**Budget day** — the 24h period starting at the configurable **daily reset time**
(default 00:00 local). A new budget day restores the full daily limit.

---

## Functional requirements

### Timer & budget
- FR1. Maintain a per-user daily budget in seconds; default **2h**, configurable.
- FR2. Decrement the budget by 1s for each second the Mac is *actively used*; never below 0.
- FR3. Pause counting immediately when use stops (lock, display sleep, fast-user-switch,
  idle ≥ threshold) and resume when it returns.
- FR4. Reset the budget to the daily limit at the configured reset time; survive the app
  not running across the boundary (reset is computed on next launch/tick).
- FR5. Persist remaining time so a restart mid-day preserves it.

### Display
- FR6. Show remaining time in the menu bar, updating each second.
- FR7. Show status (counting / paused + reason, used vs. limit) in the menu bar dropdown.

### Warnings
- FR8. Notify the user at **5, 3, and 1 minute** remaining, and at **0** ("time's up").
- FR9. Warnings fire on budget crossing thresholds (not wall-clock), so pausing defers them.
- FR10. Each threshold fires at most once per budget day; a granted extension re-arms them.

### Usage logging
- FR11. Append every active-use session as `(start, end, duration)` to a durable log.

### Parent controls
- FR12. A **parent PIN** gates settings (and, in v2+, unlock/extension). Stored only as a
  salted hash, never plaintext.
- FR13. Parents can configure: daily limit, reset time, idle threshold, parent PIN,
  parents' iMessage handles, target username.

### Enforcement (v2)
- FR14. When the budget reaches 0, **lock the screen** behind a full-screen overlay that
  requires the **parent PIN** to dismiss (not the child's login password).
- FR15. The overlay covers all displays, captures input, and re-presents if escaped.
- FR16. A parent can **extend** the budget (e.g. +30 min) by entering the parent PIN; the
  overlay then dismisses and counting resumes.
- FR17. The app must be tamper-resistant: a child cannot simply quit it to evade the limit.

### Parent notifications & remote extension (v3)
- FR18. On warnings/expiry/extension, send a **one-way iMessage** to the configured parent
  handles.
- FR19. Remote extension stays **PIN-based** (parent enters PIN on the Mac). Two-way
  iMessage reply-parsing is explicitly **out of scope** (see Non-goals).

---

## Non-functional requirements

- NFR1. Native macOS, Swift + SwiftUI, deployment target macOS 13.
- NFR2. No exotic permissions in v1: active-use detection uses `NSWorkspace`,
  `DistributedNotificationCenter`, `CGSessionCopyCurrentDictionary`, and IOKit
  `HIDIdleTime` (no Accessibility prompt).
- NFR3. Low overhead: a 1 Hz tick; debounced state persistence.
- NFR4. Core logic isolated from UI/system in a separately unit-testable module
  (`LimitCore`).

---

## Non-goals / explicitly deferred

- Per-app or per-website tracking.
- MDM / configuration-profile enforcement.
- **Two-way iMessage**: reading parent replies from `chat.db` is fragile (Full Disk
  Access, undocumented schema, hex-encoded bodies since Ventura, multi-minute delivery
  lag) and would run from the *child's* Apple ID, leaking the parent's contact. Rejected
  in favor of PIN-based extension + one-way notification.
- Forced **logout** at expiry (considered, rejected in favor of the PIN lock overlay to
  avoid losing the child's unsaved work). Could be revisited.
- Blocking re-login until the next day (was a stretch goal; superseded by the lock
  overlay).

---

## Milestones

- **v1 (implemented):** budget timer, active-use detection, menu-bar display, warnings,
  usage logging, PIN-gated settings. Runs in the child's session; no forced enforcement —
  at 0 it notifies and shows "expired".
- **v2:** parent-PIN lock overlay at expiry, PIN extension, tamper-resistance via a
  per-user `KeepAlive` LaunchAgent + a root LaunchDaemon watchdog (installed with `sudo`).
- **v3:** one-way iMessage notifications to parents via AppleScript → Messages.app.

---

## Acceptance (v1)

- Menu-bar countdown decrements only during active use; pauses on lock (⌃⌘Q), display
  sleep, fast user switch, and idle beyond the threshold.
- 5/3/1-minute and "time's up" notifications fire as the budget crosses each threshold.
- Active sessions are appended to `~/Library/Application Support/limit-app/usage.jsonl`.
- Remaining time survives an app restart; crossing the reset time restores the full limit.
- Settings require the parent PIN; an incorrect PIN is rejected.
