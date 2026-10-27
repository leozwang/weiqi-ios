import XCTest

/// Game flow across the New Game sheet, passes, Undo and relaunches (Android T7–T10, T12, T17).
/// The engine status (Debug builds) shows what the engine actually got after each step.
final class GameFlowUITests: WeiqiUITestCase {

    // MARK: - Settings (Android T3, T17, P1, P10)

    /// First launch (Android T17): with no saved settings or game, the app starts a game as Black on
    /// Amateur without handicap, and New Game shows exactly those choices.
    func testFirstLaunchDefaults() {
        relaunch(environment: ["WEIQI_UITEST_RESET": "1"])
        XCTAssertTrue(waitForState(move: 0, turn: "B", timeout: 30), describeState())
        XCTAssertTrue(waitForEngine(["visits": "500", "komi": "7.5", "handicap": "0", "restored": "0"]), engineStatusText())
        XCTAssertEqual(playerNames(), ["Myself", "KataGo"])
        XCTAssertTrue(boardStones().isEmpty, "a first launch starts on an empty board")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(moveNumber(), 0, "KataGo (White) waits for my first move")

        openNewGameSheet()
        XCTAssertTrue(levelButton("Amateur").isSelected, "Amateur is the default level")
        XCTAssertTrue(isModeSelected("I'm Black"), "I'm Black is the default side")
        XCTAssertEqual(handicapLabel(), "No Handicap")
        cancelNewGameSheet()
    }

    /// Every level that can be played reaches the engine (Android T3, P1, P10): Easy 100, Amateur 500,
    /// and with Premium Advanced 1000 and Pro 2500. New Game reopens on the level being played. In
    /// Free, picking a locked level and cancelling changes nothing.
    func testEveryLevelAppliesToTheEngine() {
        var levels = [("Easy", "100"), ("Amateur", "500")]
        if paymentEnabled { levels += [("Advanced", "1000"), ("Pro", "2500")] }
        for (level, visits) in levels {
            startNewGame(mode: "Two Players", level: level)
            XCTAssertTrue(waitForEngine(["visits": visits]), "\(level): engine got \(engineStatusText())")
            openNewGameSheet()
            XCTAssertTrue(levelButton(level).isSelected, "New Game must reopen on \(level)")
            cancelNewGameSheet()
        }
        guard !paymentEnabled else { return }
        openNewGameSheet()
        for level in ["Advanced", "Pro"] {
            levelButton(level).tap()
            XCTAssertTrue(waitUntil(5) { !self.app.buttons["START GAME"].exists }, "\(level) must be locked")
        }
        cancelNewGameSheet()
        XCTAssertTrue(waitForEngine(["visits": "500"]), "a locked level must not reach the engine: \(engineStatusText())")
        openNewGameSheet()
        XCTAssertTrue(levelButton("Amateur").isSelected, "the level of the current game stays selected")
        cancelNewGameSheet()
    }

    /// Saved settings survive a relaunch (Android T17): after each relaunch the engine gets the saved
    /// level, komi and handicap, the game is the same, and New Game shows the saved choices.
    func testSettingsSurviveRelaunch() {
        struct Combo { let mode: String, level: String, visits: String, handicap: Int }
        let combos = [
            Combo(mode: "I'm White", level: paymentEnabled ? "Advanced" : "Amateur",
                  visits: paymentEnabled ? "1000" : "500", handicap: 3),
            Combo(mode: "Two Players", level: "Easy", visits: "100", handicap: 9),
            Combo(mode: "AI vs AI", level: paymentEnabled ? "Pro" : "Easy",
                  visits: paymentEnabled ? "2500" : "100", handicap: 0),
        ]
        for combo in combos {
            let name = "\(combo.mode), \(combo.level), handicap \(combo.handicap)"
            startNewGame(mode: combo.mode, level: combo.level, handicap: combo.handicap)
            XCTAssertTrue(waitForEngine(["visits": combo.visits, "handicap": "\(combo.handicap)"]), "\(name): \(engineStatusText())")
            if combo.mode == "AI vs AI" {
                XCTAssertTrue(waitUntil(120) { (self.moveNumber() ?? 0) >= 1 }, "\(name): self-play did not start")
            }
            let movesBefore = moveNumber() ?? 0

            relaunch()
            XCTAssertTrue(waitForEngine(["visits": combo.visits, "komi": combo.handicap > 0 ? "0.5" : "7.5",
                                         "handicap": "\(combo.handicap)"]), "\(name): after relaunch \(engineStatusText())")
            switch combo.mode {
            case "I'm White":
                XCTAssertTrue(waitForState(move: 0, turn: "W", timeout: 30), "\(name): \(describeState())")
                XCTAssertEqual(playerNames(), ["KataGo", "Myself"])
                XCTAssertEqual(boardStones(), ["D4": "B", "Q16": "B", "D16": "B"], "\(name): handicap stones after relaunch")
            case "Two Players":
                XCTAssertTrue(waitForState(move: 0, turn: "W", timeout: 30), "\(name): \(describeState())")
                XCTAssertEqual(boardStones().count, 9, "\(name): nine handicap stones after relaunch")
            default:
                XCTAssertTrue(waitUntil(120) { (self.moveNumber() ?? 0) > movesBefore },
                              "\(name): self-play must go on after the relaunch: \(describeState())")
            }

            openNewGameSheet()
            XCTAssertTrue(levelButton(combo.level).isSelected, "\(name): New Game must show the saved level")
            XCTAssertTrue(isModeSelected(combo.mode), "\(name): New Game must show the saved side")
            XCTAssertEqual(handicapLabel(), handicapText(combo.handicap), "\(name): New Game must show the saved handicap")
            cancelNewGameSheet()
        }
    }

    /// Cancel keeps the game (Android T9): changing level, side and handicap in New Game and then
    /// cancelling (or swiping the sheet away) leaves the game, the side and the level as they were.
    func testCancelNewGameKeepsTheGame() {
        startNewGame(mode: "I'm Black", level: "Easy")
        XCTAssertTrue(waitForState(move: 0, turn: "B", timeout: 30), describeState())
        play("A1")
        XCTAssertTrue(waitForState(move: 2, turn: "B", timeout: 60), "KataGo did not reply: \(describeState())")
        let before = boardStones()

        openNewGameSheet()
        levelButton("Amateur").tap()
        reveal(app.buttons["I'm White"])
        app.buttons["I'm White"].tap()
        setHandicap(4)
        cancelNewGameSheet()
        XCTAssertEqual(moveNumber(), 2)
        XCTAssertEqual(turn(), "B")
        XCTAssertEqual(boardStones(), before, "Cancel must not touch the board")
        XCTAssertEqual(playerNames(), ["Myself", "KataGo"])
        XCTAssertTrue(waitForEngine(["visits": "100", "komi": "7.5", "handicap": "0"]), engineStatusText())

        // The game goes on: I can place a stone and KataGo answers as White.
        play("T19")
        XCTAssertTrue(waitForState(move: 4, turn: "B", timeout: 60), describeState())
        XCTAssertEqual(boardStones()["T19"], "B")

        // Nothing of the cancelled choices was saved.
        openNewGameSheet()
        XCTAssertTrue(levelButton("Easy").isSelected)
        XCTAssertTrue(isModeSelected("I'm Black"))
        XCTAssertEqual(handicapLabel(), "No Handicap")

        // Swiping the sheet down is the same as Cancel. Drag all the way to the bottom of the
        // screen so iPad form sheets (taller in Free mode with the unlock banner) always dismiss.
        levelButton("Amateur").tap()
        let sheetTop = app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let screenBottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        sheetTop.press(forDuration: 0.05, thenDragTo: screenBottom, withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(waitUntil(10) { !self.levelButton("Easy").exists }, "swiping down must close the New Game sheet")
        XCTAssertEqual(moveNumber(), 4)
        XCTAssertTrue(waitForEngine(["visits": "100"]), engineStatusText())
    }

    // MARK: - Pass, Undo and game end (Android T7, T8)

    /// A pass against KataGo (Android T7): the pass goes in for my color, KataGo answers with a White
    /// stone, and the game goes on; a pass between moves never ends it. (KataGo does not pass back
    /// while it can still gain points, so the end of a game by two passes is tested in Two Players:
    /// GameplayUITests.testGameOverUndoAndRelaunch.)
    func testPassAgainstKataGo() {
        startNewGame(mode: "I'm Black", level: "Easy")
        XCTAssertTrue(waitForState(move: 0, turn: "B", timeout: 30), describeState())
        play("D4")
        XCTAssertTrue(waitForState(move: 2, turn: "B", timeout: 60), describeState())
        let before = boardStones()
        actionButton("Pass").tap()
        XCTAssertTrue(waitForState(move: 4, turn: "B", timeout: 60), "KataGo (White) must answer my pass: \(describeState())")
        let after = boardStones()
        XCTAssertEqual(after.filter { $0.value == "B" }.count, before.filter { $0.value == "B" }.count, "a pass adds no stone")
        XCTAssertEqual(after.filter { $0.value == "W" }.count, before.filter { $0.value == "W" }.count + 1,
                       "KataGo must answer with one White stone")
        XCTAssertFalse(app.alerts.firstMatch.exists, "one pass must not end the game")

        play("T19")
        XCTAssertTrue(waitForState(move: 6, turn: "B", timeout: 60), describeState())
        actionButton("Pass").tap()
        XCTAssertTrue(waitForState(move: 8, turn: "B", timeout: 60), "KataGo must answer the second pass too: \(describeState())")
        XCTAssertFalse(app.alerts.firstMatch.exists, "passes separated by moves must not end the game")
        XCTAssertEqual(boardStones()["T19"], "B")
    }

    /// Undo and Redo with a pass in the record (Android T8): Undo is off until I have moved; Undo takes
    /// back KataGo's reply together with my pass, KataGo does not move by itself, and Redo puts both
    /// back. I play White, so KataGo (Black, behind by komi) answers my pass with a move.
    func testUndoTakesBackAPass() {
        startNewGame(mode: "I'm White", level: "Easy")
        XCTAssertTrue(waitForState(move: 1, turn: "W", timeout: 60), "KataGo (Black) should open: \(describeState())")
        XCTAssertFalse(actionButton("Undo").isEnabled, "Undo must be off until I have moved")
        play("A1")
        XCTAssertTrue(waitForState(move: 3, turn: "W", timeout: 60), describeState())
        let beforePass = boardStones()
        actionButton("Pass").tap()
        XCTAssertTrue(waitForState(move: 5, turn: "W", timeout: 60), "KataGo must answer my pass with a move: \(describeState())")
        let afterPass = boardStones()
        XCTAssertEqual(afterPass.count, beforePass.count + 1, "a pass adds no stone, KataGo's reply adds one")

        actionButton("Undo").tap()
        XCTAssertTrue(waitForState(move: 3, turn: "W", timeout: 15), "Undo must take back my pass and the reply: \(describeState())")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(moveNumber(), 3, "KataGo must not move by itself after Undo")
        XCTAssertEqual(boardStones(), beforePass)

        actionButton("Redo").tap()
        XCTAssertTrue(waitForState(move: 5, turn: "W", timeout: 15), "Redo must put back my pass and the reply: \(describeState())")
        XCTAssertEqual(boardStones(), afterPass)
        XCTAssertTrue(actionButton("Pass").isEnabled, "after Redo it is my turn")
    }

    // MARK: - Save and restore (Android T10)

    /// Relaunch mid-game (Android T10): the position, the side to move and the passes come back, and
    /// KataGo does not move on my turn. Then the app is closed while KataGo is thinking: after the
    /// relaunch KataGo moves right away.
    func testRelaunchMidGameAndWhileKataGoThinks() {
        startNewGame(mode: "I'm White", level: "Easy")
        XCTAssertTrue(waitForState(move: 1, turn: "W", timeout: 60), describeState())
        play("A1")
        XCTAssertTrue(waitForState(move: 3, turn: "W", timeout: 60), describeState())
        actionButton("Pass").tap()
        XCTAssertTrue(waitForState(move: 5, turn: "W", timeout: 60), describeState())
        let stones = boardStones()

        relaunch()
        XCTAssertTrue(waitForEngine(["restored": "5"]), "all five moves, including the pass, must be replayed: \(engineStatusText())")
        XCTAssertTrue(waitForState(move: 5, turn: "W", timeout: 30), describeState())
        XCTAssertEqual(boardStones(), stones, "the same position after the relaunch")
        XCTAssertEqual(playerNames(), ["KataGo", "Myself"])
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(moveNumber(), 5, "KataGo must not move on my turn after the relaunch")
        actionButton("Undo").tap()
        XCTAssertTrue(waitForState(move: 3, turn: "W", timeout: 15), "the pass is part of the restored game: \(describeState())")

        // Close the app while KataGo thinks about its reply. Pro (Premium) or Amateur (Free) think long
        // enough to be caught; a few attempts in case KataGo was faster than the termination.
        let level = paymentEnabled ? "Pro" : "Amateur"
        var caughtThinking = false
        for (attempt, corner) in ["A1", "T19", "A19"].enumerated() where !caughtThinking {
            startNewGame(mode: "I'm Black", level: level)
            XCTAssertTrue(waitForState(move: 0, turn: "B", timeout: 30), describeState())
            play(corner)
            relaunch()
            caughtThinking = engineStatus()["restored"] == "1"
            XCTAssertTrue(waitForState(move: 2, turn: "B", timeout: 120),
                          "attempt \(attempt + 1): KataGo must have answered (before closing or after the relaunch): \(describeState())")
            let after = boardStones()
            XCTAssertEqual(after[corner], "B", "attempt \(attempt + 1): my move must survive")
            XCTAssertEqual(after.values.filter { $0 == "W" }.count, 1, "attempt \(attempt + 1): KataGo plays exactly one reply: \(after)")
        }
        XCTAssertTrue(caughtThinking, "could not close the app while KataGo was thinking (\(level))")
    }

    // MARK: - Stability (Android T12)

    /// A long self-play game (Android T12): KataGo keeps playing both sides for 30 moves (Pro with
    /// Premium, Amateur in Free) without a crash, memory levels off, and NEW GAME still works.
    func testLongSelfPlayStaysStable() {
        let level = paymentEnabled ? "Pro" : "Amateur"
        startNewGame(mode: "AI vs AI", level: level)
        XCTAssertTrue(waitUntil(300) { (self.moveNumber() ?? 0) >= 10 }, "self-play stalled: \(describeState())")
        let memAt10 = Int(engineStatus()["mem"] ?? "") ?? -1
        XCTAssertTrue(waitUntil(900) { (self.moveNumber() ?? 0) >= 30 }, "self-play stalled: \(describeState())")
        XCTAssertEqual(app.state, .runningForeground, "the app must not crash")
        let memAt30 = Int(engineStatus()["mem"] ?? "") ?? -1
        print("memory footprint: \(memAt10) MB at move 10, \(memAt30) MB at move 30 (\(level))")
        XCTAssertGreaterThan(memAt10, 0, engineStatusText())
        XCTAssertLessThan(memAt30 - memAt10, 150, "memory must level off: \(memAt10) MB -> \(memAt30) MB")
        XCTAssertGreaterThanOrEqual(boardStones().count, 20, "the self-play stones must be on the board")

        startNewGame(mode: "Two Players")
        XCTAssertTrue(waitForState(move: 0, turn: "B", timeout: 60), "NEW GAME must work after a long game: \(describeState())")
        XCTAssertTrue(boardStones().isEmpty)
    }
}
