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
    @State private var isAnalyzing = false
    @State private var showAnalysis = false
    @State private var isEngineInitialized = false
    @State private var initError: String? = nil
    @State private var finalScore: String? = nil
    /// True while the final score is being computed (can take several seconds).
    @State private var isScoring = false
    @State private var showGameOverDialog = false
    @State private var showSettings = false
    @State private var showNewGame = false
    @State private var showSplashScreen = true
    @State private var minSplashTimePassed = false
    
    @State private var moveHistory: [PersistedMove] = []
    @State private var redoStack: [PersistedMove] = []
    @State private var consecutivePasses = 0
    
    @State private var pendingSettings = GameSettings()
    @State private var currentVisits: Int = 500
    /// Strength picked in the New Game sheet; only becomes `currentVisits` when a game is started.
    @State private var pendingVisits: Int = 500
    /// Bumped whenever a game is (re)started; results of engine work for an older game are dropped.
    @State private var gameGeneration = 0
    @State private var showPassAlert = false
    @State private var passAlertMessage = ""
    @State private var blackCaptures: Int = 0
    @State private var whiteCaptures: Int = 0
    @State private var showAnalysisLegend = false
    /// Handicap of the current game (for the Debug-only engine status read by UI tests).
    @State private var currentHandicap = 0
    /// Moves replayed into the engine when the current game was loaded (for the engine status).
    @State private var restoredMoves = 0
    /// Debug builds only: "visits=… komi=… handicap=… restored=… mem=… refused=…", read by UI tests
    /// (like Android's logcat checks).
    @State private var engineStatus = ""

    /// All engine work runs on one serial queue, so multi-command sequences (new game, undo, redo)
    /// never interleave with an in-flight AI move or analysis.
    private static let engineQueue = DispatchQueue(label: "com.cwave.weiqi.engine", qos: .userInitiated)

    private let backgroundColor = Color(red: 24/255, green: 24/255, blue: 28/255)
    private let accentColor = Color(red: 100/255, green: 200/255, blue: 255/255)

    var body: some View {
        ZStack(alignment: .top) {
            backgroundColor.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top Navigation Bar
                HStack {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Text("Settings"))
                    Spacer()
                    Text(finalScore ?? "围棋 碁 GO!")
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(.white)
                        .tracking(1)
                    Spacer()
                    Button(action: {
                        showAnalysis.toggle()
                        if showAnalysis {
                            triggerAnalysis()
                        } else {
                            analysis.candidates = []
                        }
                    }) {
                        Image(systemName: showAnalysis ? "eye.fill" : "eye.slash")
                            .font(.system(size: 22))
                            .foregroundColor(showAnalysis ? accentColor : .white)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Text("Analysis"))
                    .accessibilityValue(Text(showAnalysis ? "On" : "Off"))
                    .accessibilityIdentifier("analysisToggle")
                }
                .frame(height: 44)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 12)
                
                // Player Profiles
                HStack(alignment: .center) {
                    // Player 1 (Black)
                    let isBlackThinking = isThinking && currentTurn == .black
                    HStack(spacing: 12) {
                        ZStack {
                            RotatingRingView(color: accentColor, lineWidth: 2.5)
                                .frame(width: 50, height: 50)
                                .opacity(isBlackThinking ? 1.0 : 0.0)
                            Circle().fill(Color.black).frame(width: 40, height: 40).shadow(color: .black.opacity(0.5), radius: 2)
                                .overlay(Circle().stroke(currentTurn == .black ? accentColor : Color.clear, lineWidth: 2))
                        }
                        .frame(width: 52, height: 52)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey(gameMode == .userWhite ? "KataGo" : (gameMode == .aiBoth ? "KataGo" : "Myself")))
                                .font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                            Text("Captures: \(blackCaptures)").font(.system(size: 14)).foregroundColor(.gray)
                        }
                    }
                    Spacer()
                    
                    Text("VS").font(.system(size: 16, weight: .black)).foregroundColor(.gray.opacity(0.5))
                        .frame(width: 36)
                    
                    Spacer()
                    // Player 2 (White)
                    let isWhiteThinking = isThinking && currentTurn == .white
                    HStack(spacing: 12) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(LocalizedStringKey(gameMode == .userBlack ? "KataGo" : (gameMode == .aiBoth ? "KataGo" : "Myself")))
                                .font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                            Text("Captures: \(whiteCaptures)").font(.system(size: 14)).foregroundColor(.gray)
                        }
                        ZStack {
                            RotatingRingView(color: accentColor, lineWidth: 2.5)
                                .frame(width: 50, height: 50)
                                .opacity(isWhiteThinking ? 1.0 : 0.0)
                            Circle().fill(Color.white).frame(width: 40, height: 40).shadow(color: .black.opacity(0.3), radius: 2)
                                .overlay(Circle().stroke(currentTurn == .white ? accentColor : Color.clear, lineWidth: 2))
                        }
                        .frame(width: 52, height: 52)
                    }
                }
                .frame(height: 52)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                
                // MARK: Fixed-Height Status & Analysis Container (Eliminates Board Shifting)
                VStack(spacing: 4) {
                    if isScoring {
                        HStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: accentColor))
                                .scaleEffect(0.8)
                            Text(LocalizedStringKey("Counting score…"))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .frame(height: 74)
                    } else if showAnalysis && finalScore == nil {
                        // AI Winrate & Score Lead Row
                        HStack(spacing: 12) {
                            HStack(spacing: 6) {
                                Text(LocalizedStringKey("Black Winrate")).font(.system(size: 11, weight: .bold)).foregroundColor(.gray)
                                Text("\(Int(analysis.winrate * 100))%").font(.system(size: 15, weight: .heavy)).foregroundColor(accentColor)
                            }
                            Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 1, height: 16)
                            HStack(spacing: 6) {
                                Text(LocalizedStringKey("Score Lead")).font(.system(size: 11, weight: .bold)).foregroundColor(.gray)
                                Text("\(analysis.scoreLead >= 0 ? "B" : "W")+\(String(format: "%.1f", abs(analysis.scoreLead)))").font(.system(size: 15, weight: .heavy)).foregroundColor(accentColor)
                            }
                            
                            Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 1, height: 16)
                            
                            Button(action: { showAnalysisLegend = true }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "info.circle.fill")
                                        .font(.system(size: 11))
                                    Text("Guide")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .foregroundColor(Color.white.opacity(0.85))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.12))
                                .cornerRadius(6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            .alert("Recommended Moves Guide", isPresented: $showAnalysisLegend) {
                                Button("Got it", role: .cancel) { }
                            } message: {
                                Text("KataGo evaluates and ranks moves by AI win rate:\n\n• 🔵 #1 (Blue): BEST — Top AI recommendation\n• 🟢 #2 (Green): 2nd — Strong alternative\n• 🟠 #3 (Amber): 3rd — Good alternative\n• 🟣 #4 & #5 (Purple): 4th/5th — Other viable options\n\nTap any badge on the board or pill above to preview and place that move.")
                            }
                        }
                        .frame(height: 34)
                        .padding(.horizontal, 14)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(10)
                        
                        // Recommended Candidate Moves Strip (Always 32pt height)
                        if !analysis.candidates.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(analysis.candidates) { cand in
                                        let isSelected = previewMove?.0 == cand.x && previewMove?.1 == cand.y
                                        let rankLabel: String = {
                                            switch cand.order {
                                            case 1: return "BEST"
                                            case 2: return "2nd"
                                            case 3: return "3rd"
                                            case 4: return "4th"
                                            case 5: return "5th"
                                            default: return "#\(cand.order)"
                                            }
                                        }()
                                        
                                        Button(action: {
                                            handleTap(x: cand.x, y: cand.y)
                                        }) {
                                            HStack(spacing: 5) {
                                                HStack(spacing: 3) {
                                                    ZStack {
                                                        Circle()
                                                            .fill(candidateBadgeColor(for: cand.order))
                                                            .frame(width: 18, height: 18)
                                                        Text("\(cand.order)")
                                                            .font(.system(size: 10, weight: .black, design: .rounded))
                                                            .foregroundColor(.white)
                                                    }
                                                    Text(LocalizedStringKey(rankLabel))
                                                        .font(.system(size: 10, weight: .heavy))
                                                        .foregroundColor(candidateBadgeColor(for: cand.order))
                                                }
                                                
                                                Rectangle()
                                                    .fill(Color.white.opacity(0.2))
                                                    .frame(width: 1, height: 12)
                                                
                                                Text(cand.gtpCoord)
                                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                    .foregroundColor(.white)
                                                
                                                Text("\(Int((cand.winrate * 100).rounded()))%")
                                                    .font(.system(size: 11, weight: .heavy))
                                                    .foregroundColor(accentColor)
                                                
                                                Text(String(format: "%@%+.1f", cand.scoreLead >= 0 ? "B" : "W", abs(cand.scoreLead)))
                                                    .font(.system(size: 10, weight: .medium))
                                                    .foregroundColor(.gray)
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.06))
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(isSelected ? Color.yellow : Color.white.opacity(0.12), lineWidth: isSelected ? 1.5 : 0.8)
                                            )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                            .frame(height: 32)
                        } else {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: accentColor))
                                    .scaleEffect(0.65)
                                Text("KataGo evaluating moves...")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.gray)
                            }
                            .frame(height: 32)
                        }
                    } else if let score = finalScore {
                        VStack(spacing: 4) {
                            Text("Game Over")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                            Text("Result: \(score)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(accentColor)
                        }
                        .frame(height: 74)
                    } else {
                        // Analysis Off: Static game status
                        VStack(spacing: 4) {
                            HStack(spacing: 12) {
                                Text("Move \(moveHistory.count)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                Circle().fill(Color.gray.opacity(0.4)).frame(width: 4, height: 4)
                                Text(LocalizedStringKey(currentTurn == .black ? "Black to play" : "White to play"))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.gray)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(10)
                            
                            Text("Tap 👁 to view KataGo AI recommendations")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(.gray.opacity(0.5))
                        }
                        .frame(height: 74)
                    }
                }
                .frame(height: 74)
                .padding(.bottom, 6)

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
                        Text(LocalizedStringKey("Initializing Engine..."))
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
                    ActionButton(icon: "arrow.uturn.backward", title: "Undo", action: undoMove).disabled(movesToUndo == 0 || isThinking)
                    Spacer()
                    ActionButton(icon: "slash.circle", title: "Pass", action: handlePass).disabled(!isUserTurn || isThinking || finalScore != nil)
                    Spacer()
                    ActionButton(icon: "arrow.uturn.forward", title: "Redo", action: redoMove).disabled(redoStack.isEmpty || isThinking || gameMode == .aiBoth)
                }
                .padding(.horizontal, 40)

                Spacer(minLength: 12)

                // Primary Action Bar (PLACE & NEW GAME)
                HStack(spacing: 16) {
                    Button(action: { showNewGame = true }) {
                        HStack { Image(systemName: "plus.circle.fill"); Text("NEW GAME") }.font(.system(size: 14, weight: .bold)).foregroundColor(.white).frame(width: 130, height: 64)
                            .background(RoundedRectangle(cornerRadius: 32).fill(Color.orange)).shadow(color: Color.orange.opacity(0.3), radius: 6, y: 3)
                    }
                    .accessibilityIdentifier("newGame")
                    // Always available (also during AI vs AI); results for the old game are discarded.

                    Button(action: { if let move = previewMove { executeMove(x: move.0, y: move.1) } }) {
                        Text("PLACE").font(.system(size: 20, weight: .black)).tracking(2).foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 64)
                            .background(RoundedRectangle(cornerRadius: 32).fill(previewMove != nil ? Color(red: 30/255, green: 130/255, blue: 240/255) : Color.gray.opacity(0.3)))
                            .shadow(color: previewMove != nil ? Color(red: 30/255, green: 130/255, blue: 240/255).opacity(0.4) : .clear, radius: 8, y: 4)
                    }
                    .disabled(previewMove == nil || isThinking || finalScore != nil || !isUserTurn)
                }
                .padding(.horizontal, 20).padding(.bottom, 30)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            
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
            if showSplashScreen {
                SplashScreenView()
                    .transition(.opacity)
                    .zIndex(100)
            }
            #if DEBUG
            // Invisible, Debug builds only: lets UI tests check what the engine received.
            Text(engineStatus)
                .font(.system(size: 1))
                .foregroundColor(backgroundColor)
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("engineStatus")
            #endif
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // When the app only hosts the engine unit tests (WeiqiTests), those tests drive the
            // shared KataGo engine directly; keep the game UI idle so it cannot interfere.
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
            #if DEBUG
            // UI tests can start from a first launch (no saved settings, game or result).
            if ProcessInfo.processInfo.environment["WEIQI_UITEST_RESET"] == "1" {
                UserDefaults.standard.removeObject(forKey: GameSettings.userDefaultsKey)
                PersistedMove.clear()
                PersistedResult.clear()
            }
            #endif
            let saved = GameSettings.load()
            pendingSettings = saved
            currentVisits = saved.visits
            pendingVisits = saved.visits
            // Initialize engine immediately in background while splash screen is displayed
            initializeEngine()
            // Keep splash screen visible for a minimum of 1.4s for smooth visual transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                minSplashTimePassed = true
                if isEngineInitialized || initError != nil {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        showSplashScreen = false
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showNewGame) {
            NewGameView(settings: $pendingSettings, visits: $pendingVisits) {
                showNewGame = false
                pendingSettings.visits = pendingVisits
                pendingSettings.save()
                startNewGame(settings: pendingSettings, visits: pendingVisits)
            }
            .onAppear {
                let saved = GameSettings.load()
                pendingSettings = saved
                pendingVisits = saved.visits
            }
        }
        .alert("Game Over", isPresented: $showGameOverDialog) {
            Button("NEW GAME") { showNewGame = true }
            Button("BACK TO BOARD", role: .cancel) { }
        } message: { Text("Result: \(finalScore ?? "Unknown")") }
    }

    // MARK: - Turn ownership

    /// True when `color` is played by the person holding the device.
    private func isHumanColor(_ color: Stone) -> Bool {
        switch gameMode {
        case .userBoth: return true
        case .aiBoth: return false
        case .userBlack: return color == .black
        case .userWhite: return color == .white
        }
    }

    private var isUserTurn: Bool { isHumanColor(currentTurn) }

    /// Moves taken back by Undo. Against KataGo, Undo returns to your last decision (your move and
    /// KataGo's reply) so it is your turn again; it is unavailable until you have made a move.
    private var movesToUndo: Int {
        switch gameMode {
        case .aiBoth:
            return 0
        case .userBoth:
            return moveHistory.isEmpty ? 0 : 1
        case .userBlack, .userWhite:
            guard let lastHumanMove = moveHistory.lastIndex(where: { isHumanColor(Stone(rawValue: $0.stone) ?? .empty) }) else { return 0 }
            return moveHistory.count - lastHumanMove
        }
    }

    private func handleTap(x: Int, y: Int) {
        guard isEngineInitialized, !isThinking, finalScore == nil, isUserTurn, boardState[y][x] == .empty else { return }
        previewMove = (x, y)
    }

    // MARK: - Engine state

    /// Board, captures and side to move as reported by the engine, which is the source of truth.
    private struct EngineSnapshot {
        let board: [[Stone]]
        let blackCaptures: Int
        let whiteCaptures: Int
        let toMove: Stone?
    }

    /// Reads the engine position. Call on `engineQueue`.
    private static func readSnapshot(_ engine: KataGoWrapper) -> EngineSnapshot? {
        guard let res = engine.sendGtpCommand("get_board"), res.hasPrefix("=") else { return nil }
        let tokens = res.dropFirst().split(separator: " ").map(String.init)
        guard let gridStr = tokens.first, gridStr.count >= 361 else { return nil }
        var newBoard = Array(repeating: Array(repeating: Stone.empty, count: 19), count: 19)
        let chars = Array(gridStr)
        for y in 0..<19 {
            for x in 0..<19 {
                let c = chars[y * 19 + x]
                if c == "1" { newBoard[y][x] = .black }
                else if c == "2" { newBoard[y][x] = .white }
            }
        }
        let toMove: Stone? = tokens.count >= 4 ? (tokens[3] == "W" ? .white : (tokens[3] == "B" ? .black : nil)) : nil
        return EngineSnapshot(
            board: newBoard,
            blackCaptures: tokens.count >= 3 ? Int(tokens[1]) ?? 0 : 0,
            whiteCaptures: tokens.count >= 3 ? Int(tokens[2]) ?? 0 : 0,
            toMove: toMove
        )
    }

    private func apply(_ snapshot: EngineSnapshot?) {
        refreshEngineStatus()
        guard let snapshot = snapshot else { return }
        boardState = snapshot.board
        blackCaptures = snapshot.blackCaptures
        whiteCaptures = snapshot.whiteCaptures
        if let toMove = snapshot.toMove { currentTurn = toMove }
    }

    /// Debug builds only: publishes the engine's search limit, komi, the moves replayed when the game
    /// was loaded, the app's memory footprint (MB) and turn-order refusals for UI tests.
    private func refreshEngineStatus() {
        #if DEBUG
        guard let engine = bridge else { return }
        let handicap = currentHandicap
        let restored = restoredMoves
        Self.engineQueue.async {
            func value(_ cmd: String) -> String {
                (engine.sendGtpCommand(cmd) ?? "").replacingOccurrences(of: "= ", with: "")
            }
            let status = "visits=\(value("kata-get-param maxVisits")) komi=\(value("get_komi")) handicap=\(handicap) "
                + "restored=\(restored) mem=\(Self.memoryFootprintMB()) refused=\(value("get_turn_refusals"))"
            DispatchQueue.main.async { self.engineStatus = status }
        }
        #endif
    }

    #if DEBUG
    /// Physical memory footprint of the app in MB (what Xcode's memory gauge shows), or -1.
    private static func memoryFootprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }
    #endif

    /// Ownership (territory and dead stones) from an analysis response.
    private static func parseOwnership(_ response: String?) -> [Double]? {
        guard let ana = response, ana.hasPrefix("=") else { return nil }
        let jsonStr = ana.replacingOccurrences(of: "= ", with: "").replacingOccurrences(of: "=", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let raw = json["ownership"] as? [NSNumber] { return raw.map { $0.doubleValue } }
        return json["ownership"] as? [Double]
    }

    private func playCommand(for move: PersistedMove) -> String {
        let color = move.stone == 1 ? "black" : "white"
        return move.isPass ? "play \(color) pass" : "play \(color) \(toGtpCoord(x: move.x, y: move.y))"
    }

    // MARK: - Moves

    private func executeMove(x: Int, y: Int) {
        guard let engine = bridge, !isThinking, finalScore == nil, isUserTurn, boardState[y][x] == .empty else { return }
        let turnColor = currentTurn
        let turnVal = turnColor.rawValue
        let coord = toGtpCoord(x: x, y: y)
        let generation = gameGeneration

        previewMove = nil
        analysis.candidates = []
        isThinking = true

        Self.engineQueue.async {
            let res = engine.sendGtpCommand("play \(turnColor == .black ? "black" : "white") \(coord)")
            let accepted = res?.hasPrefix("=") == true
            let snapshot = Self.readSnapshot(engine)
            DispatchQueue.main.async {
                guard generation == self.gameGeneration else { return }
                self.isThinking = false
                guard accepted else {
                    // Ko, suicide or superko: the engine refused the move.
                    self.apply(snapshot)
                    self.showPassReminder(message: NSLocalizedString("Illegal move", comment: ""))
                    self.checkAiTurn()
                    return
                }

                let move = PersistedMove(x: x, y: y, isPass: false, stone: turnVal)
                self.moveHistory.append(move)
                self.redoStack.removeAll()
                self.lastMove = (x, y)
                self.currentTurn = (turnColor == .black ? .white : .black)
                self.consecutivePasses = 0
                PersistedMove.saveAll(self.moveHistory)

                self.apply(snapshot)
                SoundManager.shared.playStoneSound(withHaptic: true)

                self.checkAiTurn()
            }
        }
    }

    private func handlePass() {
        guard let engine = bridge, !isThinking, finalScore == nil, isUserTurn else { return }
        let turnColor = currentTurn
        let turnVal = turnColor.rawValue
        let generation = gameGeneration

        isThinking = true
        previewMove = nil
        analysis.candidates = []

        Self.engineQueue.async {
            let res = engine.sendGtpCommand("play \(turnColor == .black ? "black" : "white") pass")
            let snapshot = Self.readSnapshot(engine)
            DispatchQueue.main.async {
                guard generation == self.gameGeneration else { return }
                self.isThinking = false
                guard let response = res, response.hasPrefix("=") else {
                    self.apply(snapshot)
                    return
                }

                let move = PersistedMove(x: -1, y: -1, isPass: true, stone: turnVal)
                self.moveHistory.append(move)
                self.redoStack.removeAll()
                self.currentTurn = (turnColor == .black ? .white : .black)
                self.consecutivePasses += 1
                PersistedMove.saveAll(self.moveHistory)
                self.apply(snapshot)

                if self.consecutivePasses >= 2 {
                    self.finishGame()
                } else {
                    self.checkAiTurn()
                }
            }
        }
    }

    private func handleResign() {
        guard !isThinking, finalScore == nil else { return }
        let winnerScore: String
        if gameMode == .userBlack {
            winnerScore = "W+R"
        } else if gameMode == .userWhite {
            winnerScore = "B+R"
        } else {
            winnerScore = (currentTurn == .black ? "W+R" : "B+R")
        }
        previewMove = nil
        finalScore = winnerScore
        showGameOverDialog = true
    }

    private func restartCurrentGame() {
        previewMove = nil
        let saved = GameSettings.load()
        startNewGame(settings: saved, visits: saved.visits)
    }

    private func checkAiTurn() {
        guard isEngineInitialized, !isThinking, finalScore == nil else { return }
        if !isUserTurn {
            triggerAiMove()
        } else if showAnalysis {
            triggerAnalysis()
        }
    }

    private func triggerAiMove() {
        guard let engine = bridge, !isThinking, finalScore == nil else { return }
        let aiColor = currentTurn
        let wantAnalysis = showAnalysis
        let generation = gameGeneration
        isThinking = true

        Self.engineQueue.async {
            let res = engine.sendGtpCommand("genmove \(aiColor == .black ? "black" : "white")")

            var rootInfo: [String: Any]? = nil
            var parsedOwnership: [Double]? = nil
            if wantAnalysis {
                if let anaRes = engine.sendGtpCommand("kata-get-analysis black"), anaRes.hasPrefix("=") {
                    let jsonStr = anaRes.replacingOccurrences(of: "= ", with: "").replacingOccurrences(of: "=", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if let data = jsonStr.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        rootInfo = json["rootInfo"] as? [String: Any]
                        if let raw = json["ownership"] as? [NSNumber] {
                            parsedOwnership = raw.map { $0.doubleValue }
                        } else if let raw = json["ownership"] as? [Double] {
                            parsedOwnership = raw
                        }
                    }
                }
            }
            let snapshot = Self.readSnapshot(engine)

            DispatchQueue.main.async {
                guard generation == self.gameGeneration else { return }
                self.isThinking = false

                if let info = rootInfo {
                    self.analysis.winrate = info["winrate"] as? Double ?? 0.5
                    self.analysis.scoreLead = info["scoreLead"] as? Double ?? 0.0
                }
                if let owner = parsedOwnership {
                    self.analysis.ownership = owner
                }

                guard let response = res, response.hasPrefix("=") else {
                    // The engine refused (e.g. turn mismatch); resync whose turn it is.
                    self.apply(snapshot)
                    return
                }
                let moveStr = response.replacingOccurrences(of: "= ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)

                if moveStr.uppercased() == "PASS" {
                    let aiColorName = aiColor == .black ? NSLocalizedString("Black", comment: "") : NSLocalizedString("White", comment: "")
                    let format = NSLocalizedString("AI (%@) Passed", comment: "")
                    self.showPassReminder(message: String(format: format, aiColorName))

                    let move = PersistedMove(x: -1, y: -1, isPass: true, stone: aiColor.rawValue)
                    self.moveHistory.append(move)
                    self.redoStack.removeAll()
                    self.currentTurn = (aiColor == .black ? .white : .black)
                    self.consecutivePasses += 1
                    PersistedMove.saveAll(self.moveHistory)
                    self.apply(snapshot)

                    if self.consecutivePasses >= 2 {
                        self.finishGame()
                    } else if self.showAnalysis && self.finalScore == nil {
                        self.triggerAnalysis()
                    }
                } else if let pos = self.fromGtpCoord(moveStr) {
                    let move = PersistedMove(x: pos.0, y: pos.1, isPass: false, stone: aiColor.rawValue)
                    self.moveHistory.append(move)
                    self.redoStack.removeAll()
                    self.lastMove = pos
                    self.currentTurn = (aiColor == .black ? .white : .black)
                    self.consecutivePasses = 0
                    PersistedMove.saveAll(self.moveHistory)
                    self.apply(snapshot)
                    SoundManager.shared.playStoneSound(withHaptic: false)
                    if self.showAnalysis && self.finalScore == nil {
                        self.triggerAnalysis()
                    }
                }

                if self.gameMode == .aiBoth && self.finalScore == nil && self.consecutivePasses < 2 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        guard generation == self.gameGeneration else { return }
                        self.checkAiTurn()
                    }
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
        guard let engine = bridge, isEngineInitialized, !isThinking, !isAnalyzing else { return }
        let turnColor = currentTurn
        let currentHistoryCount = moveHistory.count
        let analysisVisits = max(100, Int(Double(currentVisits) * 0.4))
        let generation = gameGeneration
        isAnalyzing = true
        Self.engineQueue.async {
            let p = turnColor == .black ? "black" : "white"
            _ = engine.sendGtpCommand("think \(p) \(analysisVisits)")
            let res = engine.sendGtpCommand("kata-get-analysis black")
            var newWinrate: Double? = nil
            var newScoreLead: Double? = nil
            var newOwnership: [Double]? = nil
            var newCandidates: [CandidateMove] = []
            if let response = res, response.hasPrefix("=") {
                let jsonStr = response.replacingOccurrences(of: "= ", with: "").replacingOccurrences(of: "=", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                if let data = jsonStr.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let rootInfo = json["rootInfo"] as? [String: Any] {
                        newWinrate = rootInfo["winrate"] as? Double
                        newScoreLead = rootInfo["scoreLead"] as? Double
                    }
                    if let raw = json["ownership"] as? [NSNumber] {
                        newOwnership = raw.map { $0.doubleValue }
                    } else if let raw = json["ownership"] as? [Double] {
                        newOwnership = raw
                    }
                    if let moveInfos = json["moveInfos"] as? [[String: Any]] {
                        var parsed: [CandidateMove] = []
                        var rank = 1
                        for info in moveInfos {
                            guard let moveStr = info["move"] as? String,
                                  let (cx, cy) = CandidateMove.fromGtpCoord(moveStr) else { continue }
                            let visits = info["visits"] as? Int ?? 0
                            let blackWr = info["winrate"] as? Double ?? 0.5
                            let blackLead = info["scoreLead"] as? Double ?? 0.0
                            let displayWr = (turnColor == .black) ? blackWr : (1.0 - blackWr)
                            let displayLead = (turnColor == .black) ? blackLead : -blackLead

                            parsed.append(CandidateMove(
                                x: cx,
                                y: cy,
                                winrate: displayWr,
                                visits: visits,
                                scoreLead: displayLead,
                                order: rank
                            ))
                            rank += 1
                            if parsed.count >= 5 { break }
                        }
                        newCandidates = parsed
                    }
                }
            }
            DispatchQueue.main.async {
                self.isAnalyzing = false
                guard generation == self.gameGeneration, self.showAnalysis, self.moveHistory.count == currentHistoryCount else { return }
                if let wr = newWinrate { self.analysis.winrate = wr }
                if let sl = newScoreLead { self.analysis.scoreLead = sl }
                if let owner = newOwnership { self.analysis.ownership = owner }
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.analysis.candidates = newCandidates
                }
            }
        }
    }

    /// Scores the finished game. `presentDialog` is false when re-opening an already finished game.
    private func finishGame(presentDialog: Bool = true) {
        guard let engine = bridge else { return }
        let generation = gameGeneration
        isThinking = true
        isScoring = true
        previewMove = nil
        Self.engineQueue.async {
            let res = engine.sendGtpCommand("final_score")
            let parsedOwnership = Self.parseOwnership(engine.sendGtpCommand("kata-get-analysis black"))
            DispatchQueue.main.async {
                guard generation == self.gameGeneration else { return }
                self.isThinking = false
                self.isScoring = false
                if let owner = parsedOwnership {
                    self.analysis.ownership = owner
                }
                self.analysis.candidates = []
                if let response = res, response.hasPrefix("=") {
                    let result = response.replacingOccurrences(of: "= ", with: "")
                    self.finalScore = result
                    // Remember it, so reopening the finished game shows the same result without re-scoring.
                    PersistedResult(moveCount: self.moveHistory.count, result: result).save()
                } else {
                    self.finalScore = "Game Ended"
                }
                self.showGameOverDialog = presentDialog
                self.refreshEngineStatus()
            }
        }
    }

    /// Re-opens a finished game with its saved result; only the territory display is recomputed.
    private func showSavedResult(_ result: String) {
        guard let engine = bridge else { return }
        let generation = gameGeneration
        finalScore = result
        previewMove = nil
        analysis.candidates = []
        Self.engineQueue.async {
            let ownership = Self.parseOwnership(engine.sendGtpCommand("kata-get-analysis black"))
            DispatchQueue.main.async {
                guard generation == self.gameGeneration, let owner = ownership else { return }
                self.analysis.ownership = owner
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

        Self.engineQueue.async {
            let status = engine.initEngine(withConfig: configPath, model: modelPath, storage: storagePath)
            if status == 0 {
                DispatchQueue.main.async {
                    self.bridge = engine
                    self.isEngineInitialized = true
                    self.initError = nil
                    let savedSettings = GameSettings.load()
                    let savedMoves = PersistedMove.loadAll()
                    restoreGame(settings: savedSettings, moves: savedMoves)
                    if self.minSplashTimePassed {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            self.showSplashScreen = false
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.initError = "KataGo failed to initialize (Error Code: \(status))"
                    if self.minSplashTimePassed {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            self.showSplashScreen = false
                        }
                    }
                }
            }
        }
    }

    private func startNewGame(settings: GameSettings, visits: Int) {
        showNewGame = false
        showSettings = false
        PersistedMove.saveAll([])
        PersistedResult.clear()
        restoreGame(settings: settings, moves: [])
    }

    private func restoreGame(settings: GameSettings, moves: [PersistedMove]) {
        guard let engine = bridge else { return }
        // Invalidate every pending result from the previous game (AI move, analysis, scoring).
        gameGeneration += 1
        let generation = gameGeneration
        isThinking = true
        isScoring = false
        previewMove = nil
        analysis.candidates = []
        showGameOverDialog = false
        Self.engineQueue.async {
            engine.sendGtpCommand("clear_board")
            engine.sendGtpCommand("set_max_visits \(settings.visits)")
            engine.sendGtpCommand("komi \(settings.handicap > 0 ? 0.5 : 7.5)")
            if settings.handicap > 0 {
                _ = engine.sendGtpCommand("fixed_handicap \(settings.handicap)")
            }
            
            // Clean up any legacy persisted handicap stones from older versions
            let gameMoves: [PersistedMove]
            if settings.handicap > 0 && moves.count >= settings.handicap && moves.prefix(settings.handicap).allSatisfy({ $0.stone == 1 && !$0.isPass }) {
                gameMoves = Array(moves.dropFirst(settings.handicap))
            } else {
                gameMoves = moves
            }

            // Replay the saved game. Stop at the first move the engine rejects so the move list
            // always matches the engine's game record.
            var history: [PersistedMove] = []
            for move in gameMoves {
                guard engine.sendGtpCommand(self.playCommand(for: move))?.hasPrefix("=") == true else { break }
                history.append(move)
            }
            let snapshot = Self.readSnapshot(engine)
            
            DispatchQueue.main.async {
                guard generation == self.gameGeneration else { return }
                let trailingPasses = history.reversed().prefix(while: { $0.isPass }).count
                self.lastMove = history.last(where: { !$0.isPass }).map { ($0.x, $0.y) }
                self.previewMove = nil
                self.finalScore = nil
                self.analysis = AnalysisResult()
                self.consecutivePasses = trailingPasses
                self.moveHistory = history
                self.redoStack = []
                self.gameMode = settings.mode
                self.currentHandicap = settings.handicap
                self.restoredMoves = history.count
                self.currentVisits = settings.visits
                if let last = history.last {
                    self.currentTurn = last.stone == 1 ? .white : .black
                } else {
                    self.currentTurn = settings.handicap > 0 ? .white : .black
                }
                self.apply(snapshot)
                if history.count != moves.count {
                    PersistedMove.saveAll(history)
                }
                self.isThinking = false
                if trailingPasses >= 2 {
                    // The saved game had already ended: show its result instead of playing on.
                    if let saved = PersistedResult.load(), saved.moveCount == history.count {
                        self.showSavedResult(saved.result)
                    } else {
                        self.finishGame(presentDialog: false)
                    }
                } else {
                    self.checkAiTurn()
                }
            }
        }
    }

    private func undoMove() {
        let count = movesToUndo
        guard let engine = bridge, !isThinking, count > 0 else { return }
        let generation = gameGeneration
        isThinking = true
        previewMove = nil
        analysis.candidates = []

        Self.engineQueue.async {
            var undone = 0
            while undone < count, engine.sendGtpCommand("undo")?.hasPrefix("=") == true {
                undone += 1
            }
            let snapshot = Self.readSnapshot(engine)
            DispatchQueue.main.async {
                guard generation == self.gameGeneration else { return }
                self.isThinking = false
                guard undone > 0 else {
                    self.apply(snapshot)
                    return
                }
                let removed = Array(self.moveHistory.suffix(undone))
                self.moveHistory.removeLast(undone)
                // Pushed newest-first so Redo replays them in their original order.
                self.redoStack.append(contentsOf: removed.reversed())
                self.lastMove = self.moveHistory.last(where: { !$0.isPass }).map { ($0.x, $0.y) }
                self.currentTurn = Stone(rawValue: removed[0].stone) ?? .black
                self.consecutivePasses = self.moveHistory.reversed().prefix(while: { $0.isPass }).count
                // Taking back a move after the game ended resumes play.
                self.finalScore = nil
                self.showGameOverDialog = false
                PersistedResult.clear()
                PersistedMove.saveAll(self.moveHistory)
                self.apply(snapshot)
                self.checkAiTurn()
            }
        }
    }
    
    private func redoMove() {
        guard let engine = bridge, !isThinking, !redoStack.isEmpty, gameMode != .aiBoth else { return }
        // Replay one move; against KataGo also replay its stored reply so it is your turn again.
        var batch: [PersistedMove] = []
        for move in redoStack.reversed() {
            batch.append(move)
            let nextToMove: Stone = move.stone == 1 ? .white : .black
            if isHumanColor(nextToMove) { break }
        }
        let generation = gameGeneration
        isThinking = true
        previewMove = nil
        analysis.candidates = []

        Self.engineQueue.async {
            var replayed: [PersistedMove] = []
            for move in batch {
                guard engine.sendGtpCommand(self.playCommand(for: move))?.hasPrefix("=") == true else { break }
                replayed.append(move)
            }
            let snapshot = Self.readSnapshot(engine)
            DispatchQueue.main.async {
                guard generation == self.gameGeneration else { return }
                self.isThinking = false
                if replayed.count == batch.count {
                    self.redoStack.removeLast(replayed.count)
                } else {
                    // A stored move no longer applies; the rest of the redo list is invalid too.
                    self.redoStack.removeAll()
                }
                guard let last = replayed.last else {
                    self.apply(snapshot)
                    return
                }
                self.moveHistory.append(contentsOf: replayed)
                self.lastMove = self.moveHistory.last(where: { !$0.isPass }).map { ($0.x, $0.y) }
                self.consecutivePasses = self.moveHistory.reversed().prefix(while: { $0.isPass }).count
                self.currentTurn = (last.stone == 1 ? .white : .black)
                PersistedMove.saveAll(self.moveHistory)
                self.apply(snapshot)
                if replayed.contains(where: { !$0.isPass }) {
                    SoundManager.shared.playStoneSound(withHaptic: true)
                }
                if self.consecutivePasses >= 2 {
                    self.finishGame()
                } else {
                    self.checkAiTurn()
                }
            }
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
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject private var soundManager = SoundManager.shared

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.15"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "16"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationView {
            Form {
                // 1. Sound & Haptics
                Section(header: Text(LocalizedStringKey("Sound & Haptics"))) {
                    Toggle(LocalizedStringKey("Stone Sound"), isOn: $soundManager.isSoundEnabled)
                    Toggle(LocalizedStringKey("Haptic Feedback"), isOn: $soundManager.isHapticEnabled)
                }

                // 2. About & Engine Info
                Section(header: Text(LocalizedStringKey("About & Engine Info"))) {
                    HStack {
                        Text(LocalizedStringKey("Engine"))
                        Spacer()
                        Text("KataGo v1.15").foregroundColor(.secondary)
                    }
                    HStack {
                        Text(LocalizedStringKey("Neural Network"))
                        Spacer()
                        Text("15-Block CNN").foregroundColor(.secondary)
                    }
                    HStack {
                        Text(LocalizedStringKey("Hardware Acceleration"))
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill").foregroundColor(.yellow)
                            Text("Apple Metal GPU").foregroundColor(.secondary)
                        }
                    }
                    HStack {
                        Text(LocalizedStringKey("Rules"))
                        Spacer()
                        Text(LocalizedStringKey("Chinese Rules (7.5 Komi)")).foregroundColor(.secondary)
                    }
                    HStack {
                        Text(LocalizedStringKey("App Version"))
                        Spacer()
                        Text(appVersion).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(LocalizedStringKey("Settings"))
            .navigationBarItems(trailing: Button(LocalizedStringKey("Done")) {
                presentationMode.wrappedValue.dismiss()
            })
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct NewGameView: View {
    @Binding var settings: GameSettings
    @Binding var visits: Int
    var onStart: () -> Void
    @Environment(\.presentationMode) var presentationMode
    
    @ObservedObject private var storeManager = StoreManager.shared
    
    private let levels: [(String, Int)] = [("Easy", 100), ("Amateur", 500), ("Advanced", 1000), ("Pro", 2500)]

    private var handicapLabel: LocalizedStringKey {
        switch settings.handicap {
        case 0: return "No Handicap"
        case 1: return "1 Stone"
        default: return "\(settings.handicap) Stones"
        }
    }

    /// Handicap stones always go to Black, so spell out who that is for the chosen side.
    @ViewBuilder
    private var handicapFooter: some View {
        if settings.handicap > 0 {
            switch settings.mode {
            case .userBlack:
                Text("You play Black and receive the handicap stones. KataGo (White) moves first.")
            case .userWhite:
                Text("KataGo plays Black and receives the handicap stones. You (White) move first.")
            case .userBoth, .aiBoth:
                Text("Black receives the handicap stones. White moves first.")
            }
        }
    }
    
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
                                    .accessibilityAddTraits(visits == level.1 ? .isSelected : [])
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
                        Picker("", selection: $settings.mode) {
                            ForEach(GameMode.allCases, id: \.self) { (mode: GameMode) in
                                Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                    
                    Section(header: Text("Handicap"), footer: handicapFooter) {
                        Stepper(value: $settings.handicap, in: 0...9) {
                            Text(handicapLabel)
                        }
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
                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                            onStart()
                        }) {
                            Text(LocalizedStringKey("START GAME"))
                                .font(.system(size: 16, weight: .black))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.blue)
                                .cornerRadius(25)
                        }
                        .accessibilityIdentifier("startGame")
                    }
                }
                .padding([.horizontal, .bottom])
                .background(Color(UIColor.systemGroupedBackground))
            }
            .navigationTitle(LocalizedStringKey("New Game"))
            .navigationBarItems(trailing: Button(LocalizedStringKey("Cancel")) { presentationMode.wrappedValue.dismiss() })
        }
        .navigationViewStyle(StackNavigationViewStyle())
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
    var lineWidth: CGFloat = 2.5
    @State private var isRotating = false
    
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [color, color.opacity(0.15)]),
                    center: .center
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(Angle(degrees: isRotating ? 360 : 0))
            .animation(
                Animation.linear(duration: 0.85).repeatForever(autoreverses: false),
                value: isRotating
            )
            .onAppear {
                isRotating = true
            }
    }
}

struct SplashScreenView: View {
    @State private var isPulsing = false
    private let backgroundColor = Color(red: 24/255, green: 24/255, blue: 28/255)
    private let accentColor = Color(red: 100/255, green: 200/255, blue: 255/255)

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            // Main Brand Block (seamless match with LaunchScreen storyboard positioning)
            VStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(accentColor.opacity(0.18))
                        .frame(width: 132, height: 132)
                        .blur(radius: isPulsing ? 14 : 6)
                        .scaleEffect(isPulsing ? 1.08 : 0.98)

                    Image("LaunchIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                        // UI tests wait for the splash to go away: it covers the board and buttons.
                        .accessibilityIdentifier("splashScreen")
                }
                .frame(width: 120, height: 120)

                VStack(spacing: 8) {
                    Text("围棋 碁 GO!")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                        .tracking(1)

                    Text(LocalizedStringKey("Powered by KataGo Metal"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray.opacity(0.85))
                        .tracking(0.5)
                }
            }
            .offset(y: -40)

            // Bottom loading status
            VStack {
                Spacer()
                VStack(spacing: 14) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: accentColor))
                        .scaleEffect(1.1)

                    Text(LocalizedStringKey("Initializing Neural Engine..."))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray.opacity(0.85))
                }
                .padding(.bottom, 64)
            }
        }
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}
