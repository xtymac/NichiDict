import XCTest
@testable import CoreKit

final class ScriptDetectorTests: XCTestCase {
    func testDetectKanji() {
        // Mixed kanji and hiragana
        let script = ScriptDetector.detect("食べる")
        XCTAssertEqual(script, .mixed)
    }
    
    func testDetectHiragana() {
        let script = ScriptDetector.detect("たべる")
        XCTAssertEqual(script, .hiragana)
    }
    
    func testDetectKatakana() {
        let script = ScriptDetector.detect("カタカナ")
        XCTAssertEqual(script, .katakana)
    }
    
    func testDetectRomaji() {
        let script = ScriptDetector.detect("taberu")
        XCTAssertEqual(script, .romaji)
    }
    
    func testDetectMixed() {
        let script = ScriptDetector.detect("食tab")
        XCTAssertEqual(script, .mixed)
    }
}
