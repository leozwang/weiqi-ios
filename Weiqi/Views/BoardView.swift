import SwiftUI

struct BoardView: View {
    let boardSize: Int = 19
    let boardState: [[Stone]]
    let previewMove: (Int, Int)?
    let lastMove: (Int, Int)?
    let analysis: AnalysisResult
    let showAnalysis: Bool
    let isGameOver: Bool
    let currentTurnColor: Stone
    var onMoveTapped: (Int, Int) -> Void

    private let boardColor = Color(red: 245/255, green: 200/255, blue: 110/255)
    private let boardColorDark = Color(red: 210/255, green: 160/255, blue: 80/255)
    private let marginRatio: CGFloat = 0.015 // Maximized to edges

    var body: some View {
        GeometryReader { geometry in
            let side = geometry.size.width
            let margin = side * marginRatio
            let gridSize = side - 2 * margin
            let step = gridSize / CGFloat(boardSize - 1)
            let stoneRadius = (step / 2) * 0.98

            ZStack {
                // Board Background - Sharp edges
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [boardColor, boardColorDark]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: side, height: side)

                // Grid lines and Hoshi
                Canvas { context, size in
                    for i in 0..<boardSize {
                        let pos = margin + CGFloat(i) * step
                        
                        var hPath = Path()
                        hPath.move(to: CGPoint(x: margin, y: pos))
                        hPath.addLine(to: CGPoint(x: margin + gridSize, y: pos))
                        context.stroke(hPath, with: .color(.black.opacity(0.85)), lineWidth: 0.6)

                        var vPath = Path()
                        vPath.move(to: CGPoint(x: pos, y: margin))
                        vPath.addLine(to: CGPoint(x: pos, y: margin + gridSize))
                        context.stroke(vPath, with: .color(.black.opacity(0.85)), lineWidth: 0.6)
                    }

                    let hoshiIndices = [3, 9, 15]
                    for row in hoshiIndices {
                        for col in hoshiIndices {
                            let x = margin + CGFloat(col) * step
                            let y = margin + CGFloat(row) * step
                            context.fill(Path(ellipseIn: CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)), with: .color(.black.opacity(0.9)))
                        }
                    }
                    
                    if (showAnalysis || isGameOver) && !analysis.ownership.isEmpty {
                        for y in 0..<boardSize {
                            for x in 0..<boardSize {
                                let score = analysis.ownership[y * boardSize + x]
                                if abs(score) > 0.1 {
                                    let centerX = margin + CGFloat(x) * step
                                    let centerY = margin + CGFloat(y) * step
                                    if isGameOver {
                                        let squareSize = step * 0.4
                                        context.fill(Path(CGRect(x: centerX - squareSize/2, y: centerY - squareSize/2, width: squareSize, height: squareSize)), with: .color(score > 0 ? .black.opacity(0.6) : .white.opacity(0.75)))
                                    } else {
                                        let radius: CGFloat = 3.0
                                        context.fill(Path(ellipseIn: CGRect(x: centerX - radius, y: centerY - radius, width: radius * 2, height: radius * 2)), with: .color(score > 0 ? .black.opacity(abs(score) * 0.5) : .white.opacity(abs(score) * 0.5)))
                                    }
                                }
                            }
                        }
                    }
                }

                // Candidate Moves
                if showAnalysis && !isGameOver {
                    let bestMove = analysis.candidates.max(by: { $0.visits < $1.visits })
                    ForEach(analysis.candidates, id: \.x) { candidate in
                        let centerX = margin + CGFloat(candidate.x) * step
                        let centerY = margin + CGFloat(candidate.y) * step
                        ZStack {
                            if candidate.x == bestMove?.x && candidate.y == bestMove?.y {
                                Circle().stroke(Color.red, lineWidth: 2).frame(width: step * 0.9, height: step * 0.9)
                            } else {
                                Circle().fill(Color.red.opacity(0.5)).frame(width: step * 0.7, height: step * 0.7)
                            }
                            Text("\(Int(candidate.winrate * 100))").font(.system(size: 7, weight: .bold)).foregroundColor(.white)
                        }
                        .position(x: centerX, y: centerY)
                    }
                }

                // Stones
                ForEach(0..<boardSize, id: \.self) { y in
                    ForEach(0..<boardSize, id: \.self) { x in
                        if boardState[y][x] != .empty {
                            StoneView(stone: boardState[y][x], radius: stoneRadius)
                                .position(x: margin + CGFloat(x) * step, y: margin + CGFloat(y) * step)
                        }
                    }
                }

                if let (lx, ly) = lastMove {
                    Circle()
                        .stroke(boardState[ly][lx] == .black ? Color.white : Color.black, lineWidth: 1.2)
                        .frame(width: step * 0.4, height: step * 0.4)
                        .position(x: margin + CGFloat(lx) * step, y: margin + CGFloat(ly) * step)
                }
                
                if let (px, py) = previewMove, boardState[py][px] == .empty {
                    StoneView(stone: currentTurnColor, radius: stoneRadius)
                        .opacity(0.5)
                        .position(x: margin + CGFloat(px) * step, y: margin + CGFloat(py) * step)
                }

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
    }
}

struct StoneView: View {
    let stone: Stone
    let radius: CGFloat

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(colors: stone == .black ? [Color(white: 0.3), .black] : [.white, Color(white: 0.9)]),
                    center: UnitPoint(x: 0.3, y: 0.3),
                    startRadius: 0,
                    endRadius: radius * 1.4
                )
            )
            .frame(width: radius * 2, height: radius * 2)
            .shadow(color: .black.opacity(0.5), radius: 2, x: 1, y: 1.5)
            .overlay(
                Circle()
                    .stroke(stone == .white ? Color.black.opacity(0.2) : Color.white.opacity(0.2), lineWidth: 0.5)
            )
    }
}
