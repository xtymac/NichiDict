import XCTest
@testable import CoreKit

final class RomajiConverterTests: XCTestCase {
    func testKanaToHepburnRomaji() {
        XCTAssertEqual(RomajiConverter.toRomaji("たべる"), "taberu")
        XCTAssertEqual(RomajiConverter.toRomaji("さくら"), "sakura")
        XCTAssertEqual(RomajiConverter.toRomaji("がっこう"), "gakkou")
    }
    
    func testKunreiToHepburnNormalization() {
        XCTAssertEqual(RomajiConverter.normalizeForSearch("si"), "shi")
        XCTAssertEqual(RomajiConverter.normalizeForSearch("ti"), "chi")
        XCTAssertEqual(RomajiConverter.normalizeForSearch("tu"), "tsu")
        XCTAssertEqual(RomajiConverter.normalizeForSearch("hu"), "fu")
    }
    
    func testLongVowelHandling() {
        let normalized1 = RomajiConverter.normalizeForSearch("toukyou")
        let normalized2 = RomajiConverter.normalizeForSearch("tookyoo")
        
        // Both should normalize to same form
        XCTAssertEqual(normalized1, normalized2)
    }
    
    func testConversionPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = RomajiConverter.toRomaji("konnichiwa")
            }
        }
    }
}
