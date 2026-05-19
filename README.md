# Weiqi iOS

A native iOS Go (Weiqi) application powered by the KataGo engine. Migrated from the original Android implementation.

## Features
- **Interactive Go Board**: Custom-drawn 19x19 board with stone placement and move markers.
- **KataGo Integration**: Built-in AI using the high-performance KataGo engine via C++ interop.
- **Game Modes**:
  - **You are Black**: Play against the AI.
  - **You are White**: AI plays first.
  - **Human vs Human**: Local multiplayer.
  - **AI vs AI**: Watch the engine play against itself.
- **Modern UI**: Built with SwiftUI for a smooth, native iOS experience.

## Performance Optimization (CRITICAL)

### 1. Build in Release Mode
The engine uses the **Eigen (CPU)** backend. To achieve playable speeds (1-3 seconds per move), you **MUST** run the app in **Release** mode.
- In Xcode, go to **Product > Scheme > Edit Scheme...**
- Select **Run** on the left.
- Change **Build Configuration** from `Debug` to **`Release`**.

### 2. Search Depth
The search is currently limited to **100 visits** in `ios/Weiqi/Assets/gtp.cfg`. This provides a strong level of play while ensuring fast response times on mobile hardware.

## Development & Build Instructions

### Prerequisites
- **Xcode** 15.0+
- **XcodeGen**: Install via Homebrew: `brew install xcodegen`

### Getting Started
1. Navigate to the `ios` folder:
   ```bash
   cd ios
   ```
2. Generate the Xcode project:
   ```bash
   xcodegen
   ```
3. Open the project:
   ```bash
   open Weiqi.xcodeproj
   ```

## Architecture
- **UI Layer**: SwiftUI (`ios/Weiqi/Views/`)
- **Bridge Layer**: Objective-C++ Wrapper (`ios/Weiqi/KataGoWrapper.mm`)
- **Engine Layer**: KataGo C++ Source (`weiqi/third_party/katago/cpp/`)
- **Backend**: Eigen (CPU) for maximum compatibility and stability on iOS.

## Troubleshooting

### "AI is thinking..." stays forever
- Ensure you are in **Release** mode. In Debug mode, the engine can be 100x slower.
- If it still hangs, check the Xcode console. The engine might be stuck during model loading (though internal logs are silenced, critical errors may still appear).

### Updating the Model
To use a different KataGo model:
1. Replace `ios/Weiqi/Assets/model.bin.gz` with your new model.
2. Run `xcodegen` again if you renamed the file.
3. Update the filename in `GameView.swift` if necessary.

## Credits
- **KataGo**: [lightvector/KataGo](https://github.com/lightvector/KataGo)
- **Eigen**: C++ library for linear algebra.
