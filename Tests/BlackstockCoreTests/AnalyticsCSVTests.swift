import XCTest
@testable import BlackstockCore

final class AnalyticsCSVTests: XCTestCase {
    func testEnglishYouTubeCSV() throws {
        let csv = "Video title,Views,Watch time (hours),Impressions,Impressions click-through rate\nA,1000,10.5,5000,4.2%\nB,500,5,2000,3%"
        let data = try AnalyticsCSVParser().parse(csv)
        XCTAssertEqual(data.views, 1500); XCTAssertEqual(data.impressions, 7000); XCTAssertEqual(data.rows.count, 2)
        XCTAssertEqual(data.watchTimeHours, 15.5, accuracy: 0.001)
    }
    func testGermanSemicolonCSV() throws {
        let csv = "Video Titel;Aufrufe;Wiedergabezeit (Stunden);Impressionen;Klickrate der Impressionen\nTest;1200;8,5;4000;5,0%"
        let data = try AnalyticsCSVParser().parse(csv)
        XCTAssertEqual(data.views, 1200); XCTAssertEqual(data.impressions, 4000); XCTAssertEqual(data.rows.first?.clickThroughRate ?? 0, 0.05, accuracy: 0.001)
    }
}
