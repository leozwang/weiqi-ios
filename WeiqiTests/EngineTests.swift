import XCTest

/// Engine-level tests: they drive the real KataGo engine (Metal backend, bundled model and
/// gtp.cfg) through the same Objective-C++ bridge the app uses. They run inside the app as
/// test host; GameView stays idle in that case (see GameView.onAppear), so nothing else
/// talks to the shared engine while these commands run.
final class EngineTests: XCTestCase {
    static var engine: KataGoWrapper!

    override class func setUp() {
        super.setUp()
        engine = KataGoWrapper()
        let cfg = Bundle.main.path(forResource: "gtp", ofType: "cfg")!
        let model = Bundle.main.path(forResource: "model", ofType: "bin.gz")!
        let storage = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.path
        let status = engine.initEngine(withConfig: cfg, model: model, storage: storage)
        precondition(status == 0, "KataGo engine failed to initialize: \(status)")
    }

    // MARK: - Helpers

    @discardableResult
    func gtp(_ cmd: String) -> String { Self.engine.sendGtpCommand(cmd) ?? "" }

    func stones() -> (black: Int, white: Int) {
        let res = gtp("get_board")
        let grid = res.dropFirst(2).split(separator: " ").first.map(String.init) ?? ""
        return (grid.filter { $0 == "1" }.count, grid.filter { $0 == "2" }.count)
    }

    func analysisRoot() throws -> [String: Any] {
        let res = gtp("kata-get-analysis black")
        XCTAssertTrue(res.hasPrefix("="), res)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(res.dropFirst(2).utf8)) as? [String: Any])
        return try XCTUnwrap(json["rootInfo"] as? [String: Any])
    }

    /// Visits KataGo spent on its reply in a fresh game (no search tree to reuse) after Black opened at
    /// `opening`: the whole search, which the level's budget limits, and the subtree of the move it chose.
    func searchVisits(budget: Int, opening: String) throws -> (search: Int, chosenMove: Int) {
        XCTAssertTrue(gtp("set_max_visits \(budget)").hasPrefix("="))
        gtp("clear_board")
        gtp("komi 7.5")
        XCTAssertTrue(gtp("play black \(opening)").hasPrefix("="))
        let mv = gtp("genmove white")
        XCTAssertTrue(mv.hasPrefix("="), mv)
        let search = try XCTUnwrap(Int(gtp("get_last_search_visits").dropFirst(2)))
        let chosenMove = try XCTUnwrap(analysisRoot()["visits"] as? Int)
        return (search, chosenMove)
    }

    func turnRefusals() -> Int { Int(gtp("get_turn_refusals").dropFirst(2)) ?? -1 }

    // MARK: - Tests

    /// GameView skips engine start-up when this variable is set; if Xcode stops setting it,
    /// the host app would play moves while these tests run.
    func testHostAppStaysIdleDuringEngineTests() {
        XCTAssertNotNil(ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"])
    }

    /// Difficulty (Android T13): every level's budget caps KataGo's search for its move, and each
    /// level searches clearly more (over 1.5x) than the one below it. Openings Q16 and D4.
    func testDifficultyLevelControlsSearchBudget() throws {
        // The search stops at the budget; search threads that already started a playout finish it.
        let threads = try XCTUnwrap(Int(gtp("kata-get-param numSearchThreads").dropFirst(2)))
        var previous: (level: String, visits: Int)?
        for (level, budget) in [("Easy", 100), ("Amateur", 500), ("Advanced", 1000), ("Pro", 2500)] {
            let results = try ["Q16", "D4"].map { try searchVisits(budget: budget, opening: $0) }
            print("visits: \(level)(\(budget)) search=\(results.map(\.search)) chosen move=\(results.map(\.chosenMove))")
            for result in results {
                XCTAssertGreaterThanOrEqual(result.search, budget, "\(level): the search must use its whole budget")
                XCTAssertLessThanOrEqual(result.search, budget + threads, "\(level): the search must stop at the budget")
                XCTAssertLessThanOrEqual(result.chosenMove, budget, "\(level): the move must use at most the budget")
            }
            let visits = results.map(\.search).min()!
            if let previous = previous {
                XCTAssertGreaterThan(Double(visits), 1.5 * Double(previous.visits),
                                     "\(level) must search clearly more than \(previous.level)")
            }
            previous = (level, visits)
        }
    }

    /// Handicap: stones are placed for Black, White moves first, and undo never removes them.
    func testHandicapSetupSurvivesUndo() {
        gtp("set_max_visits 50")
        gtp("clear_board")
        gtp("komi 0.5")
        let h = gtp("fixed_handicap 2")
        XCTAssertTrue(h.hasPrefix("="), h)
        XCTAssertEqual(stones().black, 2)
        XCTAssertTrue(gtp("genmove white").hasPrefix("="), "White must be the side to move after handicap")
        XCTAssertTrue(gtp("play black A19").hasPrefix("="))
        XCTAssertTrue(gtp("undo").hasPrefix("="))
        XCTAssertTrue(gtp("undo").hasPrefix("="))
        XCTAssertEqual(stones().black, 2)
        XCTAssertEqual(stones().white, 0)
        XCTAssertTrue(gtp("undo").hasPrefix("?"), "cannot undo past the handicap setup")
    }

    /// Scoring: final_score must report a valid result and must not alter the game's komi.
    func testFinalScoreIsRoundedAndKeepsKomi() throws {
        gtp("set_max_visits 100")
        gtp("clear_board")
        gtp("komi 7.5")
        // Lopsided position: White passes four times, Black takes all four corners.
        for mv in ["D4", "Q16", "D16", "Q4"] {
            XCTAssertTrue(gtp("play black \(mv)").hasPrefix("="))
            XCTAssertTrue(gtp("play white pass").hasPrefix("="))
        }
        gtp("think black 300")
        let before = try XCTUnwrap(analysisRoot()["scoreLead"] as? Double)
        let result = gtp("final_score")
        print("final_score=\(result) leadBefore=\(before)")
        XCTAssertNotNil(result.range(of: #"^= (B|W)\+\d+\.5$"#, options: .regularExpression),
                        "komi 7.5 => result must end in .5, got '\(result)'")
        XCTAssertEqual(gtp("get_komi"), "= 7.5", "final_score must restore the game's komi")
        gtp("think black 300")
        let after = try XCTUnwrap(analysisRoot()["scoreLead"] as? Double)
        XCTAssertEqual(before, after, accuracy: 4.0, "score lead jumped after final_score => komi was altered")
    }

    /// Play-as safety: an out-of-turn request must be refused, not silently wipe the game record.
    /// Each refusal is counted; the UI tests check that count stays 0 (turn-order audit, Android T19).
    func testOutOfTurnRequestsKeepHistory() {
        gtp("set_max_visits 50")
        gtp("clear_board")
        gtp("komi 7.5")
        let refusalsBefore = turnRefusals()
        XCTAssertTrue(gtp("play black Q16").hasPrefix("="))
        XCTAssertTrue(gtp("play white D4").hasPrefix("="))
        XCTAssertTrue(gtp("genmove white").hasPrefix("?"), "out-of-turn genmove must be rejected")
        XCTAssertTrue(gtp("play white Q4").hasPrefix("?"), "out-of-turn play must be rejected")
        XCTAssertEqual(turnRefusals(), refusalsBefore + 2, "both refusals must be counted")
        XCTAssertTrue(gtp("undo").hasPrefix("="))
        XCTAssertTrue(gtp("undo").hasPrefix("="))
        XCTAssertEqual(stones().black + stones().white, 0, "move history was lost")
    }

    /// Rules: the app advertises Chinese rules, so multi-stone suicide must be illegal
    /// (it is legal under the Tromp-Taylor rules the app used before 1.15).
    func testMultiStoneSuicideIsIllegal() {
        gtp("set_max_visits 50")
        gtp("clear_board")
        gtp("komi 7.5")
        // Black A1 is walled in by White A2, B2, C1. Black B1 would join A1 into a two-stone
        // group with no liberties that captures nothing.
        let setup = [("black", "A1"), ("white", "A2"), ("black", "K10"), ("white", "B2"), ("black", "K11"), ("white", "C1")]
        for (color, mv) in setup {
            XCTAssertTrue(gtp("play \(color) \(mv)").hasPrefix("="), "\(color) \(mv)")
        }
        XCTAssertEqual(gtp("play black B1"), "? illegal move")
    }

    // MARK: - Difficulty levels

    /// Every level of the New Game sheet must reach the engine as its search limit.
    func testEveryDifficultyLevelReachesTheEngine() {
        for (level, visits) in [("Easy", 100), ("Amateur", 500), ("Advanced", 1000), ("Pro", 2500)] {
            XCTAssertTrue(gtp("set_max_visits \(visits)").hasPrefix("="), level)
            XCTAssertEqual(gtp("kata-get-param maxVisits"), "= \(visits)", level)
            XCTAssertEqual(gtp("kata-get-param maxPlayouts"), "= \(visits)", level)
        }
    }

    // MARK: - Handicap levels

    /// Black stones on the board, as GTP coordinates.
    func blackStoneCoordinates() -> Set<String> {
        let letters = Array("ABCDEFGHJKLMNOPQRST")
        let grid = Array(gtp("get_board").dropFirst(2).split(separator: " ").first ?? "")
        var result = Set<String>()
        for (i, c) in grid.enumerated() where c == "1" {
            result.insert("\(letters[i % 19])\(19 - i / 19)")
        }
        return result
    }

    func sideToMove() -> String {
        String(gtp("get_board").split(separator: " ").last ?? "")
    }

    /// Handicap 1–9 (the New Game stepper range) must use the standard star points, give White
    /// the first move, and keep the stones when there is nothing to undo.
    func testEveryHandicapLevelPlacesTheStandardStones() {
        let corners4: Set<String> = ["D4", "Q16", "D16", "Q4"]
        let expected: [Int: Set<String>] = [
            1: ["Q16"],
            2: ["D4", "Q16"],
            3: ["D4", "Q16", "D16"],
            4: corners4,
            5: corners4.union(["K10"]),
            6: corners4.union(["D10", "Q10"]),
            7: corners4.union(["D10", "Q10", "K10"]),
            8: corners4.union(["D10", "Q10", "K16", "K4"]),
            9: corners4.union(["D10", "Q10", "K16", "K4", "K10"]),
        ]
        for n in 1...9 {
            gtp("clear_board")
            gtp("komi 0.5")
            XCTAssertTrue(gtp("fixed_handicap \(n)").hasPrefix("="), "handicap \(n)")
            XCTAssertEqual(blackStoneCoordinates(), expected[n], "handicap \(n) stones")
            XCTAssertEqual(sideToMove(), "W", "handicap \(n): White moves first")
            XCTAssertEqual(gtp("get_komi"), "= 0.5", "handicap \(n) komi")
            XCTAssertTrue(gtp("undo").hasPrefix("?"), "handicap \(n): nothing to undo")
            XCTAssertEqual(blackStoneCoordinates().count, n, "handicap \(n): stones must stay")
        }
    }

    // MARK: - Ko

    func testImmediateKoRecaptureIsIllegal() {
        gtp("set_max_visits 50")
        gtp("clear_board")
        gtp("komi 7.5")
        // Ko in the top-left corner: Black B19 A18 B17, White C19 B18 D18 C17.
        let setup = [("black", "B19"), ("white", "C19"), ("black", "A18"), ("white", "B18"),
                     ("black", "B17"), ("white", "D18"), ("black", "K10"), ("white", "C17")]
        for (color, mv) in setup {
            XCTAssertTrue(gtp("play \(color) \(mv)").hasPrefix("="), "\(color) \(mv)")
        }
        XCTAssertTrue(gtp("play black C18").hasPrefix("="), "Black takes the ko")
        XCTAssertEqual(gtp("play white B18"), "? illegal move", "White may not retake the ko immediately")
        XCTAssertTrue(gtp("play white K4").hasPrefix("="), "a ko threat elsewhere is fine")
    }

    // MARK: - Score accuracy

    /// Plays out a finished game whose area score is known exactly: Black owns every point with
    /// x + y >= 18 (190 points), White every point with x + y <= 17 (171 points). Each side is one
    /// group with two one-point eyes, filled from its own corner outwards, so nothing is ever
    /// captured or in doubt. Moves alternate; a side with no stones left passes. Ends with two passes.
    func playFinishedDiagonalGame(firstToMove: String, blackStonesAlreadyPlaced: Set<String> = []) {
        let letters = Array("ABCDEFGHJKLMNOPQRST")
        func coord(_ x: Int, _ y: Int) -> String { "\(letters[x])\(19 - y)" }
        func points(_ sums: [Int]) -> [String] {
            sums.flatMap { s in (0...18).compactMap { x in (0...18).contains(s - x) ? coord(x, s - x) : nil } }
        }
        let blackEyes: Set<String> = [coord(18, 18), coord(16, 18)]
        let whiteEyes: Set<String> = [coord(0, 0), coord(2, 0)]
        let black = points(Array(stride(from: 36, through: 18, by: -1)))
            .filter { !blackEyes.contains($0) && !blackStonesAlreadyPlaced.contains($0) }
        let white = points(Array(0...17)).filter { !whiteEyes.contains($0) }

        var queues = ["black": black[...], "white": white[...]]
        var color = firstToMove
        while !(queues["black"]!.isEmpty && queues["white"]!.isEmpty) {
            let move = queues[color]!.popFirst() ?? "pass"
            let res = gtp("play \(color) \(move)")
            XCTAssertTrue(res.hasPrefix("="), "\(color) \(move): \(res)")
            if !res.hasPrefix("=") { return }
            color = color == "black" ? "white" : "black"
        }
        XCTAssertTrue(gtp("play \(color) pass").hasPrefix("="))
        XCTAssertTrue(gtp("play \(color == "black" ? "white" : "black") pass").hasPrefix("="))
    }

    /// Even game, Chinese area scoring: 190 - 171 = Black +19, minus 7.5 komi = B+11.5.
    func testScoreEvenGameMatchesExactAreaCount() {
        gtp("set_max_visits 100")
        gtp("clear_board")
        gtp("komi 7.5")
        playFinishedDiagonalGame(firstToMove: "black")
        let (black, white) = stones()
        XCTAssertEqual(black, 188)
        XCTAssertEqual(white, 169)
        XCTAssertEqual(gtp("final_score"), "= B+11.5")
        XCTAssertEqual(gtp("get_komi"), "= 7.5", "scoring must not change the komi")
    }

    /// Undo at game over, then pass again (Android T15): the same position gets the same result.
    func testUndoAtGameOverThenPassGivesTheSameScore() {
        gtp("set_max_visits 100")
        gtp("clear_board")
        gtp("komi 7.5")
        playFinishedDiagonalGame(firstToMove: "black")
        XCTAssertEqual(gtp("final_score"), "= B+11.5")
        XCTAssertTrue(gtp("undo").hasPrefix("="), "take back the last pass, as Undo does after game over")
        let side = sideToMove() == "B" ? "black" : "white"
        XCTAssertTrue(gtp("play \(side) pass").hasPrefix("="))
        XCTAssertEqual(gtp("final_score"), "= B+11.5", "the same position must get the same result")
        XCTAssertEqual(gtp("get_komi"), "= 7.5")
    }

    /// Handicap 2 as the app plays it (komi 0.5). Chinese rules also give White 1 point per
    /// handicap stone: 19 - 0.5 - 2 = B+16.5 (it would be B+18.5 without that compensation).
    func testScoreHandicapGameIncludesChineseCompensation() {
        gtp("set_max_visits 100")
        gtp("clear_board")
        gtp("komi 0.5")
        XCTAssertTrue(gtp("fixed_handicap 2").hasPrefix("="))
        playFinishedDiagonalGame(firstToMove: "white", blackStonesAlreadyPlaced: ["D4", "Q16"])
        let (black, white) = stones()
        XCTAssertEqual(black, 188)
        XCTAssertEqual(white, 169)
        XCTAssertEqual(gtp("final_score"), "= B+16.5")
        XCTAssertEqual(gtp("get_komi"), "= 0.5", "scoring must not change the komi")
    }
}
