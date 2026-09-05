import Foundation
import AVFoundation
import UIKit

@MainActor
final class SoundManager: ObservableObject {
    static let shared = SoundManager()
    
    private let soundEnabledKey = "isSoundEnabled"
    private let hapticEnabledKey = "isHapticEnabled"
    
    @Published var isSoundEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isSoundEnabled, forKey: soundEnabledKey)
        }
    }
    
    @Published var isHapticEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isHapticEnabled, forKey: hapticEnabledKey)
        }
    }
    
    // Multiple AVAudioPlayers per sound file to allow overlapping playback without cutting off resonance
    private var players: [AVAudioPlayer] = []
    private var currentIndex = 0
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    private init() {
        if UserDefaults.standard.object(forKey: soundEnabledKey) == nil {
            self.isSoundEnabled = true
        } else {
            self.isSoundEnabled = UserDefaults.standard.bool(forKey: soundEnabledKey)
        }
        
        if UserDefaults.standard.object(forKey: hapticEnabledKey) == nil {
            self.isHapticEnabled = true
        } else {
            self.isHapticEnabled = UserDefaults.standard.bool(forKey: hapticEnabledKey)
        }
        
        setupAudioSession()
        preloadSounds()
        hapticGenerator.prepare()
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("SoundManager: Failed to configure AVAudioSession: \(error)")
        }
    }
    
    private func preloadSounds() {
        var loadedPlayers: [AVAudioPlayer] = []
        
        // Load stone variations (stone1.wav through stone5.wav)
        for i in 1...5 {
            if let url = Bundle.main.url(forResource: "stone\(i)", withExtension: "wav") {
                // Create 2 players per sound for natural overlap
                for _ in 0..<2 {
                    if let player = try? AVAudioPlayer(contentsOf: url) {
                        player.prepareToPlay()
                        player.volume = 1.0
                        loadedPlayers.append(player)
                    }
                }
            }
        }
        
        // Fallback to "stone.wav" if numbered ones aren't found
        if loadedPlayers.isEmpty, let url = Bundle.main.url(forResource: "stone", withExtension: "wav") {
            for _ in 0..<3 {
                if let player = try? AVAudioPlayer(contentsOf: url) {
                    player.prepareToPlay()
                    player.volume = 1.0
                    loadedPlayers.append(player)
                }
            }
        }
        
        // Shuffle the pool initially so the first moves get random natural variations
        self.players = loadedPlayers.shuffled()
    }
    
    /// Plays the authentic Go stone placement sound and optionally triggers subtle haptic feedback
    func playStoneSound(withHaptic: Bool = false) {
        if withHaptic && isHapticEnabled {
            hapticGenerator.impactOccurred()
        }
        
        guard isSoundEnabled, !players.isEmpty else { return }
        
        // Find an idle player or pick the next one in round-robin fashion
        var selectedPlayer: AVAudioPlayer?
        for player in players {
            if !player.isPlaying {
                selectedPlayer = player
                break
            }
        }
        
        if selectedPlayer == nil {
            selectedPlayer = players[currentIndex % players.count]
            currentIndex = (currentIndex + 1) % players.count
        }
        
        if let player = selectedPlayer {
            player.currentTime = 0
            player.play()
        }
    }
}
