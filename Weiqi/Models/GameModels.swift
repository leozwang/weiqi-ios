import Foundation

enum Stone: Int {
    case empty = 0
    case black = 1
    case white = 2
}

enum GameMode: String, CaseIterable, Codable {
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

struct GameSettings: Codable {
    var mode: GameMode = .userBlack
    var handicap: Int = 0
    var visits: Int = 500
    var modelName: String = "model.bin.gz"
}

extension GameSettings {
    static let userDefaultsKey = "com.cwave.weiqi.game_settings"
    
    static func load() -> GameSettings {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let settings = try? JSONDecoder().decode(GameSettings.self, from: data) {
            return settings
        }
        return GameSettings()
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }
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

struct PersistedMove: Codable {
    let x: Int
    let y: Int
    let isPass: Bool
    let stone: Int
}

extension PersistedMove {
    static let userDefaultsKey = "com.cwave.weiqi.persisted_moves"
    
    static func loadAll() -> [PersistedMove] {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let moves = try? JSONDecoder().decode([PersistedMove].self, from: data) {
            return moves
        }
        return []
    }
    
    static func saveAll(_ moves: [PersistedMove]) {
        if let data = try? JSONEncoder().encode(moves) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
    
    static func clear() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}
