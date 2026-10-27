import XCTest

/// End-to-end gameplay tests: they launch the app, start games from the New Game sheet and
/// play on the board, exactly like a user. Each test starts its own game, so the saved game from
/// a previous run does not matter. Helpers live in WeiqiUITestCase.
final class GameplayUITests: WeiqiUITestCase {

    // MARK: - Play As

    func testPlayAsBlackUndoReturnsToMyTurn() {
        startNewGame(mode: "I'm Black")
        XCTAssertTrue(waitForState(move: 0, turn: "B", timeout: 30), describeState())
        play(15, 3)
        XCTAssertTrue(waitForState(move: 2, turn: "B", timeout: 60), "KataGo did not reply: \(describeState())")
        // My stone is where I tapped and KataGo answered with exactly one White stone.
        let stones = boardStones()
        XCTAssertEqual(stones["Q16"], "B", "my stone must be on Q16: \(stones)")
        XCTAssertEqual(stones.values.filter { $0 == "W" }.count, 1, "KataGo must reply with one White stone: \(stones)")
        actionButton("Undo").tap()
        XCTAssertTrue(waitForState(move: 0, turn: "B", timeout: 15),
                      "after Undo it should be my turn at move 0, got \(describeState())")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(moveNumber(), 0, "KataGo should not replay by itself after Undo")
        XCTAssertTrue(boardStones().isEmpty, "Undo must clear both stones")
        actionButton("Redo").tap()
        XCTAssertTrue(waitForState(move: 2, turn: "B", timeout: 15), "Redo should restore my move + reply: \(describeState())")
        XCTAssertEqual(boardStones(), stones, "Redo must put back the same two stones")
    }

    func testPlayAsWhiteKataGoOpensAndUndo() {
        startNewGame(mode: "I'm White")
        XCTAssertTrue(waitForState(move: 1, turn: "W", timeout: 60), "KataGo (Black) should open: \(describeState())")
        play(0, 0)
        XCTAssertTrue(waitForState(move: 3, turn: "W", timeout: 60), describeState())
        actionButton("Undo").tap()
        XCTAssertTrue(waitForState(move: 1, turn: "W", timeout: 15),
                      "after Undo it should be my turn at move 1, got \(describeState())")
    }

    func testTwoPlayersUndoIsOneMove() {
        startNewGame(mode: "Two Players")
        XCTAssertTrue(waitForState(move: 0, turn: "B", timeout: 30), describeState())
        play(0, 0)
        XCTAssertTrue(waitForState(move: 1, turn: "W", timeout: 15), describeState())
        play(18, 18)
        XCTAssertTrue(waitForState(move: 2, turn: "B", timeout: 15), describeState())
        actionButton("Undo").tap()
        XCTAssertTrue(waitForState(move: 1, turn: "W", timeout: 15), describeState())
        actionButton("Redo").tap()
        XCTAssertTrue(waitForState(move: 2, turn: "B", timeout: 15), describeState())
    }

    func testAIvsAINewGameAvailableAndNoStaleMoves() {
        startNewGame(mode: "AI vs AI")
        XCTAssertTrue(waitUntil(60) { (self.moveNumber() ?? 0) >= 2 }, "self-play did not start: \(describeState())")
        var disabled = 0
        for _ in 0..<12 {
            if !newGameButton().isEnabled { disabled += 1 }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertEqual(disabled, 0, "NEW GAME was disabled in \(disabled)/12 samples during AI vs AI")
        startNewGame(mode: "I'm Black")
        XCTAssertTrue(waitForState(move: 0, turn: "B", timeout: 30), describeState())
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(moveNumber(), 0, "a stale self-play move leaked into the new game: \(describeState())")
        XCTAssertEqual(turn(), "B")
        XCTAssertTrue(boardStones().isEmpty, "the new board must be empty")
    }

    /// Every mode: who is who, who moves first, and whether KataGo moves on its own.
    func testEveryPlayAsMode() {
        startNewGame(mode: "I'm Black")
        XCTAssertEqual(playerNames(), ["Myself", "KataGo"])
        XCTAssertTrue(waitForState(move: 0, turn: "B", timeout: 30), describeState())
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(moveNumber(), 0, "KataGo must wait for my first move")
        XCTAssertTrue(actionButton("Pass").isEnabled)

        startNewGame(mode: "I'm White")
        XCTAssertEqual(playerNames(), ["KataGo", "Myself"])
        XCTAssertTrue(waitForState(move: 1, turn: "W", timeout: 60), "KataGo (Black) must open: \(describeState())")
        XCTAssertEqual(boardStones().values.sorted(), ["B"], "KataGo plays Black, one stone")

        startNewGame(mode: "Two Players")
        XCTAssertEqual(playerNames(), ["Myself", "Myself"])
        XCTAssertTrue(waitForState(move: 0, turn: "B", timeout: 30), describeState())
        play(3, 3)
        XCTAssertTrue(waitForState(move: 1, turn: "W", timeout: 15), describeState())
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(moveNumber(), 1, "nobody moves for White in Two Players")
        XCTAssertTrue(actionButton("Pass").isEnabled, "White is a person too")

        startNewGame(mode: "AI vs AI")
        XCTAssertEqual(playerNames(), ["KataGo", "KataGo"])
        XCTAssertTrue(waitUntil(60) { (self.moveNumber() ?? 0) >= 4 }, "self-play must keep going: \(describeState())")
        XCTAssertFalse(actionButton("Pass").isEnabled, "nothing to pass for in AI vs AI")
        XCTAssertFalse(actionButton("Undo").isEnabled)
        XCTAssertFalse(actionButton("Redo").isEnabled)
    }

    /// Play As with handicap (Android T5): Two Players places both colors by hand and both can pass;
    /// AI vs AI starts with White and keeps playing.
    func testPlayAsWithHandicap() {
        startNewGame(mode: "Two Players", handicap: 2)
        XCTAssertTrue(waitForState(move: 0, turn: "W", timeout: 30), "handicap: White moves first: \(describeState())")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(moveNumber(), 0, "the AI never moves in Two Players")
        play("A1")
        XCTAssertTrue(waitForState(move: 1, turn: "B", timeout: 15), describeState())
        XCTAssertEqual(boardStones()["A1"], "W")
        actionButton("Pass").tap()
        XCTAssertTrue(waitForState(move: 2, turn: "W", timeout: 15), "Black can pass: \(describeState())")
        actionButton("Pass").tap()
        XCTAssertTrue(waitUntil(90) { self.app.alerts.firstMatch.exists }, "White can pass too; two passes end the game")
        app.alerts.firstMatch.buttons["BACK TO BOARD"].tap()

        startNewGame(mode: "AI vs AI", handicap: 2)
        XCTAssertTrue(waitForEngine(["komi": "0.5", "handicap": "2"]), engineStatusText())
        XCTAssertTrue(waitUntil(60) { (self.moveNumber() ?? 0) >= 3 }, "self-play with handicap must keep going: \(describeState())")
        let stones = boardStones()
        XCTAssertEqual(stones["D4"], "B")
        XCTAssertEqual(stones["Q16"], "B")
    }

    // MARK: - Handicap

    func testHandicapAsBlackKataGoOpensAndUndo() {
        startNewGame(mode: "I'm Black", handicap: 2)
        XCTAssertTrue(waitForState(move: 1, turn: "B", timeout: 60), "White (KataGo) should move first: \(describeState())")
        XCTAssertFalse(actionButton("Undo").isEnabled, "Undo must be disabled before I have moved")
        play(0, 0)
        XCTAssertTrue(waitForState(move: 3, turn: "B", timeout: 60), describeState())
        actionButton("Undo").tap()
        XCTAssertTrue(waitForState(move: 1, turn: "B", timeout: 15), "Undo should return to my turn: \(describeState())")
        let stones = boardStones()
        XCTAssertEqual(stones["D4"], "B", "Undo must never remove handicap stones")
        XCTAssertEqual(stones["Q16"], "B", "Undo must never remove handicap stones")
    }

    func testHandicapAsWhiteIMoveFirst() {
        startNewGame(mode: "I'm White", handicap: 3)
        XCTAssertTrue(waitForState(move: 0, turn: "W", timeout: 30), describeState())
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(moveNumber(), 0, "KataGo (Black) must wait for my first move")
        play(0, 0)
        XCTAssertTrue(waitForState(move: 2, turn: "W", timeout: 60), describeState())
    }

    /// Stepper limits (0...9), the explanation under Handicap, and the 1- and 9-stone games.
    func testHandicapBoundaries() {
        if app.alerts.firstMatch.exists { app.alerts.firstMatch.buttons.element(boundBy: 0).tap() }
        newGameButton().tap()
        openedSheetSelectingEasy()
        reveal(app.buttons["I'm Black"])
        app.buttons["I'm Black"].tap()
        setHandicap(0)
        let stepper = app.steppers.firstMatch
        stepper.buttons["Decrement"].tap()
        XCTAssertEqual(stepper.label, "No Handicap", "cannot go below 0")
        setHandicap(9)
        stepper.buttons["Increment"].tap()
        XCTAssertEqual(stepper.label, "9 Stones", "cannot go above 9")
        let footer = app.staticTexts["You play Black and receive the handicap stones. KataGo (White) moves first."]
        reveal(footer)  // below the fold on the iPad sheet when there is no purchase banner
        XCTAssertTrue(footer.exists, "the Handicap footer must say who receives the stones")
        app.buttons["START GAME"].tap()
        XCTAssertTrue(waitForState(move: 1, turn: "B", timeout: 60), "9 stones: KataGo (White) opens: \(describeState())")
        XCTAssertFalse(actionButton("Undo").isEnabled, "nothing of mine to undo yet")

        startNewGame(mode: "I'm White", handicap: 1)
        XCTAssertTrue(waitForState(move: 0, turn: "W", timeout: 30), "1 stone: I (White) move first: \(describeState())")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(moveNumber(), 0)
    }

    // MARK: - Screens for visual review (attached to the .xcresult bundle)

    func testCaptureHandicapScreens() {
        if app.alerts.firstMatch.exists { app.alerts.firstMatch.buttons.element(boundBy: 0).tap() }
        newGameButton().tap()
        openedSheetSelectingEasy()
        reveal(app.buttons["I'm White"])
        app.buttons["I'm White"].tap()
        setHandicap(2)
        snapshot("newgame_white_handicap2")
        reveal(app.buttons["I'm Black"])
        app.buttons["I'm Black"].tap()
        snapshot("newgame_black_handicap2")
        app.buttons["START GAME"].tap()
        XCTAssertTrue(waitForState(move: 1, turn: "B", timeout: 60), describeState())
        snapshot("game_black_handicap2_after_kata_opens")
    }

    // MARK: - Payment (the suite runs once with payment disabled and once enabled)

    func testPaymentGatesAdvancedAndProLevels() {
        if app.alerts.firstMatch.exists { app.alerts.firstMatch.buttons.element(boundBy: 0).tap() }
        newGameButton().tap()
        openedSheetSelectingEasy()
        let start = app.buttons["START GAME"]
        let banner = app.staticTexts["One-time purchase unlocks Advanced and Pro levels forever."]
        XCTAssertEqual(banner.exists, !paymentEnabled, "the purchase banner must show only before purchase")

        for level in ["Advanced", "Pro"] {
            levelButton(level).tap()
            if paymentEnabled {
                XCTAssertTrue(start.waitForExistence(timeout: 5), "\(level) must be playable after purchase")
                XCTAssertFalse(app.staticTexts["Unlock Elite Levels"].exists)
            } else {
                XCTAssertTrue(waitUntil(5) { !start.exists }, "\(level) must be locked without purchase")
                XCTAssertTrue(app.staticTexts["Unlock Elite Levels"].exists, "paywall missing for \(level)")
                XCTAssertTrue(app.buttons["Restore Purchases"].exists)
                let buy = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Unlock for' OR label == 'Load Store Info'")).firstMatch
                XCTAssertTrue(buy.exists, "purchase button missing for \(level)")
            }
        }
        snapshot("newgame_pro_payment_\(paymentEnabled ? "enabled" : "disabled")")

        // Free levels are always playable.
        for level in ["Easy", "Amateur"] {
            levelButton(level).tap()
            XCTAssertTrue(start.waitForExistence(timeout: 5), "\(level) must always be playable")
        }
        app.buttons["Cancel"].tap()
    }

    func testProGameWhenPurchased() throws {
        try XCTSkipUnless(paymentEnabled, "Pro is locked without purchase (checked by testPaymentGatesAdvancedAndProLevels)")
        startNewGame(mode: "I'm White", level: "Pro")
        XCTAssertTrue(waitForEngine(["visits": "2500"]), engineStatusText())
        XCTAssertTrue(waitForState(move: 1, turn: "W", timeout: 120), "KataGo (Black) should open at Pro: \(describeState())")
        play(0, 0)
        // Pro thinks for a while: Pass and PLACE stay off until it has replied (Android T6).
        let samples = assertControlsOffWhileKataGoThinks(aiTurn: "B")
        print("controls checked \(samples) times while KataGo (Pro) was thinking")
        XCTAssertTrue(waitForState(move: 3, turn: "W", timeout: 120), "KataGo should reply at Pro: \(describeState())")
    }

    // MARK: - Game end

    /// Two passes end the game (Android T7, T16, part of T15): a valid x.5 result, the board is locked,
    /// relaunch keeps the same result without scoring again or showing the dialog, Undo resumes play,
    /// passing again gives the same result, and NEW GAME works afterwards.
    func testGameOverUndoAndRelaunch() {
        startNewGame(mode: "Two Players")
        XCTAssertTrue(waitForState(move: 0, turn: "B", timeout: 30), describeState())
        play(3, 3)
        XCTAssertTrue(waitForState(move: 1, turn: "W", timeout: 15), describeState())
        actionButton("Pass").tap()
        XCTAssertTrue(waitForState(move: 2, turn: "B", timeout: 15), describeState())
        actionButton("Pass").tap()
        let alert = app.alerts.firstMatch
        var sawCounting = false
        XCTAssertTrue(waitUntil(90, poll: 0.05) {
            if self.app.staticTexts["Counting score…"].exists { sawCounting = true }
            return alert.exists
        }, "game did not end after two passes")
        XCTAssertTrue(sawCounting, "\"Counting score…\" must show while the score is counted")
        let message = alert.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Result'")).firstMatch.label
        print("game result: \(message)")
        XCTAssertNotNil(message.range(of: #"^Result: (B|W)\+\d+\.5$"#, options: .regularExpression),
                        "a 7.5-komi game must end with an x.5 result, got '\(message)'")
        let result = String(message.dropFirst("Result: ".count))
        alert.buttons["BACK TO BOARD"].tap()

        // The finished game stays on the board and is locked.
        XCTAssertTrue(app.staticTexts["Game Over"].waitForExistence(timeout: 5))
        tapPoint("K10")
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertFalse(app.buttons["PLACE"].isEnabled, "the board must be locked after the game")
        XCTAssertFalse(actionButton("Pass").isEnabled)

        relaunch()
        XCTAssertTrue(waitUntil(30) { self.app.staticTexts["Result: \(result)"].exists },
                      "relaunch must show the same result \(result): \(describeState())")
        XCTAssertFalse(app.staticTexts["Counting score…"].exists, "a finished game must not be scored again")
        XCTAssertFalse(app.alerts.firstMatch.exists, "re-opening a finished game should not pop the dialog again")

        actionButton("Undo").tap()
        XCTAssertTrue(waitForState(move: 2, turn: "B", timeout: 15), "Undo after game over should resume play: \(describeState())")
        XCTAssertTrue(actionButton("Pass").isEnabled)
        actionButton("Pass").tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 90), "passing again must end the game again")
        let again = alert.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Result'")).firstMatch.label
        XCTAssertEqual(again, "Result: \(result)", "the same position must get the same result")
        alert.buttons["NEW GAME"].tap()
        let start = app.buttons["START GAME"]
        XCTAssertTrue(levelButton("Easy").waitForExistence(timeout: 10), "NEW GAME must open the New Game sheet after game over")
        levelButton("Easy").tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(waitForState(move: 0, turn: "B", timeout: 30), "a new game must start after game over: \(describeState())")
    }
}
