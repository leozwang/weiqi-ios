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
    @State private var finalScore: String? = nil
    @State private var showGameOverDialog = false
    @State private var showSettings = false
    
    @State private var moveHistory: [(Int, Int, Stone)] = []
    @State private var redoStack: [(Int, Int, Stone)] = []
    @State private var consecutivePasses = 0
    
    @State private var pendingSettings = GameSettings()
    @State private var currentVisits: Int = 1000

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
                    Text(finalScore ?? "Weiqi").font(.system(size: 18, weight: .black)).foregroundColor(.white).tracking(1)
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
                            Text(gameMode == .userWhite ? "KataGo" : (gameMode == .aiBoth ? "KataGo" : "You"))
                                .font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                            Text("Captures: 0").font(.system(size: 14)).foregroundColor(.gray)
                        }
                    }
                    Spacer()
                    
                    ZStack {
                        Text("VS").font(.system(size: 16, weight: .black)).foregroundColor(.gray.opacity(0.5))
                            .opacity(isThinking ? 0 : 1)
                        
                        if isThinking {
                            Text("...")
                                .font(.system(size: 20, weight: .black))
                                .foregroundColor(accentColor)
                        }
                    }
                    .frame(width: 40)
                    
                    Spacer()
                    // Player 2 (White)
                    HStack(spacing: 12) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(gameMode == .userBlack ? "KataGo" : (gameMode == .aiBoth ? "KataGo" : "You"))
                                .font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                            Text("Captures: 0").font(.system(size: 14)).foregroundColor(.gray)
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
                } else {
                    VStack(spacing: 12) {
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
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Sequential loading: wait a bit before starting engine
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                initializeEngine()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: $pendingSettings, visits: $currentVisits) {
                startNewGame(settings: pendingSettings, visits: currentVisits)
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
        if engine.sendGtpCommand("play \(currentTurn == .black ? "black" : "white") \(toGtpCoord(x: x, y: y))")?.hasPrefix("=") == true {
            moveHistory.append((x, y, currentTurn)); redoStack.removeAll(); boardState[y][x] = currentTurn
            lastMove = (x, y); previewMove = nil; currentTurn = (currentTurn == .black ? .white : .black); consecutivePasses = 0
            if showAnalysis { triggerAnalysis() }
            checkAiTurn()
        }
    }

    private func handlePass() {
        guard let engine = bridge, !isThinking, finalScore == nil else { return }
        if engine.sendGtpCommand("play \(currentTurn == .black ? "black" : "white") pass")?.hasPrefix("=") == true {
            previewMove = nil; currentTurn = (currentTurn == .black ? .white : .black); consecutivePasses += 1
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
                        currentTurn = (currentTurn == .black ? .white : .black); consecutivePasses += 1
                        if consecutivePasses >= 2 { finishGame() }
                    } else if let pos = fromGtpCoord(moveStr) {
                        moveHistory.append((pos.0, pos.1, currentTurn)); redoStack.removeAll(); boardState[pos.1][pos.0] = currentTurn
                        lastMove = pos; currentTurn = (currentTurn == .black ? .white : .black); consecutivePasses = 0
                    }
                    if showAnalysis { triggerAnalysis() }
                    if gameMode == .aiBoth && finalScore == nil { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { checkAiTurn() } }
                }
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
        let configPath = Bundle.main.path(forResource: "gtp", ofType: "cfg") ?? ""
        let modelPath = Bundle.main.path(forResource: "model", ofType: "bin.gz") ?? ""
        DispatchQueue.global(qos: .userInitiated).async {
            if engine.initEngine(withConfig: configPath, model: modelPath) == 0 {
                DispatchQueue.main.async { self.bridge = engine; self.isEngineInitialized = true; checkAiTurn() }
            }
        }
    }

    private func startNewGame(settings: GameSettings, visits: Int) {
        guard let engine = bridge else { return }
        isThinking = true; showSettings = false
        DispatchQueue.global(qos: .userInitiated).async {
            engine.sendGtpCommand("clear_board"); engine.sendGtpCommand("set_max_visits \(visits)")
            engine.sendGtpCommand("komi \(settings.handicap > 0 ? 0.5 : 7.5)")
            if settings.handicap > 0 { engine.sendGtpCommand("fixed_handicap \(settings.handicap)") }
            let rawBoard = getFixedHandicapStones(count: settings.handicap)
            DispatchQueue.main.async {
                boardState = Array(repeating: Array(repeating: .empty, count: 19), count: 19)
                for pos in rawBoard { boardState[pos.1][pos.0] = .black }
                lastMove = nil; previewMove = nil; finalScore = nil; analysis = AnalysisResult(); consecutivePasses = 0
                moveHistory = rawBoard.map { ($0.0, $0.1, .black) }; redoStack.removeAll()
                gameMode = settings.mode; currentTurn = settings.handicap > 0 ? .white : .black
                isThinking = false; checkAiTurn()
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
        bridge?.sendGtpCommand("undo"); redoStack.append(last); boardState[last.1][last.0] = .empty
        lastMove = moveHistory.last.map { ($0.0, $0.1) }; currentTurn = last.2; consecutivePasses = 0
        if showAnalysis { triggerAnalysis() }
    }
    
    private func redoMove() {
        guard !isThinking, let next = redoStack.popLast() else { return }
        if bridge?.sendGtpCommand("play \(next.2 == .black ? "black" : "white") \(toGtpCoord(x: next.0, y: next.1))")?.hasPrefix("=") == true {
            moveHistory.append(next); boardState[next.1][next.0] = next.2; lastMove = (next.0, next.1); currentTurn = (next.2 == .black ? .white : .black); consecutivePasses = 0
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
    
    private let levels: [(String, Int)] = [("Easy", 100), ("Amateur", 500), ("Advanced", 1000), ("Pro", 2500)]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Play As")) {
                    Picker("Mode", selection: $settings.mode) {
                        ForEach(GameMode.allCases, id: \.self) { (mode: GameMode) in
                            Text(mode.rawValue).tag(mode)
                        }
                    }.pickerStyle(.inline)
                }
                
                Section(header: Text("Handicap")) {
                    Stepper("\(settings.handicap) Stones", value: $settings.handicap, in: 0...9)
                }
                
                Section(header: Text("AI Strength")) {
                    Picker("Strength", selection: $visits) {
                        ForEach(levels, id: \.1) { (level: (String, Int)) in
                            Text(level.0).tag(level.1)
                        }
                    }.pickerStyle(.segmented)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(visits) visits per move")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
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
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
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
                Text(title).font(.system(size: 14, weight: .bold))
            }
            .foregroundColor(isEnabled ? .white : .white.opacity(0.3))
            .frame(width: 72, height: 72).background(Color.white.opacity(0.05)).cornerRadius(20)
        }
    }
}
