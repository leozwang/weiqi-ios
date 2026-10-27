import XCTest

/// Board tests: what the player sees on the board after real taps (Android T4, T6, T14).
/// Stones are read from screenshots, the engine's komi and handicap from the engine status.
final class BoardUITests: WeiqiUITestCase {

    /// Handicap None and 1–9 (Android T4): the stones on screen are exactly the standard star points,
    /// komi is 7.5 without and 0.5 with handicap, the right side moves first, and Undo is off.
    func testEveryHandicapLevelOnTheBoard() {
        let corners: Set<String> = ["D4", "Q16", "D16", "Q4"]
        let expected: [Int: Set<String>] = [
            0: [], 1: ["Q16"], 2: ["D4", "Q16"], 3: ["D4", "Q16", "D16"], 4: corners,
            5: corners.union(["K10"]), 6: corners.union(["D10", "Q10"]), 7: corners.union(["D10", "Q10", "K10"]),
            8: corners.union(["D10", "Q10", "K16", "K4"]), 9: corners.union(["D10", "Q10", "K16", "K4", "K10"]),
        ]
        for n in 0...9 {
            startNewGame(mode: "Two Players", handicap: n)   // Two Players: nobody moves by itself
            XCTAssertTrue(waitForState(move: 0, turn: n == 0 ? "B" : "W", timeout: 30), "handicap \(n): \(describeState())")
            XCTAssertTrue(waitForEngine(["komi": n == 0 ? "7.5" : "0.5", "handicap": "\(n)"]),
                          "handicap \(n): engine got \(engineStatusText())")
            let stones = boardStones()
            XCTAssertEqual(Set(stones.filter { $0.value == "B" }.keys), expected[n], "handicap \(n): stones on screen")
            XCTAssertFalse(stones.values.contains("W"), "handicap \(n): no White stones yet")
            XCTAssertFalse(actionButton("Undo").isEnabled, "handicap \(n): nothing to undo")
        }
    }

    /// Taps land on the right point (Android T6, T14a): A19, J10 and T1 (no column I, rows counted
    /// from the bottom), colors alternate, and an occupied point cannot be selected.
    func testPlacingStonesAndCoordinates() {
        startNewGame(mode: "Two Players")
        XCTAssertTrue(waitForState(move: 0, turn: "B", timeout: 30), describeState())
        play("A19")
        XCTAssertTrue(waitForState(move: 1, turn: "W", timeout: 15), describeState())
        play("J10")
        XCTAssertTrue(waitForState(move: 2, turn: "B", timeout: 15), describeState())
        play("T1")
        XCTAssertTrue(waitForState(move: 3, turn: "W", timeout: 15), describeState())
        XCTAssertEqual(boardStones(), ["A19": "B", "J10": "W", "T1": "B"], "stones must appear exactly where tapped")

        tapPoint("J10")
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertFalse(app.buttons["PLACE"].isEnabled, "an occupied point must not be selectable")
        XCTAssertEqual(moveNumber(), 3)
    }

    /// Illegal moves are refused on the board (Android T14b/c, M2): an immediate ko retake and a
    /// multi-stone suicide show "Illegal move" and change nothing; the retake is legal after a ko threat.
    func testIllegalMovesAreRefusedOnTheBoard() {
        startNewGame(mode: "Two Players")
        XCTAssertTrue(waitForState(move: 0, turn: "B", timeout: 30), describeState())
        for (i, mv) in ["B19", "C19", "A18", "B18", "B17", "D18", "K10", "C17", "C18"].enumerated() {
            play(mv)
            XCTAssertTrue(waitUntil(15) { self.moveNumber() == i + 1 }, "\(mv): \(describeState())")
        }
        XCTAssertNil(boardStones()["B18"], "Black C18 must capture B18")
        // White may not retake the ko at once.
        play("B18")
        XCTAssertTrue(app.staticTexts["Illegal move"].waitForExistence(timeout: 5), "the ko retake must show Illegal move")
        XCTAssertTrue(waitForState(move: 9, turn: "W", timeout: 5), "a refused move must not count: \(describeState())")
        XCTAssertEqual(boardStones()["C18"], "B", "nothing may change after a refused move")
        // After a ko threat and an answer the retake is legal.
        play("K4")
        XCTAssertTrue(waitForState(move: 10, turn: "B", timeout: 15), describeState())
        play("Q16")
        XCTAssertTrue(waitForState(move: 11, turn: "W", timeout: 15), describeState())
        play("B18")
        XCTAssertTrue(waitForState(move: 12, turn: "B", timeout: 15), "the retake after a threat is legal: \(describeState())")
        XCTAssertNil(boardStones()["C18"], "White B18 must capture C18")

        startNewGame(mode: "Two Players")
        XCTAssertTrue(waitForState(move: 0, turn: "B", timeout: 30), describeState())
        for (i, mv) in ["A1", "A2", "K10", "B2", "K11", "C1"].enumerated() {
            play(mv)
            XCTAssertTrue(waitUntil(15) { self.moveNumber() == i + 1 }, "\(mv): \(describeState())")
        }
        play("B1")   // would join A1 into a two-stone group without liberties
        XCTAssertTrue(app.staticTexts["Illegal move"].waitForExistence(timeout: 5), "multi-stone suicide must show Illegal move")
        XCTAssertTrue(waitForState(move: 6, turn: "B", timeout: 5), describeState())
        XCTAssertEqual(boardStones()["A1"], "B", "the suicide attempt must not remove A1")
        XCTAssertNil(boardStones()["B1"])
    }
}
