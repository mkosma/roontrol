# roontrol Claude instructions

## What this is

Swift menubar app (mbp) that intercepts F10-F19 keyDown events and routes
them to roon-bridge over HTTP. arm64, macOS 13+, no dock icon (LSUIElement).

## Key constraints

- **Karabiner does the media-key capture; roontrol's CGEventTap does the
  routing.** On macOS 13+ `mediaremoted` claims consumer media keys before
  any public CGEventTap can see them. Karabiner's HID driver sits *below*
  `mediaremoted`, so a Karabiner rule on non-built-in keyboards remaps the
  volume/mute keys (in BOTH consumer and f-key form) to bare F10/F11/F12
  before macOS acts. roontrol's CGEventTap then consumes those f-keys and
  routes to roon-bridge. The rule lives at `~/.config/karabiner/karabiner.json`
  (description starts "roontrol:"); it is NOT yet tracked in a repo.
  Without it, external-keyboard volume keys leak to macOS system volume.
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
