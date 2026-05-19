import Foundation

enum Stone: Int {
    case empty = 0
    case black = 1
    case white = 2
}

enum GameMode {
    case userBlack, userWhite, userBoth, aiBoth
}

struct CandidateMove {
    let x: Int
    let y: Int
    let winrate: Double
    let visits: Int
}

struct AnalysisResult {
    var winrate: Double = 0.5
    var scoreLead: Double = 0.0
    var ownership: [Double] = Array(repeating: 0.0, count: 361)
    var candidates: [CandidateMove] = []
}
