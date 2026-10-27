import XCTest

/// Japanese and Simplified Chinese (Android T18, M5): the New Game sheet, the handicap line, the
/// status line and the Game Over dialog are fully translated. The app is launched in the language
/// with launch arguments, so the simulator's language is not changed. Screenshots are attached for
/// the visual check (M5: no clipped or overlapping text).
final class LocalizationUITests: WeiqiUITestCase {

    struct Language {
        let code: String, locale: String
        let newGame: String, sheetTitle: String, start: String, cancel: String
        let aiStrength: String, playAs: String, handicap: String, easy: String
        let imBlack: String, twoPlayers: String, noHandicap: String, twoStones: String, footer: String
        let move0: String, move1: String, blackToPlay: String, myself: String, pass: String
        let gameOver: String, backToBoard: String, resultPrefix: String
    }

    static let japanese = Language(
        code: "ja", locale: "ja_JP",
        newGame: "対局開始", sheetTitle: "新規対局", start: "対局開始", cancel: "キャンセル",
        aiStrength: "AI 強度", playAs: "手番", handicap: "置き石", easy: "入門",
        imBlack: "自分が黒番", twoPlayers: "二人対局", noHandicap: "置き石なし", twoStones: "2子",
        footer: "あなたが黒番で置き石を置きます。KataGo（白）が先に打ちます。",
        move0: "0手目", move1: "1手目", blackToPlay: "黒の番です", myself: "自分", pass: "パス",
        gameOver: "終局", backToBoard: "盤面に戻る", resultPrefix: "結果: ")

    static let chinese = Language(
        code: "zh-Hans", locale: "zh_CN",
        newGame: "新游戏", sheetTitle: "新对局", start: "开始对局", cancel: "取消",
        aiStrength: "AI 强度", playAs: "玩家持子", handicap: "让子", easy: "入门",
        imBlack: "我执黑", twoPlayers: "双人对弈", noHandicap: "不让子", twoStones: "让2子",
        footer: "你执黑并获得让子，KataGo（白）先行。",
        move0: "第0手", move1: "第1手", blackToPlay: "轮到黑方", myself: "我", pass: "停一手",
        gameOver: "棋局结束", backToBoard: "返回棋盘", resultPrefix: "结果：")

    /// English texts that must not be left anywhere in a translated screen. (Not "Undo"/"Redo": the
    /// system labels the arrow icons with those words.)
    static let english = ["NEW GAME", "START GAME", "Cancel", "New Game", "AI Strength", "Play As", "Handicap",
                          "Easy", "I'm Black", "Two Players", "No Handicap", "2 Stones", "Pass",
                          "PLACE", "Settings", "Analysis", "Game Over", "BACK TO BOARD", "Black to play", "Myself"]

    func testJapanese() { check(Self.japanese) }
    func testSimplifiedChinese() { check(Self.chinese) }

    func check(_ lang: Language) {
        relaunch(arguments: ["-AppleLanguages", "(\(lang.code))", "-AppleLocale", lang.locale])
        let newGame = app.buttons["newGame"]
        XCTAssertTrue(newGame.label.contains(lang.newGame), "NEW GAME button: '\(newGame.label)'")
        newGame.tap()

        // New Game sheet: title, sections, level, sides, handicap line, Cancel and START.
        XCTAssertTrue(app.navigationBars[lang.sheetTitle].waitForExistence(timeout: 10), "sheet title \(lang.sheetTitle)")
        let easy = levelButton(lang.easy)
        XCTAssertTrue(easy.exists, "level \(lang.easy)")
        easy.tap()
        XCTAssertTrue(app.buttons[lang.cancel].exists, "Cancel: \(lang.cancel)")
        let start = app.buttons["startGame"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertEqual(start.label, lang.start)
        for header in [lang.aiStrength, lang.playAs] {
            XCTAssertTrue(app.staticTexts[header].exists, "section header \(header)")
        }
        let imBlack = app.buttons[lang.imBlack]
        reveal(imBlack)
        imBlack.tap()
        setLocalizedHandicap(to: lang.twoStones, noHandicap: lang.noHandicap)
        let footer = app.staticTexts[lang.footer]
        reveal(footer)
        XCTAssertTrue(footer.exists, "handicap line: \(lang.footer)")
        XCTAssertTrue(app.staticTexts[lang.handicap].exists, "section header \(lang.handicap)")
        assertNoEnglish("New Game sheet")
        snapshot("t18_\(lang.code)_new_game_h2_black")

        // A Two Players game without handicap, ended with two passes.
        let twoPlayers = app.buttons[lang.twoPlayers]
        reveal(twoPlayers)
        twoPlayers.tap()
        setLocalizedHandicap(to: lang.noHandicap, noHandicap: lang.noHandicap)
        start.tap()
        XCTAssertTrue(waitUntil(30) { self.app.staticTexts[lang.move0].exists && self.app.staticTexts[lang.blackToPlay].exists },
                      "status line \(lang.move0) / \(lang.blackToPlay)")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", lang.myself)).count, 2, "player names")
        assertNoEnglish("main screen")
        snapshot("t18_\(lang.code)_main")
        let pass = actionButton(lang.pass)
        pass.tap()
        XCTAssertTrue(waitUntil(15) { self.app.staticTexts[lang.move1].exists && pass.isEnabled }, "first pass")
        pass.tap()

        let alert = app.alerts[lang.gameOver]
        XCTAssertTrue(alert.waitForExistence(timeout: 90), "Game Over dialog: \(lang.gameOver)")
        let message = alert.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", lang.resultPrefix)).firstMatch
        XCTAssertTrue(message.exists, "result line must start with '\(lang.resultPrefix)'")
        let resultLine = message.label
        XCTAssertNotNil(resultLine.range(of: #"(B|W)\+\d+\.5$"#, options: .regularExpression), "result: '\(resultLine)'")
        XCTAssertTrue(alert.buttons[lang.newGame].exists, "dialog button \(lang.newGame)")
        XCTAssertTrue(alert.buttons[lang.backToBoard].exists, "dialog button \(lang.backToBoard)")
        assertNoEnglish("Game Over dialog")
        snapshot("t18_\(lang.code)_game_over")
        alert.buttons[lang.backToBoard].tap()
        XCTAssertTrue(app.staticTexts[lang.gameOver].waitForExistence(timeout: 5), "\(lang.gameOver) on the board")
        XCTAssertTrue(app.staticTexts[resultLine].exists, "result on the board")
    }

    /// Sets the Handicap stepper by its (translated) label: down to no handicap with the left (-)
    /// button, then up to `target` with the right (+) button. (The buttons' labels are translated too.)
    func setLocalizedHandicap(to target: String, noHandicap zero: String) {
        let stepper = app.steppers.firstMatch
        reveal(stepper)
        let buttons = stepper.buttons.allElementsBoundByIndex.sorted { $0.frame.minX < $1.frame.minX }
        guard buttons.count == 2 else { return XCTFail("stepper buttons: \(buttons.count)") }
        var steps = 0
        while stepper.label != zero && steps < 10 { buttons[0].tap(); steps += 1 }
        steps = 0
        while stepper.label != target && steps < 10 { buttons[1].tap(); steps += 1 }
        XCTAssertEqual(stepper.label, target, "handicap row")
    }

    /// Fails if any element on screen is still labelled with one of the English texts. Reads the whole
    /// accessibility tree in one snapshot.
    func assertNoEnglish(_ screen: String, file: StaticString = #filePath, line: UInt = #line) {
        let tree = app.debugDescription
        let leftovers = Self.english.filter { tree.range(of: "label: '\($0)'", options: .caseInsensitive) != nil }
        XCTAssertTrue(leftovers.isEmpty, "\(screen): untranslated \(leftovers)", file: file, line: line)
    }
}
