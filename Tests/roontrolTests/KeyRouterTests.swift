import XCTest
import CoreGraphics
@testable import roontrol

/// Tests for KeyRouter modifier logic and F13-F19 mapping.
///
/// RoonBridgeClient is not called here -- we verify the static routing
/// decisions and keycode mapping only.
@MainActor
final class KeyRouterTests: XCTestCase {

    // -------------------------------------------------------------------------
    // F13-F19 keycode to preset index mapping
    // -------------------------------------------------------------------------

    func testF13MapsToPreset1() {
        XCTAssertEqual(KeyRouter.presetIndexForKeyCode(105), 1)
    }

    func testF14MapsToPreset2() {
        XCTAssertEqual(KeyRouter.presetIndexForKeyCode(107), 2)
    }

    func testF15MapsToPreset3() {
        XCTAssertEqual(KeyRouter.presetIndexForKeyCode(113), 3)
    }

    func testF16MapsToPreset4() {
        XCTAssertEqual(KeyRouter.presetIndexForKeyCode(106), 4)
    }

    func testF17MapsToPreset5() {
        XCTAssertEqual(KeyRouter.presetIndexForKeyCode(64), 5)
    }

    func testF18MapsToPreset6() {
        XCTAssertEqual(KeyRouter.presetIndexForKeyCode(79), 6)
    }

    func testF19MapsToPreset7() {
        XCTAssertEqual(KeyRouter.presetIndexForKeyCode(80), 7)
    }

    func testUnmappedKeycodeReturnsNil() {
        XCTAssertNil(KeyRouter.presetIndexForKeyCode(36))  // Return
        XCTAssertNil(KeyRouter.presetIndexForKeyCode(0))   // A
        XCTAssertNil(KeyRouter.presetIndexForKeyCode(122)) // F1
    }

    // -------------------------------------------------------------------------
    // Transport media key (NX_KEYTYPE_*) to TransportAction mapping
    // -------------------------------------------------------------------------

    func testPlayKeyMapsToPlaypause() {
        XCTAssertEqual(KeyRouter.transportActionForMediaKey(16), .playpause)
    }

    func testNextAndFastKeysMapToNext() {
        XCTAssertEqual(KeyRouter.transportActionForMediaKey(17), .next)  // NX_KEYTYPE_NEXT
        XCTAssertEqual(KeyRouter.transportActionForMediaKey(19), .next)  // NX_KEYTYPE_FAST
    }

    func testPreviousAndRewindKeysMapToPrev() {
        XCTAssertEqual(KeyRouter.transportActionForMediaKey(18), .prev)  // NX_KEYTYPE_PREVIOUS
        XCTAssertEqual(KeyRouter.transportActionForMediaKey(20), .prev)  // NX_KEYTYPE_REWIND
    }

    func testNonTransportMediaKeysReturnNil() {
        XCTAssertNil(KeyRouter.transportActionForMediaKey(0))  // NX_KEYTYPE_SOUND_UP
        XCTAssertNil(KeyRouter.transportActionForMediaKey(1))  // NX_KEYTYPE_SOUND_DOWN
        XCTAssertNil(KeyRouter.transportActionForMediaKey(7))  // NX_KEYTYPE_MUTE
    }
}
