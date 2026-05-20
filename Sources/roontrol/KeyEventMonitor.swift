import AppKit
import CoreGraphics

/// KeyEventMonitor: intercepts F-keys and transport media keys.
///
/// Two CGEventTaps, both at `.cghidEventTap`:
///  - keyDown tap for F10-F19. roontrol acts only on keyboards that
///    deliver these as real keyDown keycodes. On mbp the external keyboard
///    is configured (Karabiner) to do that; the internal keyboard keeps
///    native media keys. F10-F12 = volume, F13-F19 = presets.
///  - NSSystemDefined tap for the transport media keys (previous /
///    play-pause / next, F7-F9 on a Mac keyboard). These arrive as
///    aux-control events, never as keyDown. roontrol consumes only the
///    transport keys and routes them to Roon; volume/mute media keys pass
///    through untouched and still drive macOS system volume.
/// See roontrol CLAUDE.md "Key constraints".
///
/// A tap returns nil to consume an event when routed; otherwise passes it
/// through unchanged. Both taps require Accessibility permission.
///
/// At-home detection: the tap callbacks read a non-isolated Bool flag
/// (atHomeFlag) which is updated from the main actor via NetworkProfile.
@MainActor
public class KeyEventMonitor {

    let bridgeClient: RoonBridgeClient
    let networkProfile: NetworkProfile
    let keyRouter: KeyRouter

    // Thread-safe flag readable from the non-isolated CGEventTap callbacks.
    // Updated on main actor but read safely from any thread (Bool is atomic on arm64).
    nonisolated(unsafe) var atHomeFlag: Bool = false

    // Tap handles are written from the MainActor (setup/stop) and read from
    // the non-isolated CGEventTap callback when the OS disables the tap.
    // The reads/writes don't race: setup completes before any callback can
    // fire, and stop() runs at terminate after all callbacks have drained.
    nonisolated(unsafe) fileprivate var functionTap: CFMachPort?
    nonisolated(unsafe) fileprivate var functionRunLoopSource: CFRunLoopSource?
    nonisolated(unsafe) fileprivate var mediaTap: CFMachPort?
    nonisolated(unsafe) fileprivate var mediaRunLoopSource: CFRunLoopSource?

    public init(bridgeClient: RoonBridgeClient, networkProfile: NetworkProfile) {
        self.bridgeClient = bridgeClient
        self.networkProfile = networkProfile
        self.keyRouter = KeyRouter(bridgeClient: bridgeClient)
    }

    public func start() {
        atHomeFlag = networkProfile.isAtHome

        networkProfile.onStatusChange = { [weak self] isAtHome in
            self?.atHomeFlag = isAtHome
        }

        setupFunctionKeyTap()
        setupMediaKeyTap()
    }

    public func stop() {
        teardownTap(&functionTap, &functionRunLoopSource)
        teardownTap(&mediaTap, &mediaRunLoopSource)
    }

    private func teardownTap(_ tap: inout CFMachPort?, _ source: inout CFRunLoopSource?) {
        if let t = tap {
            CGEvent.tapEnable(tap: t, enable: false)
            if let s = source {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes)
            }
        }
        tap = nil
        source = nil
    }

    // -------------------------------------------------------------------------
    // Function key tap (F10-F19 keyDown)
    // -------------------------------------------------------------------------

    private func setupFunctionKeyTap() {
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: functionKeyTapCallback,
            userInfo: selfPtr
        ) else {
            NSLog("[KeyEventMonitor] Could not create function key tap -- is Accessibility permission granted?")
            return
        }

        self.functionTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.functionRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[KeyEventMonitor] Function key tap installed at cghidEventTap")
    }

    // -------------------------------------------------------------------------
    // Media key tap (NSSystemDefined transport keys)
    // -------------------------------------------------------------------------

    private func setupMediaKeyTap() {
        // NSSystemDefined == CGEventType raw value 14; CGEventType has no
        // named case for it.
        let eventMask = CGEventMask(1 << 14)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: mediaKeyTapCallback,
            userInfo: selfPtr
        ) else {
            NSLog("[KeyEventMonitor] Could not create media key tap -- is Accessibility permission granted?")
            return
        }

        self.mediaTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.mediaRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[KeyEventMonitor] Media key tap installed at cghidEventTap")
    }
}

// -------------------------------------------------------------------------
// CGEventTap callback for F10-F19 keyDown
// -------------------------------------------------------------------------

private func functionKeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passRetained(event) }
    let monitor = Unmanaged<KeyEventMonitor>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = monitor.functionTap {
            CGEvent.tapEnable(tap: tap, enable: true)
            NSLog("[KeyEventMonitor] function tap re-enabled after \(type.rawValue)")
        }
        return Unmanaged.passRetained(event)
    }

    guard type == .keyDown else { return Unmanaged.passRetained(event) }

    let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
    guard KeyRouter.handlesKeyCode(keyCode) else {
        return Unmanaged.passRetained(event) // not one of ours
    }

    let flags = event.flags

    guard monitor.atHomeFlag else {
        NSLog("[KeyEventMonitor] F-key arrived but not at home")
        return Unmanaged.passRetained(event)
    }

    NSLog(String(
        format: "[KeyEventMonitor] routing F-key: %d flags=0x%llx fn=%@ ctrl=%@ opt=%@ cmd=%@ shift=%@",
        keyCode,
        flags.rawValue,
        flags.contains(.maskSecondaryFn) ? "Y" : "n",
        flags.contains(.maskControl) ? "Y" : "n",
        flags.contains(.maskAlternate) ? "Y" : "n",
        flags.contains(.maskCommand) ? "Y" : "n",
        flags.contains(.maskShift) ? "Y" : "n"
    ))
    DispatchQueue.main.async {
        monitor.keyRouter.routeFunctionKey(keyCode, modifiers: flags)
    }

    return nil // consume so the foreground app doesn't also receive F13...
}

// -------------------------------------------------------------------------
// CGEventTap callback for NSSystemDefined transport media keys
// -------------------------------------------------------------------------

private func mediaKeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passRetained(event) }
    let monitor = Unmanaged<KeyEventMonitor>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = monitor.mediaTap {
            CGEvent.tapEnable(tap: tap, enable: true)
            NSLog("[KeyEventMonitor] media tap re-enabled after \(type.rawValue)")
        }
        return Unmanaged.passRetained(event)
    }

    // Decode the aux-control event. A nil action means it is not a
    // transport key (volume, mute, brightness, ...) -- leave it untouched.
    guard let nsEvent = NSEvent(cgEvent: event),
          let mediaKey = MediaKeyEvent.decode(
              subtype: Int(nsEvent.subtype.rawValue),
              data1: nsEvent.data1
          ),
          let action = KeyRouter.transportActionForMediaKey(mediaKey.keyCode)
    else {
        return Unmanaged.passRetained(event)
    }

    // Away from home: leave transport keys to macOS Now Playing routing.
    guard monitor.atHomeFlag else {
        return Unmanaged.passRetained(event)
    }

    // Ours. Route the down edge to Roon; consume both edges so neither
    // the foreground app nor macOS Now Playing also reacts to the key.
    if mediaKey.isDown {
        NSLog("[KeyEventMonitor] routing transport media key: \(action.rawValue)")
        DispatchQueue.main.async {
            monitor.keyRouter.routeTransport(action)
        }
    }
    return nil
}

// -------------------------------------------------------------------------
// MediaKeyEvent: decode an NSSystemDefined aux-control button event
// -------------------------------------------------------------------------

/// A decoded NSSystemDefined aux-control event -- the media keys (play,
/// next, previous, volume, mute, ...). roontrol acts only on the transport
/// keys; it still decodes the rest so the tap knows what to pass through.
struct MediaKeyEvent: Equatable {
    /// NX_KEYTYPE_* code. 16 = play/pause, 17 = next, 18 = previous.
    let keyCode: Int
    /// True on the key-down edge, false on key-up.
    let isDown: Bool

    /// NX_SUBTYPE_AUX_CONTROL_BUTTONS -- the systemDefined subtype that
    /// carries media keys. Other subtypes (power key, etc.) are not ours.
    static let auxControlSubtype = 8

    /// Decodes an NSSystemDefined event's subtype and `data1` field.
    /// Returns nil if the event is not an aux-control button.
    ///
    /// `data1` layout for aux-control buttons:
    ///   bits 16-31 : key code (NX_KEYTYPE_*)
    ///   bits 8-15  : key state (0xA = down, 0xB = up)
    static func decode(subtype: Int, data1: Int) -> MediaKeyEvent? {
        guard subtype == auxControlSubtype else { return nil }
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let keyState = (data1 & 0x0000_FF00) >> 8
        return MediaKeyEvent(keyCode: keyCode, isDown: keyState == 0xA)
    }
}

// -------------------------------------------------------------------------
// Helper: NSEventModifierFlags -> CGEventFlags
// -------------------------------------------------------------------------

extension NSEvent.ModifierFlags {
    var toCGEventFlags: CGEventFlags {
        var flags = CGEventFlags()
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.command) { flags.insert(.maskCommand) }
        return flags
    }
}
