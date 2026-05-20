# roontrol Claude instructions

## What this is

Swift menubar app (mbp) that intercepts F10-F19 keyDown events and routes
them to roon-bridge over HTTP. arm64, macOS 13+, no dock icon (LSUIElement).

## Key constraints

- **roontrol's tap only sees `keyDown`, never media events.** Real volume/mute
  keys travel as `NSSystemDefined` events; the CGEventTap masks `keyDown` only.
  So roontrol acts only on keyboards that deliver F10-F19 as real `keyDown`
  keycodes. On mbp the external keyboard is configured (Karabiner) to emit
  F10/F11/F12 keycodes, so its F10-F12 always route to Roon (fn is a no-op
  there). The internal keyboard runs default macOS behavior (`fnState=0`):
  bare F10-F12 are media keys that drive macOS system volume, and fn+F10-F12
  are f-key keycodes that route to Roon. This split is deliberate.
- **Dell DDPM must not double-fire F-keys.** If Dell Display and Peripheral
  Manager is installed, its setting "Enable Fn and media key behavior" must
  stay UNCHECKED. Checked, it makes every F-key fire the media function AND
  the f-key, so F11 drops macOS system volume in lockstep with Roon. This
  cost a multi-hour misdiagnosis on 2026-05-19.
- **mbp talks ONLY to roon-bridge via HTTP.** No direct Roon Core connection.
- **No local config on mbp.** All settings live in roon-bridge's config.json. Sole exception: `BRIDGE_AUTH_TOKEN` lives in roontrol's LaunchAgent plist EnvironmentVariables (mirrors how roon-bridge stores its own copy). Repo-tracked source: `launchd/com.roontrol.plist`. Rotation requires editing both the bridge plist and this one.
- **No em dashes** in any output (code comments, commit messages, docs).
- **Server-side ramping.** roontrol sends one HTTP request per keypress.

## Build

On mbp with Xcode: `xcodebuild` or `swift build -c release`.
Mini has CLT only (no Xcode) -- cannot build AppKit targets here.

## Test

```
swift test
```

Tests live in `Tests/roontrolTests/`. No real Roon calls; MockURLProtocol intercepts URLSession.

## Commit conventions

- `feat:` new feature
- `fix:` bug fix
- `test:` test additions
- `chore:` deps, build, CI
- `docs:` README, comments

## Source layout

```
Sources/roontrol/
  main.swift             -- entry point
  AppDelegate.swift      -- lifecycle, accessibility check
  KeyEventMonitor.swift  -- CGEventTap for F10-F19 keyDown
  KeyRouter.swift        -- routing decisions (modifier logic, keycode mapping)
  RoonBridgeClient.swift -- URLSession HTTP client + Codable types
  BridgeDiscovery.swift  -- mDNS browser + fallback
  NetworkProfile.swift   -- at-home detection (NWPathMonitor)
  MenubarController.swift -- NSStatusItem + SwiftUI popover

Tests/roontrolTests/
  NetworkProfileTests.swift   -- interface simulation
  KeyRouterTests.swift        -- keycode mapping, modifier routing
  RoonBridgeClientTests.swift -- encoding, error handling, MockURLProtocol
```
