import Foundation

enum Stone: Int {
    case empty = 0
    case black = 1
    case white = 2
}

enum GameMode: String, CaseIterable {
    case userBlack = "You are Black"
    case userWhite = "You are White"
    case userBoth = "Two Players"
    case aiBoth = "AI vs AI"
    
    var description: String {
        switch self {
        case .userBlack: return "Human vs AI"
        case .userWhite: return "AI vs Human"
        case .userBoth: return "Local Multiplayer"
        case .aiBoth: return "Self-play"
        }
    }
}

struct GameSettings {
    var mode: GameMode = .userBlack
    var handicap: Int = 0
    var visits: Int = 1000
    var modelName: String = "model.bin.gz"
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
