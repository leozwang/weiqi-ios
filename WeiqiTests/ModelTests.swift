import XCTest
@testable import Weiqi

/// Settings and game-record persistence, and board coordinate conversion. These touch the app's
/// real UserDefaults keys, so the original values are restored after every test.
final class ModelTests: XCTestCase {
    private var savedSettings: Data?
    private var savedMoves: Data?
    private var savedResult: Data?

    override func setUp() {
        savedSettings = UserDefaults.standard.data(forKey: GameSettings.userDefaultsKey)
        savedMoves = UserDefaults.standard.data(forKey: PersistedMove.userDefaultsKey)
        savedResult = UserDefaults.standard.data(forKey: PersistedResult.userDefaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.set(savedSettings, forKey: GameSettings.userDefaultsKey)
        UserDefaults.standard.set(savedMoves, forKey: PersistedMove.userDefaultsKey)
        UserDefaults.standard.set(savedResult, forKey: PersistedResult.userDefaultsKey)
    }

    func testDefaultSettingsForFirstLaunch() {
        UserDefaults.standard.removeObject(forKey: GameSettings.userDefaultsKey)
        let settings = GameSettings.load()
        XCTAssertEqual(settings.mode, .userBlack)
        XCTAssertEqual(settings.handicap, 0)
        XCTAssertEqual(settings.visits, 500, "first launch plays at Amateur")
    }

    func testSettingsRoundTripForEveryModeHandicapAndLevel() {
        for mode in GameMode.allCases {
            for handicap in [0, 1, 5, 9] {
                for visits in [100, 500, 1000, 2500] {
                    var settings = GameSettings()
                    settings.mode = mode
                    settings.handicap = handicap
                    settings.visits = visits
                    settings.save()
                    let loaded = GameSettings.load()
                    XCTAssertEqual(loaded.mode, mode)
                    XCTAssertEqual(loaded.handicap, handicap)
                    XCTAssertEqual(loaded.visits, visits)
                }
            }
        }
    }

    /// Settings saved by older versions used other "Play As" titles; they must still load.
    func testLegacyPlayAsTitlesStillLoad() throws {
        let cases: [(String, GameMode)] = [
            ("You are Black", .userBlack), ("You're Black", .userBlack),
            ("You are White", .userWhite), ("You're White", .userWhite), ("You're white", .userWhite),
            ("Two Players", .userBoth), ("AI vs AI", .aiBoth), ("something unknown", .userBlack),
        ]
        for (title, mode) in cases {
            let json = #"{"mode":"\#(title)","handicap":3,"visits":1000,"modelName":"model.bin.gz"}"#
            let settings = try JSONDecoder().decode(GameSettings.self, from: Data(json.utf8))
            XCTAssertEqual(settings.mode, mode, title)
            XCTAssertEqual(settings.handicap, 3)
            XCTAssertEqual(settings.visits, 1000)
        }
    }

    func testGameRecordRoundTrip() {
        let moves = [
            PersistedMove(x: 3, y: 15, isPass: false, stone: Stone.black.rawValue),
            PersistedMove(x: -1, y: -1, isPass: true, stone: Stone.white.rawValue),
            PersistedMove(x: 18, y: 0, isPass: false, stone: Stone.black.rawValue),
        ]
        PersistedMove.saveAll(moves)
        let loaded = PersistedMove.loadAll()
        XCTAssertEqual(loaded.map(\.x), [3, -1, 18])
        XCTAssertEqual(loaded.map(\.y), [15, -1, 0])
        XCTAssertEqual(loaded.map(\.isPass), [false, true, false])
        XCTAssertEqual(loaded.map(\.stone), [1, 2, 1])
        PersistedMove.clear()
        XCTAssertTrue(PersistedMove.loadAll().isEmpty)
    }

    /// The result of a finished game is saved with the number of moves it belongs to, so a relaunch
    /// shows it again without scoring (Android T16).
    func testFinishedGameResultRoundTrip() {
        PersistedResult(moveCount: 3, result: "B+11.5").save()
        let loaded = PersistedResult.load()
        XCTAssertEqual(loaded?.moveCount, 3)
        XCTAssertEqual(loaded?.result, "B+11.5")
        PersistedResult.clear()
        XCTAssertNil(PersistedResult.load())
    }

    /// GTP columns skip the letter I; rows count from the bottom.
    func testBoardCoordinates() {
        XCTAssertEqual(CandidateMove(x: 0, y: 0, winrate: 0, visits: 0).gtpCoord, "A19")
        XCTAssertEqual(CandidateMove(x: 8, y: 9, winrate: 0, visits: 0).gtpCoord, "J10")
        XCTAssertEqual(CandidateMove(x: 18, y: 18, winrate: 0, visits: 0).gtpCoord, "T1")
        XCTAssertEqual(CandidateMove.fromGtpCoord("A19").map { [$0.0, $0.1] }, [0, 0])
        XCTAssertEqual(CandidateMove.fromGtpCoord("j10").map { [$0.0, $0.1] }, [8, 9])
        XCTAssertEqual(CandidateMove.fromGtpCoord("T1").map { [$0.0, $0.1] }, [18, 18])
        XCTAssertNil(CandidateMove.fromGtpCoord("pass"))
        XCTAssertNil(CandidateMove.fromGtpCoord("I5"), "there is no column I")
        XCTAssertNil(CandidateMove.fromGtpCoord("A20"))
    }
}
