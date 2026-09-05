# Weiqi iOS

A **fully free** and **completely offline** native iOS Go (Weiqi) application powered by the KataGo engine. Unlike many other Go apps, the engine runs locally on your device, requiring no internet connection and providing unlimited play for free.

## Features
- **Interactive Go Board**: Custom-drawn 19x19 board with stone placement and move markers.
- **KataGo Integration**: Built-in AI using the high-performance KataGo engine via C++ interop.
- **100% Offline**: All AI computations happen on-device. No data usage, no latency, and privacy-focused.
- **Always Free**: No subscriptions or hidden costs. Play as many games as you want.
- **Game Modes**:
  - **I'm Black**: Play against the AI.
  - **I'm White**: AI plays first.
  - **Human vs Human**: Local multiplayer.
  - **AI vs AI**: Watch the engine play against itself.
- **Modern UI**: Built with SwiftUI for a smooth, native iOS experience.

## Performance Optimization (CRITICAL)

### 1. Build in Release Mode
The engine uses the **Metal (GPU)** backend via Apple's Metal Performance Shaders Graph (MPSGraph). To achieve maximum performance, run the app in **Release** mode.
- In Xcode, go to **Product > Scheme > Edit Scheme...**
- Select **Run** on the left.
- Change **Build Configuration** from `Debug` to **`Release`**.

### 2. Search Depth
The search is configured via `Weiqi/Assets/gtp.cfg`. The GPU backend delivers rapid neural evaluations directly on Apple Silicon.

## Development & Build Instructions

### Prerequisites
- **Xcode** 15.0+
- **XcodeGen**: Install via Homebrew: `brew install xcodegen`

### Getting Started
1. Generate the Xcode project:
   ```bash
   xcodegen
   ```
2. Open the project:
   ```bash
   open Weiqi.xcodeproj
   ```

## Architecture
- **UI Layer**: SwiftUI (`Weiqi/Views/`)
- **Bridge Layer**: Objective-C++ Wrapper (`Weiqi/KataGoWrapper.mm`)
- **Engine Layer**: KataGo C++ Source (`Weiqi/external/katago/cpp/`)
- **Backend**: Metal (GPU via Apple MPSGraph) with C++/Swift interoperability.

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
