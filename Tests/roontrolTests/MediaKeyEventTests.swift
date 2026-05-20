import XCTest
@testable import roontrol

/// Tests for MediaKeyEvent decoding of NSSystemDefined aux-control events.
///
/// `data1` layout for aux-control buttons:
///   bits 16-31 : key code (NX_KEYTYPE_*)
///   bits 8-15  : key state (0xA = down, 0xB = up)
final class MediaKeyEventTests: XCTestCase {

    /// Builds a data1 value the way the window server packs aux buttons.
    private func data1(keyCode: Int, state: Int) -> Int {
        (keyCode << 16) | (state << 8)
    }

    func testPlayPauseDown() {
        let event = MediaKeyEvent.decode(
            subtype: MediaKeyEvent.auxControlSubtype,
            data1: data1(keyCode: 16, state: 0xA)
        )
        XCTAssertEqual(event, MediaKeyEvent(keyCode: 16, isDown: true))
    }

    func testPlayPauseUp() {
        let event = MediaKeyEvent.decode(
            subtype: MediaKeyEvent.auxControlSubtype,
            data1: data1(keyCode: 16, state: 0xB)
        )
        XCTAssertEqual(event, MediaKeyEvent(keyCode: 16, isDown: false))
    }

    func testNextTrackDown() {
        let event = MediaKeyEvent.decode(
            subtype: MediaKeyEvent.auxControlSubtype,
            data1: data1(keyCode: 17, state: 0xA)
        )
        XCTAssertEqual(event, MediaKeyEvent(keyCode: 17, isDown: true))
    }

    func testPreviousTrackDown() {
        let event = MediaKeyEvent.decode(
            subtype: MediaKeyEvent.auxControlSubtype,
            data1: data1(keyCode: 18, state: 0xA)
        )
        XCTAssertEqual(event, MediaKeyEvent(keyCode: 18, isDown: true))
    }

    func testVolumeKeyStillDecodes() {
        // Volume up is NX_KEYTYPE_SOUND_UP (0); decoding succeeds so the
        // tap can recognize it as not-a-transport-key and pass it through.
        let event = MediaKeyEvent.decode(
            subtype: MediaKeyEvent.auxControlSubtype,
            data1: data1(keyCode: 0, state: 0xA)
        )
        XCTAssertEqual(event, MediaKeyEvent(keyCode: 0, isDown: true))
    }

    func testNonAuxSubtypeReturnsNil() {
        // Subtype 1 is the power key, not an aux-control button.
        XCTAssertNil(MediaKeyEvent.decode(subtype: 1, data1: data1(keyCode: 16, state: 0xA)))
    }
}
