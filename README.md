# TimeOn

Forced-break timer for macOS. Lives as a menu bar icon, runs a configurable work / break cycle, and at the end of every work block it covers every connected display with an unkillable black overlay until the break is over.

## Features

- **Menu bar agent** with the format `⦿ 12m` showing minutes until the next break (`⏸ 12m` while paused). No Dock icon, no Cmd-Tab presence.
- **Configurable cycle** — work duration: 25 / 30 / 45 / 50 / 60 / 75 / 90 / 120 min · break duration: 1 / 5 / 10 / 15 / 20 / 30 / 45 min.
- **Pause / Resume** that preserves the exact remaining time.
- **Test Break (10 s)** for verifying the blocker without waiting a full work block.
- **Multi-display blocker** — one borderless black `NSWindow` per `NSScreen.screens`, level `kCGMaximumWindowLevelKey` (above notifications, screen saver, Dock). Rebuilt on display changes, wake, screensaver-stop and active-space changes.
- **Skip Break button** at the bottom of the blocker, configurable on/off from the settings panel.
- **Bypass apps** — pick any currently running app from the system; if it is in foreground when a break would trigger, the break is skipped and a new work cycle starts.
- **Smooth progress bar** rendered with `TimelineView(.animation)` at the display refresh rate (60 fps), drawn manually so the width grows continuously without per-tick jumps.

## Blocker hardening

- `NSApplication.PresentationOptions = [.hideDock, .hideMenuBar, .disableAppleMenu, .disableProcessSwitching, .disableForceQuit, .disableSessionTermination, .disableHideApplication, .disableMenuBarTransparency]`.
- `NSWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, `canHide = false`, `hidesOnDeactivate = false`, `isMovable = false`, `isReleasedWhenClosed = false`.
- `keyDown`, `performKeyEquivalent` and `cancelOperation` (Esc) are swallowed.
- A 0.5 s watchdog re-applies presentation options, window level, visibility and re-activates the app if it loses focus.
- Observers reinforce the overlay on `didChangeScreenParameters`, `didResignActive`, `didActivateApplication`, `activeSpaceDidChange`, `didWake`, `screensDidWake`, and the distributed `com.apple.screensaver.didstart` / `didstop` notifications.
- App Sandbox is **off** so the blocker can use the maximum window level and can't be quit via standard shortcuts during a break.

## Project layout

```
TimeOn/TimeOn/
  TimeOnApp.swift          @main scene with MenuBarExtra and the menu bar label
  AppDelegate.swift        sets accessory activation policy, blocks terminate during break
  ContentView.swift        settings panel inside the popover
  SessionController.swift  state machine (idle / working / onBreak), pause, persistence, bypass logic
  BreakBlocking.swift      protocol abstraction for the blocker (lets tests inject a spy)
  BlockerCoordinator.swift NSWindow management, presentation options, watchdog, observers
  BreakBlockerView.swift   SwiftUI overlay (progress bar + elapsed / -remaining + Skip Break)
  RunningApps.swift        snapshot of running apps with `activationPolicy == .regular`
TimeOnTests/
  TimeOnTests.swift        27 unit tests over SessionController behaviour
TimeOnUITests/             smoke launch test
```

## Build & run

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project TimeOn/TimeOn.xcodeproj -scheme TimeOn \
             -configuration Debug -destination 'platform=macOS' build
```

Or open `TimeOn/TimeOn.xcodeproj` in Xcode and press Run. macOS 26.3+ deployment target.

## Tests

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project TimeOn/TimeOn.xcodeproj -scheme TimeOn \
             -configuration Debug -destination 'platform=macOS' test
```

The unit tests use Swift Testing and an injected `BreakBlocking` spy plus an isolated `UserDefaults` suite, so they cover the full lifecycle (start / skip / pause / resume / bypass / persistence / time math / phase transitions) without ever opening a real overlay window.

## Releases

Pre-built binaries are published on the [Releases page](https://github.com/jalopezsuarez/TimeOn/releases).

- **v1.0.0** — Release / arm64, signed with an **Apple Development** identity (`Jose Antonio Lopez Suarez`, team `DF5Y772UU7`). `codesign --verify --strict` passes. The certificate is a development cert, not a Developer ID Application cert, and the build is not notarized — so Gatekeeper still rejects it on a first run. Right-click → Open to bypass it.

A fully Gatekeeper-clean build needs a Developer ID Application certificate plus `xcrun notarytool` notarization, both gated on an Apple Developer Program enrollment.

## Known limits

- `kill -9` from another terminal or Activity Monitor will still terminate the app — preventing that needs a privileged helper, out of scope.
- The system lock screen (Cmd-Ctrl-Q) renders at its own level; on unlock the watchdog rebuilds and re-fronts the overlay within 0.5 s.
- The app is not signed for distribution; on first launch macOS may show the standard Gatekeeper prompt.
