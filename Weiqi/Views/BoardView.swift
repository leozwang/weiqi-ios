import SwiftUI

struct BoardView: View {
    let boardState: [[Stone]]
    let previewMove: (Int, Int)?
    let lastMove: (Int, Int)?
    let analysis: AnalysisResult
    let showAnalysis: Bool
    let isGameOver: Bool
    let currentTurnColor: Stone
    var onMoveTapped: (Int, Int) -> Void

    private let boardColor = Color(red: 245/255, green: 200/255, blue: 110/255)
    private let boardSize: Int = 19
    private let marginRatio: CGFloat = 0.015

    var body: some View {
        GeometryReader { geometry in
            let side = geometry.size.width
            let margin = side * marginRatio
            let gridSize = side - 2 * margin
            let step = gridSize / CGFloat(boardSize - 1)
            let stoneRadius = (step / 2) * 0.98

            ZStack {
                // 1. Board Background
                Rectangle()
                    .fill(boardColor)
                    .frame(width: side, height: side)

                // 2. Grid Lines (Safe Shape implementation)
                GridShape(boardSize: boardSize, margin: margin)
                    .stroke(Color.black.opacity(0.8), lineWidth: 0.6)

                // 3. Hoshi Points (Individual views)
                HoshiOverlay(boardSize: boardSize, margin: margin)
                
                // 4. Ownership Analysis Dots
                if (showAnalysis || isGameOver) && !analysis.ownership.isEmpty {
                    ForEach(0..<boardSize, id: \.self) { y in
                        ForEach(0..<boardSize, id: \.self) { x in
                            let score = analysis.ownership[y * boardSize + x]
                            if abs(score) > 0.1 {
                                Circle()
                                    .fill(score > 0 ? Color.black : Color.white)
                                    .opacity(abs(score) * 0.4)
                                    .frame(width: 6, height: 6)
                                    .position(x: margin + CGFloat(x) * step, y: margin + CGFloat(y) * step)
                            }
                        }
                    }
                }

                // 5. Stones
                ForEach(0..<boardSize, id: \.self) { y in
                    ForEach(0..<boardSize, id: \.self) { x in
                        let stone = boardState[y][x]
                        if stone != .empty {
                            StoneView(stone: stone, radius: stoneRadius)
                                .position(x: margin + CGFloat(x) * step, y: margin + CGFloat(y) * step)
                            
                            // Last Move Marker
                            if lastMove?.0 == x && lastMove?.1 == y {
                                Circle()
                                    .stroke(stone == .black ? .white : .black, lineWidth: 1.5)
                                    .frame(width: 8, height: 8)
                                    .position(x: margin + CGFloat(x) * step, y: margin + CGFloat(y) * step)
                            }
                        }
                    }
                }
                
                // 6. Preview Move
                if let (px, py) = previewMove, boardState[py][px] == .empty {
                    StoneView(stone: currentTurnColor, radius: stoneRadius)
                        .opacity(0.5)
                        .position(x: margin + CGFloat(px) * step, y: margin + CGFloat(py) * step)
                }

                // 7. Gesture Overlay
                Color.white.opacity(0.001)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                let x = Int(((value.location.x - margin) / step).rounded())
                                let y = Int(((value.location.y - margin) / step).rounded())
                                if x >= 0 && x < boardSize && y >= 0 && y < boardSize {
                                    onMoveTapped(x, y)
                                }
                            }
                    )
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(4)
    }
}

struct StoneView: View {
    let stone: Stone
    let radius: CGFloat
    
    var body: some View {
        ZStack {
            // Simple shadow
            Circle()
                .fill(Color.black.opacity(0.3))
                .offset(x: 1, y: 1)
            
            // Stone with radial gradient
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: stone == .black ? [Color(white: 0.3), .black] : [.white, Color(white: 0.9)]),
                        center: .init(x: 0.35, y: 0.35),
                        startRadius: 0,
                        endRadius: radius * 1.2
                    )
                )
            
            if stone == .white {
                Circle().stroke(Color.black.opacity(0.1), lineWidth: 0.5)
            }
        }
        .frame(width: radius * 2, height: radius * 2)
    }
}

struct GridShape: Shape {
    let boardSize: Int
    let margin: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let gridSize = rect.width - 2 * margin
        let step = gridSize / CGFloat(boardSize - 1)

        for i in 0..<boardSize {
            let pos = margin + CGFloat(i) * step
            // Horizontal
            path.move(to: CGPoint(x: margin, y: pos))
            path.addLine(to: CGPoint(x: margin + gridSize, y: pos))
            // Vertical
            path.move(to: CGPoint(x: pos, y: margin))
            path.addLine(to: CGPoint(x: pos, y: margin + gridSize))
        }
        return path
    }
}

struct HoshiOverlay: View {
    let boardSize: Int
    let margin: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            let gridSize = geometry.size.width - 2 * margin
            let step = gridSize / CGFloat(boardSize - 1)
            let hoshiIndices = [3, 9, 15]
            
            ZStack {
                ForEach(hoshiIndices, id: \.self) { row in
                    ForEach(hoshiIndices, id: \.self) { col in
                        Circle()
                            .fill(Color.black)
                            .frame(width: 4, height: 4)
                            .position(
                                x: margin + CGFloat(col) * step,
                                y: margin + CGFloat(row) * step
                            )
                    }
                }
            }
        }
    }
}
