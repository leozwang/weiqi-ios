import SwiftUI

struct BoardView: View {
    let boardSize: Int = 19
    let boardState: [[Stone]]
    let lastMove: (Int, Int)?
    let analysis: AnalysisResult
    let showAnalysis: Bool
    var onMoveTapped: (Int, Int) -> Void

    private let boardColor = Color(red: 220/255, green: 179/255, blue: 92/255)
    private let marginRatio: CGFloat = 0.08

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let margin = side * marginRatio
            let gridSize = side - 2 * margin
            let step = gridSize / CGFloat(boardSize - 1)

            ZStack {
                Rectangle()
                    .fill(boardColor)
                    .frame(width: side, height: side)

                // Grid lines
                Canvas { context, size in
                    for i in 0..<boardSize {
                        let pos = margin + CGFloat(i) * step
                        // Horizontal
                        var hPath = Path()
                        hPath.move(to: CGPoint(x: margin, y: pos))
                        hPath.addLine(to: CGPoint(x: margin + gridSize, y: pos))
                        context.stroke(hPath, with: .color(.black.opacity(0.8)), lineWidth: 1)

                        // Vertical
                        var vPath = Path()
                        vPath.move(to: CGPoint(x: pos, y: margin))
                        vPath.addLine(to: CGPoint(x: pos, y: margin + gridSize))
                        context.stroke(vPath, with: .color(.black.opacity(0.8)), lineWidth: 1)
                    }

                    // Hoshi points
                    let hoshiIndices = [3, 9, 15]
                    for row in hoshiIndices {
                        for col in hoshiIndices {
                            let x = margin + CGFloat(col) * step
                            let y = margin + CGFloat(row) * step
                            context.fill(Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)), with: .color(.black))
                        }
                    }
                }

                // Stones
                ForEach(0..<boardSize, id: \.self) { y in
                    ForEach(0..<boardSize, id: \.self) { x in
                        let stone = boardState[y][x]
                        if stone != .empty {
                            StoneView(stone: stone, radius: step * 0.47)
                                .position(x: margin + CGFloat(x) * step, y: margin + CGFloat(y) * step)
                        }
                    }
                }

                // Last move marker
                if let (lx, ly) = lastMove {
                    Circle()
                        .stroke(Color.red, lineWidth: 2)
                        .frame(width: step * 0.5, height: step * 0.5)
                        .position(x: margin + CGFloat(lx) * step, y: margin + CGFloat(ly) * step)
                }

                // Gesture overlay
                Color.white.opacity(0.001)
                    .onTapGesture { location in
                        let x = Int(((location.x - margin) / step).rounded())
                        let y = Int(((location.y - margin) / step).rounded())
                        if x >= 0 && x < boardSize && y >= 0 && y < boardSize {
                            onMoveTapped(x, y)
                        }
                    }
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
            .fill(stone == .black ? Color.black : Color.white)
            .frame(width: radius * 2, height: radius * 2)
            .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 1)
    }
}
