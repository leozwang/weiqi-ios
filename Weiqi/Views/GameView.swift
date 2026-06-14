import SwiftUI

struct GameView: View {
    @State private var gameMode: GameMode = .userBlack
    @State private var bridge: KataGoWrapper?
    @State private var status: String = "Ready"
    @State private var boardState: [[Stone]] = Array(repeating: Array(repeating: .empty, count: 19), count: 19)
    @State private var lastMove: (Int, Int)?
    @State private var previewMove: (Int, Int)?
    @State private var currentTurn: Stone = .black
    @State private var analysis = AnalysisResult()
    @State private var isThinking = false
    @State private var showAnalysis = false
    @State private var isEngineInitialized = false
    @State private var initError: String? = nil
    @State private var finalScore: String? = nil
    @State private var showGameOverDialog = false
    @State private var showSettings = false
    
    @State private var moveHistory: [PersistedMove] = []
    @State private var redoStack: [PersistedMove] = []
    @State private var consecutivePasses = 0
    
    @State private var pendingSettings = GameSettings()
    @State private var currentVisits: Int = 500
    @State private var showPassAlert = false
    @State private var passAlertMessage = ""

    private let backgroundColor = Color(red: 24/255, green: 24/255, blue: 28/255)
    private let accentColor = Color(red: 100/255, green: 200/255, blue: 255/255)

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top Navigation Bar
                HStack {
                    Button(action: {}) { Image(systemName: "line.3.horizontal").font(.system(size: 24)).foregroundColor(.white) }
                    Spacer()
                    Text(finalScore ?? "围棋 碁 GO!").font(.system(size: 18, weight: .black)).foregroundColor(.white).tracking(1)
                    Spacer()
                    Button(action: { showAnalysis.toggle(); if showAnalysis { triggerAnalysis() } }) {
                        Image(systemName: showAnalysis ? "eye.fill" : "eye.slash").font(.system(size: 22)).foregroundColor(showAnalysis ? accentColor : .white)
                    }
                }
                .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 20)
                
                // Player Profiles
                HStack {
                    // Player 1 (Black)
                    HStack(spacing: 12) {
                        Circle().fill(Color.black).frame(width: 40, height: 40).shadow(color: .black.opacity(0.5), radius: 2)
                            .overlay(Circle().stroke(currentTurn == .black ? accentColor : Color.clear, lineWidth: 2))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey(gameMode == .userWhite ? "KataGo" : (gameMode == .aiBoth ? "KataGo" : "You")))
                                .font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                            Text(LocalizedStringKey("Captures: 0")).font(.system(size: 14)).foregroundColor(.gray)
                        }
                    }
                    Spacer()
                    
                    ZStack {
                        Text("VS").font(.system(size: 16, weight: .black)).foregroundColor(.gray.opacity(0.5))
                            .opacity(isThinking ? 0 : 1)
                        
                        if isThinking {
                            RotatingRingView(color: accentColor)
                        }
                    }
                    .frame(width: 40)
                    
                    Spacer()
                    // Player 2 (White)
                    HStack(spacing: 12) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(LocalizedStringKey(gameMode == .userBlack ? "KataGo" : (gameMode == .aiBoth ? "KataGo" : "You")))
                                .font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                            Text(LocalizedStringKey("Captures: 0")).font(.system(size: 14)).foregroundColor(.gray)
                        }
                        Circle().fill(Color.white).frame(width: 40, height: 40).shadow(color: .black.opacity(0.3), radius: 2)
                            .overlay(Circle().stroke(currentTurn == .white ? accentColor : Color.clear, lineWidth: 2))
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 12)
                
                // AI Status Row
                if showAnalysis && finalScore == nil {
                    HStack(spacing: 20) {
                        HStack(spacing: 8) {
                            Text("Black Winrate").font(.system(size: 12, weight: .bold)).foregroundColor(.gray)
                            Text("\(Int(analysis.winrate * 100))%").font(.system(size: 16, weight: .heavy)).foregroundColor(accentColor)
                        }
                        Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 1, height: 20)
                        HStack(spacing: 8) {
                            Text("Score Lead").font(.system(size: 12, weight: .bold)).foregroundColor(.gray)
                            Text("\(analysis.scoreLead >= 0 ? "B" : "W")+\(String(format: "%.1f", abs(analysis.scoreLead)))").font(.system(size: 16, weight: .heavy)).foregroundColor(accentColor)
                        }
                    }
                    .padding(.vertical, 8).padding(.horizontal, 16).background(Color.white.opacity(0.08)).cornerRadius(12).padding(.bottom, 8)
                }

                Spacer().frame(height: 12)

                // Only render the board once the engine is ready
                if isEngineInitialized {
                    BoardView(
                        boardState: boardState, previewMove: previewMove, lastMove: lastMove,
                        analysis: analysis, showAnalysis: showAnalysis, isGameOver: finalScore != nil,
                        currentTurnColor: currentTurn, onMoveTapped: handleTap
                    )
                    .padding(.horizontal, 4)
                } else if let error = initError {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 44))
                            .foregroundColor(.red)
                        Text("Engine Failed to Initialize")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button(action: {
                            self.initError = nil
                            initializeEngine()
                        }) {
                            Text("Retry")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(backgroundColor)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(accentColor)
                                .cornerRadius(8)
                        }
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .padding(20)
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: accentColor))
                            .scaleEffect(1.2)
                            .padding(.bottom, 4)
                        Text("Initializing Engine...")
                            .foregroundColor(.gray)
                            .font(.system(size: 14, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .padding(20)
                }

                Spacer(minLength: 12)

                // Navigation Row: Undo - PASS (Skip) - Redo
                HStack(spacing: 0) {
                    ActionButton(icon: "arrow.uturn.backward", title: "Undo", action: undoMove).disabled(moveHistory.isEmpty || isThinking)
                    Spacer()
                    ActionButton(icon: "slash.circle", title: "Pass", action: handlePass).disabled(gameMode == .aiBoth || isThinking || finalScore != nil)
                    Spacer()
                    ActionButton(icon: "arrow.uturn.forward", title: "Redo", action: redoMove).disabled(redoStack.isEmpty || isThinking)
                }
                .padding(.horizontal, 40)

                Spacer(minLength: 12)

                // Primary Action Bar (PLACE & NEW GAME)
                HStack(spacing: 16) {
                    Button(action: { showSettings = true }) {
                        HStack { Image(systemName: "plus.circle.fill"); Text("NEW GAME") }.font(.system(size: 14, weight: .bold)).foregroundColor(.white).frame(width: 130, height: 64)
                            .background(RoundedRectangle(cornerRadius: 32).fill(Color.orange)).shadow(color: Color.orange.opacity(0.3), radius: 6, y: 3)
                    }
                    .disabled(isThinking)

                    Button(action: { if let move = previewMove { executeMove(x: move.0, y: move.1) } }) {
                        Text("PLACE").font(.system(size: 20, weight: .black)).tracking(2).foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 64)
                            .background(RoundedRectangle(cornerRadius: 32).fill(previewMove != nil ? Color(red: 30/255, green: 130/255, blue: 240/255) : Color.gray.opacity(0.3)))
                            .shadow(color: previewMove != nil ? Color(red: 30/255, green: 130/255, blue: 240/255).opacity(0.4) : .clear, radius: 8, y: 4)
                    }
                    .disabled(previewMove == nil || isThinking || finalScore != nil)
                }
                .padding(.horizontal, 20).padding(.bottom, 30)
            }
            
            if showPassAlert {
                VStack {
                    Spacer().frame(height: 120)
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 18, weight: .bold))
                        Text(passAlertMessage)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color(red: 30/255, green: 30/255, blue: 35/255)))
                    .overlay(Capsule().stroke(Color.orange, lineWidth: 1.5))
                    .shadow(color: Color.black.opacity(0.4), radius: 6, y: 3)
                    
                    Spacer()
                }
                .ignoresSafeArea()
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            let saved = GameSettings.load()
            pendingSettings = saved
            currentVisits = saved.visits
            // Sequential loading: wait a bit before starting engine
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                initializeEngine()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: $pendingSettings, visits: $currentVisits) {
                pendingSettings.visits = currentVisits
                pendingSettings.save()
                startNewGame(settings: pendingSettings, visits: currentVisits)
            }
            .onAppear {
                let saved = GameSettings.load()
                pendingSettings = saved
                currentVisits = saved.visits
            }
        }
        .alert("Game Over", isPresented: $showGameOverDialog) {
            Button("NEW GAME") { showSettings = true }
            Button("BACK TO BOARD", role: .cancel) { }
        } message: { Text("Result: \(finalScore ?? "Unknown")") }
    }

    private func handleTap(x: Int, y: Int) {
        guard isEngineInitialized, !isThinking, finalScore == nil else { return }
        let isUserTurn = gameMode == .userBoth || (gameMode == .userBlack && currentTurn == .black) || (gameMode == .userWhite && currentTurn == .white)
        guard isUserTurn, boardState[y][x] == .empty else { return }
        previewMove = (x, y)
    }

    private func executeMove(x: Int, y: Int) {
        guard let engine = bridge else { return }
        let turnVal = currentTurn.rawValue
        if engine.sendGtpCommand("play \(currentTurn == .black ? "black" : "white") \(toGtpCoord(x: x, y: y))")?.hasPrefix("=") == true {
            let move = PersistedMove(x: x, y: y, isPass: false, stone: turnVal)
            moveHistory.append(move)
            redoStack.removeAll()
            boardState[y][x] = currentTurn
            lastMove = (x, y)
            previewMove = nil
            currentTurn = (currentTurn == .black ? .white : .black)
            consecutivePasses = 0
            
            PersistedMove.saveAll(moveHistory)
            
            if showAnalysis { triggerAnalysis() }
            checkAiTurn()
        }
    }

    private func handlePass() {
        guard let engine = bridge, !isThinking, finalScore == nil else { return }
        let turnVal = currentTurn.rawValue
        if engine.sendGtpCommand("play \(currentTurn == .black ? "black" : "white") pass")?.hasPrefix("=") == true {
            let move = PersistedMove(x: -1, y: -1, isPass: true, stone: turnVal)
            moveHistory.append(move)
            previewMove = nil
            currentTurn = (currentTurn == .black ? .white : .black)
            consecutivePasses += 1
            
            PersistedMove.saveAll(moveHistory)
            
            if consecutivePasses >= 2 { finishGame() } else { if showAnalysis { triggerAnalysis() }; checkAiTurn() }
        }
    }

    private func checkAiTurn() {
        guard isEngineInitialized, !isThinking, finalScore == nil else { return }
        if (gameMode == .aiBoth) || (gameMode == .userBlack && currentTurn == .white) || (gameMode == .userWhite && currentTurn == .black) { triggerAiMove() }
    }

    private func triggerAiMove() {
        guard let engine = bridge else { return }
        isThinking = true
        DispatchQueue.global(qos: .userInitiated).async {
            let res = engine.sendGtpCommand("genmove \(currentTurn == .black ? "black" : "white")")
            DispatchQueue.main.async {
                isThinking = false
                if let response = res, response.hasPrefix("=") {
                    let moveStr = response.replacingOccurrences(of: "= ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if moveStr.uppercased() == "PASS" {
                        let aiColor = currentTurn == .black ? NSLocalizedString("Black", comment: "") : NSLocalizedString("White", comment: "")
                        let format = NSLocalizedString("AI (%@) Passed", comment: "")
                        showPassReminder(message: String(format: format, aiColor))
                        
                        let turnVal = currentTurn.rawValue
                        let move = PersistedMove(x: -1, y: -1, isPass: true, stone: turnVal)
                        moveHistory.append(move)
                        
                        currentTurn = (currentTurn == .black ? .white : .black); consecutivePasses += 1
                        
                        PersistedMove.saveAll(moveHistory)
                        
                        if consecutivePasses >= 2 { finishGame() }
                    } else if let pos = fromGtpCoord(moveStr) {
                        let turnVal = currentTurn.rawValue
                        let move = PersistedMove(x: pos.0, y: pos.1, isPass: false, stone: turnVal)
                        moveHistory.append(move)
                        redoStack.removeAll()
                        boardState[pos.1][pos.0] = currentTurn
                        lastMove = pos; currentTurn = (currentTurn == .black ? .white : .black); consecutivePasses = 0
                        
                        PersistedMove.saveAll(moveHistory)
                    }
                    if showAnalysis { triggerAnalysis() }
                    if gameMode == .aiBoth && finalScore == nil { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { checkAiTurn() } }
                }
            }
        }
    }

    private func showPassReminder(message: String) {
        passAlertMessage = message
        withAnimation(.spring()) {
            showPassAlert = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                showPassAlert = false
            }
        }
    }

    private func triggerAnalysis() {
        guard let engine = bridge, isEngineInitialized, !isThinking else { return }
        isThinking = true
        DispatchQueue.global(qos: .userInitiated).async {
            let analysisVisits = max(100, Int(Double(currentVisits) * 0.4))
            engine.sendGtpCommand("think black \(analysisVisits)")
            let res = engine.sendGtpCommand("kata-get-analysis black")
            DispatchQueue.main.async {
                isThinking = false
                if let response = res, response.hasPrefix("=") {
                    let jsonStr = response.replacingOccurrences(of: "=", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if let data = jsonStr.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let rootInfo = json["rootInfo"] as? [String: Any] {
                        analysis.winrate = rootInfo["winrate"] as? Double ?? 0.5
                        analysis.scoreLead = rootInfo["scoreLead"] as? Double ?? 0.0
                    }
                }
            }
        }
    }

    private func finishGame() {
        isThinking = true
        DispatchQueue.global(qos: .userInitiated).async {
            let res = bridge?.sendGtpCommand("final_score")
            DispatchQueue.main.async {
                isThinking = false
                finalScore = res?.replacingOccurrences(of: "= ", with: "") ?? "Game Ended"
                showGameOverDialog = true
            }
        }
    }

    private func initializeEngine() {
        let engine = KataGoWrapper()
        guard let configPath = Bundle.main.path(forResource: "gtp", ofType: "cfg"), !configPath.isEmpty else {
            self.initError = "Missing gtp.cfg configuration file"
            return
        }
        guard let modelPath = Bundle.main.path(forResource: "model", ofType: "bin.gz"), !modelPath.isEmpty else {
            self.initError = "Missing neural network model.bin.gz file"
            return
        }

        // Resolve a safe, writable directory for logs and configurations (e.g., Caches Directory)
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let storagePath = paths.first?.path ?? NSTemporaryDirectory()

        DispatchQueue.global(qos: .userInitiated).async {
            let status = engine.initEngine(withConfig: configPath, model: modelPath, storage: storagePath)
            if status == 0 {
                DispatchQueue.main.async {
                    self.bridge = engine
                    self.isEngineInitialized = true
                    self.initError = nil
                    let savedSettings = GameSettings.load()
                    let savedMoves = PersistedMove.loadAll()
                    restoreGame(settings: savedSettings, moves: savedMoves)
                }
            } else {
                DispatchQueue.main.async {
                    self.initError = "KataGo failed to initialize (Error Code: \(status))"
                }
            }
        }
    }

    private func startNewGame(settings: GameSettings, visits: Int) {
        showSettings = false
        let rawBoard = getFixedHandicapStones(count: settings.handicap)
        let initialMoves = rawBoard.map { PersistedMove(x: $0.0, y: $0.1, isPass: false, stone: 1) }
        PersistedMove.saveAll(initialMoves)
        restoreGame(settings: settings, moves: initialMoves)
    }

    private func restoreGame(settings: GameSettings, moves: [PersistedMove]) {
        guard let engine = bridge else { return }
        isThinking = true
        DispatchQueue.global(qos: .userInitiated).async {
            engine.sendGtpCommand("clear_board")
            engine.sendGtpCommand("set_max_visits \(settings.visits)")
            engine.sendGtpCommand("komi \(settings.handicap > 0 ? 0.5 : 7.5)")
            if settings.handicap > 0 {
                engine.sendGtpCommand("fixed_handicap \(settings.handicap)")
            }
            
            let handicapCount = settings.handicap
            var board = Array(repeating: Array(repeating: Stone.empty, count: 19), count: 19)
            var history: [PersistedMove] = []
            var last: (Int, Int)? = nil
            var passes = 0
            
            for (index, move) in moves.enumerated() {
                let stone = Stone(rawValue: move.stone) ?? .empty
                if index < handicapCount {
                    board[move.y][move.x] = stone
                    history.append(move)
                } else {
                    let cmd = move.isPass ? "play \(move.stone == 1 ? "black" : "white") pass" : "play \(move.stone == 1 ? "black" : "white") \(toGtpCoord(x: move.x, y: move.y))"
                    _ = engine.sendGtpCommand(cmd)
                    
                    history.append(move)
                    if !move.isPass {
                        board[move.y][move.x] = stone
                        last = (move.x, move.y)
                        passes = 0
                    } else {
                        passes += 1
                    }
                }
            }
            
            let nextTurn: Stone
            if moves.isEmpty {
                nextTurn = settings.handicap > 0 ? .white : .black
            } else {
                nextTurn = (moves.last?.stone == 1) ? .white : .black
            }
            
            DispatchQueue.main.async {
                boardState = board
                lastMove = last
                previewMove = nil
                finalScore = nil
                analysis = AnalysisResult()
                consecutivePasses = passes
                moveHistory = history
                redoStack = []
                gameMode = settings.mode
                currentTurn = nextTurn
                isThinking = false
                checkAiTurn()
            }
        }
    }
    
    private func getFixedHandicapStones(count: Int) -> [(Int, Int)] {
        let pts = [(3,3), (15,15), (15,3), (3,15), (9,9), (3,9), (15,9), (9,3), (9,15)]
        if count <= 0 { return [] }; if count == 1 { return [(15,3)] }
        if count == 2 { return [(15,3), (3,15)] }; if count == 3 { return [(15,3), (3,15), (15,15)] }
        if count == 4 { return [(15,3), (3,15), (15,15), (3,3)] }; if count == 5 { return [(15,3), (3,15), (15,15), (3,3), (9,9)] }
        if count == 6 { return [(15,3), (3,15), (15,15), (3,3), (15,9), (3,9)] }; if count == 7 { return [(15,3), (3,15), (15,15), (3,3), (15,9), (3,9), (9,9)] }
        if count == 8 { return [(15,3), (3,15), (15,15), (3,3), (15,9), (3,9), (9,3), (9,15)] }
        return Array(pts.prefix(9))
    }

    private func undoMove() {
        guard !isThinking, let last = moveHistory.popLast() else { return }
        bridge?.sendGtpCommand("undo")
        redoStack.append(last)
        if !last.isPass {
            boardState[last.y][last.x] = .empty
        }
        lastMove = moveHistory.last(where: { !$0.isPass }).map { ($0.x, $0.y) }
        currentTurn = Stone(rawValue: last.stone) ?? .black
        
        var passes = 0
        for m in moveHistory.reversed() {
            if m.isPass {
                passes += 1
            } else {
                break
            }
        }
        consecutivePasses = passes
        PersistedMove.saveAll(moveHistory)
        
        if showAnalysis { triggerAnalysis() }
    }
    
    private func redoMove() {
        guard !isThinking, let next = redoStack.popLast() else { return }
        let cmd = next.isPass ? "play \(next.stone == 1 ? "black" : "white") pass" : "play \(next.stone == 1 ? "black" : "white") \(toGtpCoord(x: next.x, y: next.y))"
        if bridge?.sendGtpCommand(cmd)?.hasPrefix("=") == true {
            moveHistory.append(next)
            if !next.isPass {
                boardState[next.y][next.x] = Stone(rawValue: next.stone) ?? .empty
                lastMove = (next.x, next.y)
                consecutivePasses = 0
            } else {
                lastMove = moveHistory.last(where: { !$0.isPass }).map { ($0.x, $0.y) }
                consecutivePasses += 1
            }
            currentTurn = (next.stone == 1 ? .white : .black)
            PersistedMove.saveAll(moveHistory)
            
            if showAnalysis { triggerAnalysis() }
        }
    }

    private func toGtpCoord(x: Int, y: Int) -> String {
        let letters = "ABCDEFGHJKLMNOPQRST"
        return "\(Array(letters)[x])\(19 - y)"
    }

    private func fromGtpCoord(_ coord: String) -> (Int, Int)? {
        let coord = coord.uppercased(); guard coord.count >= 2 else { return nil }
        let letters = "ABCDEFGHJKLMNOPQRST"
        guard let col = letters.firstIndex(of: coord.first!) else { return nil }
        guard let rowNum = Int(coord.dropFirst()) else { return nil }
        return (letters.distance(from: letters.startIndex, to: col), 19 - rowNum)
    }
}

// --- Subviews ---

struct SettingsView: View {
    @Binding var settings: GameSettings
    @Binding var visits: Int
    var onStart: () -> Void
    @Environment(\.presentationMode) var presentationMode
    
    @ObservedObject private var storeManager = StoreManager.shared
    
    private let levels: [(String, Int)] = [("Easy", 100), ("Amateur", 500), ("Advanced", 1000), ("Pro", 2500)]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Form {
                    Section(header: Text("AI Strength")) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                ForEach(levels, id: \.1) { level in
                                    let isLocked = (level.0 == "Advanced" || level.0 == "Pro") && !storeManager.isPurchased
                                    Button(action: {
                                        visits = level.1
                                    }) {
                                        VStack(spacing: 4) {
                                            HStack(spacing: 4) {
                                                Text(LocalizedStringKey(level.0))
                                                    .font(.system(size: 14, weight: .bold))
                                                if isLocked {
                                                    Image(systemName: "lock.fill")
                                                        .font(.system(size: 10))
                                                        .foregroundColor(.orange)
                                                }
                                            }
                                            Text("\(level.1) visits")
                                                .font(.system(size: 10))
                                                .foregroundColor(visits == level.1 ? .white.opacity(0.8) : .gray)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(visits == level.1 ? Color.blue : Color.white.opacity(0.08))
                                        )
                                        .foregroundColor(visits == level.1 ? .white : .primary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            if !storeManager.isPurchased {
                                HStack(spacing: 8) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.orange)
                                    Text("One-time purchase unlocks Advanced and Pro levels forever.")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(.orange)
                                        .multilineTextAlignment(.leading)
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.12))
                                .cornerRadius(8)
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    }
                    
                    Section(header: Text("Play As")) {
                        Picker("Mode", selection: $settings.mode) {
                            ForEach(GameMode.allCases, id: \.self) { (mode: GameMode) in
                                Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                            }
                        }.pickerStyle(.inline)
                    }
                    
                    Section(header: Text("Handicap")) {
                        Stepper("\(settings.handicap) Stones", value: $settings.handicap, in: 0...9)
                    }
                }
                
                // Bottom panel containing Paywall / Start button
                VStack {
                    Divider()
                        .padding(.bottom, 8)
                    
                    let isCurrentLevelLocked = (visits >= 1000) && !storeManager.isPurchased
                    if isCurrentLevelLocked {
                        VStack(spacing: 12) {
                            Text("Unlock Elite Levels")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.orange)
                            Text("Advanced and Pro levels require high computational budget and utilize deep search. Unlock permanently to play at master level.")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                            
                            if let product = storeManager.product {
                                Button(action: {
                                    Task {
                                        await storeManager.purchase()
                                    }
                                }) {
                                    if storeManager.isPurchasing {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Text("Unlock for \(product.displayPrice)")
                                            .font(.system(size: 15, weight: .bold))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(24)
                                .disabled(storeManager.isPurchasing)
                            } else {
                                Button(action: {
                                    Task {
                                        await storeManager.loadProducts()
                                    }
                                }) {
                                    Text("Load Store Info")
                                        .font(.system(size: 15, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(24)
                            }
                            
                            Button(action: {
                                Task {
                                    await storeManager.restorePurchases()
                                }
                            }) {
                                Text("Restore Purchases")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.blue)
                            }
                            .disabled(storeManager.isPurchasing)
                            
                            if let error = storeManager.errorMessage {
                                Text(error)
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    } else {
                        Button(action: onStart) {
                            Text("START GAME")
                                .font(.system(size: 16, weight: .black))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.blue)
                                .cornerRadius(25)
                        }
                    }
                }
                .padding([.horizontal, .bottom])
                .background(Color(UIColor.systemGroupedBackground))
            }
            .navigationTitle("New Game")
            .navigationBarItems(trailing: Button("Cancel") { presentationMode.wrappedValue.dismiss() })
        }
    }
}

struct ActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 24))
                Text(LocalizedStringKey(title)).font(.system(size: 14, weight: .bold))
            }
            .foregroundColor(isEnabled ? .white : .white.opacity(0.3))
            .frame(width: 72, height: 72).background(Color.white.opacity(0.05)).cornerRadius(20)
        }
    }
}

struct RotatingRingView: View {
    var color: Color = Color(red: 100/255, green: 200/255, blue: 255/255)
    @State private var isRotating = 0.0
    
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [color, color.opacity(0.2)]),
                    center: .center
                ),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
            )
            .frame(width: 20, height: 20)
            .rotationEffect(Angle(degrees: isRotating))
            .onAppear {
                withAnimation(Animation.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    isRotating = 360.0
                }
            }
    }
}
