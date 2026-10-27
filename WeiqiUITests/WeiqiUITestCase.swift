import XCTest

/// Base class of the UI tests: launches the app in the payment state of the test-plan configuration,
/// offers helpers to drive the New Game sheet and the board like a user, and reads back what happened:
/// - the status line ("Move N" + "Black/White to play", shown while analysis is off),
/// - the stones on the board, read from a screenshot,
/// - the engine status (Debug builds only): what the engine actually received (search limit, komi,
///   handicap) and how many out-of-turn requests it refused. This plays the role of the engine log
///   that the Android release tests read with logcat.
class WeiqiUITestCase: XCTestCase {
    var app: XCUIApplication!

    /// Payment state for this run: `WEIQI_PAYMENT=enabled|disabled` (default disabled). Weiqi.xctestplan
    /// sets it per configuration ("Free" = disabled, "Premium" = enabled), so every test runs in both.
    /// The app is launched with that purchase state pinned (Debug builds only, see StoreManager).
    let paymentEnabled = ProcessInfo.processInfo.environment["WEIQI_PAYMENT"] == "enabled"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["WEIQI_UITEST_PURCHASED"] = paymentEnabled ? "1" : "0"
        app.launch()
        waitForEngineReady()
    }

    /// Turn-order audit (Android T19): the app must never ask the engine to move or search for the
    /// color that is not to play. The engine counts such refusals since the app was launched.
    override func tearDownWithError() throws {
        guard let app = app, app.state == .runningForeground, let refused = engineStatus()["refused"] else { return }
        XCTAssertEqual(refused, "0", "the app asked the engine for the wrong color \(refused) time(s)")
    }

    /// Ready = the engine finished restoring the game (the engine status appears; works in any language)
    /// and the splash screen, which covers the board and buttons and swallows taps, is gone.
    func waitForEngineReady(file: StaticString = #filePath, line: UInt = #line) {
        let splash = app.images.matching(identifier: "splashScreen").firstMatch
        XCTAssertTrue(waitUntil(90) { !self.engineStatus().isEmpty && !splash.exists },
                      "engine never became ready", file: file, line: line)
        // The splash leaves the accessibility tree when its 0.5 s fade-out starts, but it keeps
        // catching taps until the fade has finished.
        Thread.sleep(forTimeInterval: 0.8)
    }

    /// Terminates and relaunches the app (same payment state). `environment` and `arguments` only
    /// apply to this launch (e.g. a reset or a language); later relaunches go back to the defaults.
    func relaunch(environment: [String: String] = [:], arguments: [String] = []) {
        app.terminate()
        let baseEnvironment = app.launchEnvironment
        app.launchEnvironment.merge(environment) { $1 }
        app.launchArguments = arguments
        app.launch()
        app.launchEnvironment = baseEnvironment
        app.launchArguments = []
        waitForEngineReady()
    }

    // MARK: - Status line and buttons

    func newGameButton() -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'NEW GAME'")).firstMatch
    }
    func actionButton(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }
    func moveNumber() -> Int? {
        let el = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Move '")).firstMatch
        guard el.exists else { return nil }
        return Int(el.label.dropFirst(5))
    }
    func turn() -> String? {
        if app.staticTexts["Black to play"].exists { return "B" }
        if app.staticTexts["White to play"].exists { return "W" }
        return nil
    }
    func describeState() -> String { "move=\(moveNumber().map(String.init) ?? "nil") turn=\(turn() ?? "nil")" }

    /// Names shown for Black (left) and White (right).
    func playerNames() -> [String] {
        let names = app.staticTexts.matching(NSPredicate(format: "label == 'Myself' OR label == 'KataGo'")).allElementsBoundByIndex
        return names.sorted { $0.frame.minX < $1.frame.minX }.map(\.label)
    }

    @discardableResult
    func waitUntil(_ timeout: TimeInterval, poll: TimeInterval = 0.25, _ cond: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if cond() { return true }
            Thread.sleep(forTimeInterval: poll)
        }
        return cond()
    }
    func waitForState(move: Int, turn t: String, timeout: TimeInterval) -> Bool {
        waitUntil(timeout) { self.moveNumber() == move && self.turn() == t }
    }

    // MARK: - Engine status (Debug builds only)

    /// "visits=500 komi=7.5 handicap=0 refused=0" as a dictionary; empty if not available.
    func engineStatus() -> [String: String] {
        let el = app.staticTexts.matching(identifier: "engineStatus").firstMatch
        guard el.exists else { return [:] }
        var result: [String: String] = [:]
        for pair in el.label.split(separator: " ") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { result[String(kv[0])] = String(kv[1]) }
        }
        return result
    }
    func engineStatusText() -> String {
        let el = app.staticTexts.matching(identifier: "engineStatus").firstMatch
        return el.exists ? el.label : "(no engine status)"
    }
    /// Waits until the engine reports these values, e.g. ["visits": "500", "komi": "7.5"].
    func waitForEngine(_ expected: [String: String], timeout: TimeInterval = 15) -> Bool {
        waitUntil(timeout) {
            let status = self.engineStatus()
            return expected.allSatisfy { status[$0.key] == $0.value }
        }
    }

    // MARK: - Board

    static let columns = Array("ABCDEFGHJKLMNOPQRST")
    /// GTP coordinate ("D4") to board indices (x from the left, y from the top).
    func point(_ gtp: String) -> (Int, Int) {
        let x = Self.columns.firstIndex(of: gtp.uppercased().first!)!
        return (x, 19 - Int(gtp.dropFirst())!)
    }
    func coordinate(_ x: Int, _ y: Int) -> String { "\(Self.columns[x])\(19 - y)" }

    /// A screenshot with pixel access, and the board frame found in it (bounding box of the wood colour).
    struct BoardImage {
        let pixels: [UInt8]
        let width: Int
        let height: Int
        let scale: CGFloat
        let rect: CGRect

        var step: CGFloat { (rect.width - 2 * rect.width * 0.015) / 18 }
        func center(_ x: Int, _ y: Int) -> CGPoint {
            let margin = rect.width * 0.015
            return CGPoint(x: rect.minX + margin + CGFloat(x) * step, y: rect.minY + margin + CGFloat(y) * step)
        }
        /// Average colour of a 3×3 pixel patch around a point (in points).
        func rgb(at p: CGPoint) -> (r: Int, g: Int, b: Int) {
            let cx = Int(p.x * scale), cy = Int(p.y * scale)
            var r = 0, g = 0, b = 0, n = 0
            for dy in -1...1 {
                for dx in -1...1 {
                    let x = min(max(cx + dx, 0), width - 1), y = min(max(cy + dy, 0), height - 1)
                    let i = (y * width + x) * 4
                    r += Int(pixels[i]); g += Int(pixels[i + 1]); b += Int(pixels[i + 2]); n += 1
                }
            }
            return (r / n, g / n, b / n)
        }
    }

    func captureBoard() -> BoardImage? {
        let shot = XCUIScreen.main.screenshot().image
        guard let cg = shot.cgImage else { return nil }
        let w = cg.width, h = cg.height
        let scale = CGFloat(w) / shot.size.width
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in stride(from: 0, to: h, by: 2) {
            for x in stride(from: 0, to: w, by: 2) {
                let i = (y * w + x) * 4
                if abs(Int(data[i]) - 245) < 14 && abs(Int(data[i + 1]) - 200) < 14 && abs(Int(data[i + 2]) - 110) < 20 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX > minX else { return nil }
        let rect = CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                          width: CGFloat(maxX - minX + 2) / scale, height: CGFloat(maxY - minY + 2) / scale)
        return BoardImage(pixels: data, width: w, height: h, scale: scale, rect: rect)
    }

    /// Stones on the board as seen on screen: GTP coordinate -> "B" or "W". Each point is sampled a
    /// little off its centre (towards the inside of the board, since edge stones reach past the wood),
    /// which avoids grid lines, star points and the last-move marker.
    func boardStones() -> [String: String] {
        guard let board = captureBoard() else { return [:] }
        var stones: [String: String] = [:]
        for y in 0..<19 {
            for x in 0..<19 {
                let c = board.center(x, y)
                let dx = board.step * (x == 18 ? -0.28 : 0.28), dy = board.step * (y == 18 ? -0.28 : 0.28)
                let (r, g, b) = board.rgb(at: CGPoint(x: c.x + dx, y: c.y + dy))
                if max(r, g, b) < 100 { stones[coordinate(x, y)] = "B" }
                else if min(r, g, b) > 200 { stones[coordinate(x, y)] = "W" }
            }
        }
        return stones
    }

    func tapPoint(_ x: Int, _ y: Int) {
        guard let board = captureBoard() else { return XCTFail("board not found on screen") }
        XCTAssertGreaterThan(board.rect.width, 100, "board not found on screen")
        let c = board.center(x, y)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: c.x, dy: c.y)).tap()
    }
    func tapPoint(_ gtp: String) { let (x, y) = point(gtp); tapPoint(x, y) }

    func play(_ x: Int, _ y: Int, file: StaticString = #filePath, line: UInt = #line) {
        tapPoint(x, y)
        let place = app.buttons["PLACE"]
        XCTAssertTrue(waitUntil(5) { place.isEnabled }, "board tap did not select a point (\(x),\(y))", file: file, line: line)
        place.tap()
    }
    func play(_ gtp: String, file: StaticString = #filePath, line: UInt = #line) {
        let (x, y) = point(gtp)
        play(x, y, file: file, line: line)
    }

    /// Call right after my move against KataGo (Android T6): while KataGo thinks (`aiTurn` to play),
    /// Pass and PLACE must stay off. The buttons are read before the turn, and the turn can only
    /// change from KataGo's to mine in between, so a hit is a real violation, never a race.
    /// Returns how many samples were taken while KataGo was thinking.
    @discardableResult
    func assertControlsOffWhileKataGoThinks(aiTurn: String, file: StaticString = #filePath, line: UInt = #line) -> Int {
        var samples = 0
        while samples < 20 {
            let passOn = actionButton("Pass").isEnabled
            let placeOn = app.buttons["PLACE"].isEnabled
            guard turn() == aiTurn else { break }
            XCTAssertFalse(passOn, "Pass must be off while KataGo thinks", file: file, line: line)
            XCTAssertFalse(placeOn, "PLACE must be off while KataGo thinks", file: file, line: line)
            samples += 1
        }
        return samples
    }

    // MARK: - New Game sheet

    func levelButton(_ level: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", level)).firstMatch
    }

    /// True when the Play As row is the selected one (selected trait or its checkmark).
    func isModeSelected(_ mode: String) -> Bool {
        let row = app.buttons[mode]
        reveal(row)
        return row.isSelected || row.images["checkmark"].exists || row.images["Selected"].exists
    }

    /// The New Game form only creates rows that are on screen (on the smaller iPad form sheet the
    /// Handicap row starts below the fold), so scroll until `element` can be tapped.
    func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let form = app.collectionViews.firstMatch
        for scrollDown in [true, false] {
            var swipes = 0
            while !(element.exists && element.isHittable) && swipes < 4 {
                if scrollDown { form.swipeUp() } else { form.swipeDown() }
                swipes += 1
            }
            if element.exists && element.isHittable { return }
        }
        XCTFail("could not scroll to \(element)", file: file, line: line)
    }

    func startNewGame(mode: String, level: String = "Easy", handicap: Int = 0) {
        if app.alerts.firstMatch.exists { app.alerts.firstMatch.buttons.element(boundBy: 0).tap() }
        let ng = newGameButton()
        XCTAssertTrue(waitUntil(30) { ng.isEnabled }, "NEW GAME never became enabled")
        ng.tap()
        // Pick the level first: the sheet reopens on the saved level, which is locked in Free if the
        // last game was Advanced/Pro (then the paywall replaces START GAME).
        let levelButton = levelButton(level)
        XCTAssertTrue(levelButton.waitForExistence(timeout: 10), "New Game sheet did not open")
        levelButton.tap()
        let start = app.buttons["START GAME"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "START GAME missing for \(level)")
        let modeButton = app.buttons[mode]
        reveal(modeButton)
        modeButton.tap()
        setHandicap(handicap)
        start.tap()
        XCTAssertTrue(waitUntil(10) { !self.app.buttons["START GAME"].exists })
    }

    /// Waits for the New Game sheet and selects Easy (always playable), so START GAME is shown.
    func openedSheetSelectingEasy() {
        let easy = levelButton("Easy")
        XCTAssertTrue(easy.waitForExistence(timeout: 10), "New Game sheet did not open")
        easy.tap()
        XCTAssertTrue(app.buttons["START GAME"].waitForExistence(timeout: 5))
    }

    /// Opens the New Game sheet without changing anything in it.
    func openNewGameSheet(file: StaticString = #filePath, line: UInt = #line) {
        if app.alerts.firstMatch.exists { app.alerts.firstMatch.buttons["BACK TO BOARD"].tap() }
        newGameButton().tap()
        XCTAssertTrue(levelButton("Easy").waitForExistence(timeout: 10), "New Game sheet did not open", file: file, line: line)
    }

    /// Closes the New Game sheet with Cancel.
    func cancelNewGameSheet(file: StaticString = #filePath, line: UInt = #line) {
        app.buttons["Cancel"].tap()
        XCTAssertTrue(waitUntil(10) { !self.levelButton("Easy").exists }, "the New Game sheet did not close", file: file, line: line)
    }

    /// The Handicap row of the New Game sheet: "No Handicap", "1 Stone", "3 Stones".
    func handicapLabel() -> String {
        let stepper = app.steppers.firstMatch
        reveal(stepper)
        return stepper.label
    }
    func handicapText(_ n: Int) -> String { n == 0 ? "No Handicap" : (n == 1 ? "1 Stone" : "\(n) Stones") }

    func setHandicap(_ n: Int) {
        let stepper = app.steppers.firstMatch
        reveal(stepper)
        func current() -> Int {
            let label = stepper.label.isEmpty ? (stepper.value as? String ?? "") : stepper.label
            return Int(label.split(separator: " ").first ?? "") ?? 0
        }
        var guardCount = 0
        while current() != n && guardCount < 20 {
            if current() < n { stepper.buttons["Increment"].tap() } else { stepper.buttons["Decrement"].tap() }
            guardCount += 1
        }
        XCTAssertEqual(current(), n, "could not set handicap (label '\(stepper.label)')")
    }

    // MARK: - Attachments

    func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
