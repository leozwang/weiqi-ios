import XCTest

/// Analysis mode (Android T11): KataGo's winrate, score lead and recommended moves appear for the
/// player to move and are refreshed after each move; tapping a recommendation previews it and
/// PLACE plays it.
final class AnalysisUITests: WeiqiUITestCase {

    /// A recommendation pill ("1, BEST, Q16, 48%, B+0.5") and the board coordinate in it.
    func candidate(_ rank: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", rank)).firstMatch
    }
    func coordinate(in label: String) -> String? {
        label.components(separatedBy: CharacterSet(charactersIn: ", ")).first {
            $0.range(of: #"^[A-HJ-T](1[0-9]|[1-9])$"#, options: .regularExpression) != nil
        }
    }

    func testAnalysisRecommendationsAndPlace() {
        startNewGame(mode: "I'm Black", level: "Easy")
        XCTAssertTrue(waitForState(move: 0, turn: "B", timeout: 30), describeState())
        let toggle = app.buttons["analysisToggle"]
        XCTAssertEqual(toggle.value as? String, "Off")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "On")
        XCTAssertTrue(app.staticTexts["Black Winrate"].waitForExistence(timeout: 10), "the winrate must show")
        XCTAssertTrue(app.staticTexts["Score Lead"].exists, "the score lead must show")
        let best = candidate("BEST")
        XCTAssertTrue(best.waitForExistence(timeout: 60), "KataGo must recommend moves")
        XCTAssertTrue(candidate("2nd").exists, "several moves are recommended")
        snapshot("analysis_on")

        // The guide explains the badges.
        app.buttons["Guide"].tap()
        let guide = app.alerts["Recommended Moves Guide"]
        XCTAssertTrue(guide.waitForExistence(timeout: 5))
        guide.buttons["Got it"].tap()

        // Tapping a pill previews that move; tapping the best badge on the board moves the preview there.
        guard let bestPoint = coordinate(in: best.label) else { return XCTFail("no coordinate in '\(best.label)'") }
        candidate("2nd").tap()
        XCTAssertTrue(waitUntil(5) { self.app.buttons["PLACE"].isEnabled }, "tapping a recommendation must preview it")
        tapPoint(bestPoint)
        Thread.sleep(forTimeInterval: 0.3)
        app.buttons["PLACE"].tap()

        // My stone is on the recommended point, KataGo replies, and new recommendations appear for my next move.
        XCTAssertTrue(waitUntil(60) { self.boardStones().count == 2 }, "KataGo did not reply: \(boardStones())")
        XCTAssertEqual(boardStones()[bestPoint], "B", "PLACE must play the recommended move \(bestPoint)")
        XCTAssertTrue(waitUntil(60) { self.candidate("BEST").exists && self.coordinate(in: self.candidate("BEST").label) != bestPoint },
                      "recommendations must be refreshed after the moves")

        // Analysis off: the status line is back.
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "Off")
        XCTAssertTrue(waitForState(move: 2, turn: "B", timeout: 10), describeState())
        XCTAssertFalse(app.staticTexts["Black Winrate"].exists)
        XCTAssertFalse(candidate("BEST").exists, "no recommendations with analysis off")
    }
}
