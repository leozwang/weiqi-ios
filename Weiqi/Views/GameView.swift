import SwiftUI

struct GameView: View {
    @State private var gameMode: GameMode = .userBlack
    @State private var bridge: KataGoWrapper?
    @State private var status: String = "Initializing Engine..."
    @State private var boardState: [[Stone]] = Array(repeating: Array(repeating: .empty, count: 19), count: 19)
    @State private var lastMove: (Int, Int)?
    @State private var currentTurn: Stone = .black
    @State private var analysis = AnalysisResult()
    @State private var isThinking = false

    var body: some View {
        NavigationView {
            VStack {
                HeaderView(status: status, analysis: analysis, isThinking: isThinking)
                    .padding(.horizontal)

                BoardView(
                    boardState: boardState,
                    lastMove: lastMove,
                    analysis: analysis,
                    showAnalysis: true,
                    onMoveTapped: handleUserMove
                )
                .padding(4)

                Spacer()
                
                ControlBar(onReset: resetGame, onUndo: undoMove)
            }
            .navigationTitle("Weiqi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Game Mode", selection: $gameMode) {
                            Text("You are Black").tag(GameMode.userBlack)
                            Text("You are White").tag(GameMode.userWhite)
                            Text("Human vs Human").tag(GameMode.userBoth)
                            Text("AI vs AI").tag(GameMode.aiBoth)
                        }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .onChange(of: gameMode) { newMode in
                checkAiTurn()
            }
            .onAppear {
                initializeEngine()
            }
        }
    }

    private func initializeEngine() {
        let engine = KataGoWrapper()
        let configPath = Bundle.main.path(forResource: "gtp", ofType: "cfg") ?? ""
        let modelPath = Bundle.main.path(forResource: "model", ofType: "bin.gz") ?? ""

        DispatchQueue.global(qos: .userInitiated).async {
            let result = engine.initEngine(withConfig: configPath, model: modelPath)
            DispatchQueue.main.async {
                if result == 0 {
                    self.bridge = engine
                    status = "Ready"
                    syncBoard()
                    checkAiTurn()
                } else {
                    status = "Failed to initialize: \(result)"
                }
            }
        }
    }

    private func handleUserMove(x: Int, y: Int) {
        guard let engine = bridge, !isThinking else { return }
        
        // Only allow moves if it's the user's turn in the current mode
        let isUserTurn = gameMode == .userBoth ||
                         (gameMode == .userBlack && currentTurn == .black) ||
                         (gameMode == .userWhite && currentTurn == .white)
        
        guard isUserTurn else { return }
        if boardState[y][x] != .empty { return }

        let colorStr = currentTurn == .black ? "black" : "white"
        let moveStr = toGtpCoord(x: x, y: y)
        
        let res = engine.sendGtpCommand("play \(colorStr) \(moveStr)")
        if res?.hasPrefix("=") == true {
            boardState[y][x] = currentTurn
            lastMove = (x, y)
            currentTurn = (currentTurn == .black ? .white : .black)
            status = "\(currentTurn == .black ? "Black" : "White")'s turn"
            
            checkAiTurn()
        }
    }

    private func checkAiTurn() {
        guard let _ = bridge, !isThinking else { return }
        
        let shouldAiPlay = (gameMode == .aiBoth) ||
                           (gameMode == .userBlack && currentTurn == .white) ||
                           (gameMode == .userWhite && currentTurn == .black)
        
        if shouldAiPlay {
            triggerAiMove()
        }
    }

    private func triggerAiMove() {
        guard let engine = bridge, !isThinking else { return }
        
        isThinking = true
        status = "AI is thinking..."
        
        let colorStr = currentTurn == .black ? "black" : "white"
        
        DispatchQueue.global(qos: .userInitiated).async {
            let res = engine.sendGtpCommand("genmove \(colorStr)")
            
            DispatchQueue.main.async {
                isThinking = false
                if let response = res, response.hasPrefix("=") {
                    let moveStr = response.replacingOccurrences(of: "= ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if moveStr.uppercased() == "PASS" {
                        status = "AI passed"
                        currentTurn = (currentTurn == .black ? .white : .black)
                    } else if let pos = fromGtpCoord(moveStr) {
                        boardState[pos.1][pos.0] = currentTurn
                        lastMove = pos
                        currentTurn = (currentTurn == .black ? .white : .black)
                        status = "\(currentTurn == .black ? "Black" : "White")'s turn"
                    }
                    
                    // If AI vs AI, trigger next move
                    if gameMode == .aiBoth {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            checkAiTurn()
                        }
                    }
                } else {
                    status = "AI error: \(res ?? "unknown")"
                }
            }
        }
    }

    private func fromGtpCoord(_ coord: String) -> (Int, Int)? {
        let coord = coord.uppercased()
        guard coord.count >= 2 else { return nil }
        
        let letters = "ABCDEFGHJKLMNOPQRST"
        let colChar = coord.first!
        guard let col = letters.firstIndex(of: colChar) else { return nil }
        
        let rowStr = coord.dropFirst()
        guard let rowNum = Int(rowStr) else { return nil }
        let row = 19 - rowNum
        
        let colIndex = letters.distance(from: letters.startIndex, to: col)
        return (colIndex, row)
    }

    private func syncBoard() {
        // Full board sync if we had a getBoardState bridge
    }

    private func toGtpCoord(x: Int, y: Int) -> String {
        let letters = "ABCDEFGHJKLMNOPQRST"
        let col = Array(letters)[x]
        let row = 19 - y
        return "\(col)\(row)"
    }

    private func resetGame() {
        bridge?.sendGtpCommand("clear_board")
        boardState = Array(repeating: Array(repeating: .empty, count: 19), count: 19)
        lastMove = nil
        currentTurn = .black
        status = "Ready"
        checkAiTurn()
    }
    
    private func undoMove() {
        // GTP 'undo'
        let _ = bridge?.sendGtpCommand("undo")
        // Note: Full board sync would be better here
    }
}

struct HeaderView: View {
    let status: String
    let analysis: AnalysisResult
    let isThinking: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text(status)
                .font(.headline)
            
            HStack {
                Text("Winrate: \(Int(analysis.winrate * 100))%")
                Spacer()
                Text("Score: \(String(format: "%.1f", analysis.scoreLead))")
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            
            if isThinking {
                ProgressView()
                    .progressViewStyle(LinearProgressViewStyle())
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct ControlBar: View {
    var onReset: () -> Void
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: 40) {
            Button(action: onUndo) {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            Button(action: onReset) {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
        }
        .padding()
    }
}
