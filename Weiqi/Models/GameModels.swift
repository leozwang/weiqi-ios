import Foundation

enum Stone: Int {
    case empty = 0
    case black = 1
    case white = 2
}

enum GameMode: String, CaseIterable, Codable {
    case userBlack = "I'm Black"
    case userWhite = "I'm White"
    case userBoth = "Two Players"
    case aiBoth = "AI vs AI"
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "I'm Black", "You are Black", "You're Black":
            self = .userBlack
        case "I'm White", "You are White", "You're White", "You're white":
            self = .userWhite
        case "Two Players":
            self = .userBoth
        case "AI vs AI":
            self = .aiBoth
        default:
            self = GameMode(rawValue: raw) ?? .userBlack
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    
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

struct CandidateMove: Identifiable {
    var id: String { "\(x),\(y)" }
    let x: Int
    let y: Int
    let winrate: Double
    let visits: Int
    var scoreLead: Double = 0.0
    var order: Int = 1
    
    var gtpCoord: String {
        let letters = "ABCDEFGHJKLMNOPQRST"
        guard x >= 0 && x < letters.count else { return "" }
        return "\(Array(letters)[x])\(19 - y)"
    }
    
    static func fromGtpCoord(_ coord: String) -> (Int, Int)? {
        let coord = coord.uppercased()
        guard coord.count >= 2, coord != "PASS" else { return nil }
        let letters = "ABCDEFGHJKLMNOPQRST"
        guard let firstChar = coord.first, let col = letters.firstIndex(of: firstChar) else { return nil }
        guard let rowNum = Int(coord.dropFirst()) else { return nil }
        let x = letters.distance(from: letters.startIndex, to: col)
        let y = 19 - rowNum
        guard x >= 0 && x < 19 && y >= 0 && y < 19 else { return nil }
        return (x, y)
    }
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
