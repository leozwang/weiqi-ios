# Weiqi — Test Guide

> **Rule:** run the full test suite before every release. Only release when `scripts/run_tests.sh`
> ends with `ALL PASSED` **and** the [manual checklist](#5-manual-checklist) is done.

The suite covers every case of the Android app's release test plan; the case-by-case mapping is in
[android_test_mapping.md](android_test_mapping.md).

---

## 1. Quick start

**Prerequisites:** Xcode 27 (last verified), XcodeGen (`brew install xcodegen`), and the iOS 26.2 simulators
**iPhone 17** and **iPad mini (A17 Pro)**.

```bash
scripts/run_tests.sh
```

Expected end of the output:

```text
==> Testing on iPhone 17 (iOS 26.2), test plan configuration Free
  PASS: iPhone 17, Free
==> Testing on iPhone 17 (iOS 26.2), test plan configuration Premium
  PASS: iPhone 17, Premium
==> Testing on iPad mini (A17 Pro) (iOS 26.2), test plan configuration Free
  PASS: iPad mini (A17 Pro), Free
==> Testing on iPad mini (A17 Pro) (iOS 26.2), test plan configuration Premium
  PASS: iPad mini (A17 Pro), Premium
==> Release build for generic iOS devices
  PASS: Release device build
  PASS: Release version 1.15 (16) (project.yml)
  PASS: no Debug test hooks in the Release binary
==> ALL PASSED
```

It takes about **75 minutes**. KataGo really plays the moves in the UI tests.

| Option | Example |
|---|---|
| Other simulators | `scripts/run_tests.sh "iPhone 17 Pro" "iPad Air 11-inch (M3)"` |
| Other simulator iOS version | `OS=26.0 scripts/run_tests.sh` |
| One configuration only | `CONFIG=Premium scripts/run_tests.sh` (or `Free`) |
| Skip the device build | `SKIP_DEVICE_BUILD=1 scripts/run_tests.sh` |

Logs and result bundles go to `build/TestResults/` (git-ignored). Open a `*.xcresult` in Xcode to see failures
and the attached screenshots.

### What the script does
1. `xcodegen generate` (so new test files are part of the project).
2. For each simulator:
   1. Boot it and wait for the boot to finish.
   2. For each test-plan configuration (**Free**, then **Premium**):
      1. Uninstall the app, so every run starts as a new user from a clean install.
      2. Run all tests.
3. Build the **Release** configuration for generic iOS devices (what App Store archives use). Then check the
   built app:
   - its version matches `project.yml`;
   - the Debug-only test hooks are not in the binary.
4. Print PASS/FAIL per run and exit non-zero on any failure.

---

## 2. Test plan: `Weiqi.xctestplan`

The **Weiqi** scheme runs every test in two configurations:

| Configuration | Payment state | Proves |
|---|---|---|
| **Free** | "Unlock Elite Levels" **not** bought (`WEIQI_PAYMENT=disabled`) | The app works for free users; Advanced/Pro show the paywall |
| **Premium** | "Unlock Elite Levels" bought (`WEIQI_PAYMENT=enabled`) | The app works for paying users; Advanced/Pro start, and the Pro paths (Pro game, Pro self-play, Pro saved settings) are tested |

**Per run:** 54 tests (27 in `WeiqiTests`, 27 in `WeiqiUITests`). In **Free**, `testProGameWhenPurchased` is
skipped by design (Pro is locked). Full suite: 4 runs = 216 test executions, plus the Release build checks.

### Debug-only test hooks

UI tests can't read the engine log the way the Android tests read `adb logcat`. Debug builds therefore offer
these hooks. All of them are `#if DEBUG`, and the script fails if the Release binary contains them.

| Hook | What it does |
|---|---|
| `WEIQI_UITEST_PURCHASED=0/1` (launch environment) | Pins the purchase state (`StoreManager`). The UI tests set it from the configuration. The real StoreKit flow is tested by `StoreTests` |
| `WEIQI_UITEST_RESET=1` (launch environment) | Starts like a first launch: no saved settings, game or result |
| Engine status (invisible text, identifier `engineStatus`) | `visits=500 komi=7.5 handicap=0 restored=0 mem=160 refused=0`. In order: the engine's search limit, komi and handicap; the moves replayed when the game was loaded; the app's memory footprint in MB; and how many out-of-turn requests the engine refused |

The engine also answers `get_turn_refusals` and `get_last_search_visits`, which `EngineTests` use.

---

## 3. Test inventory

### `WeiqiTests` — hosted in the app, real KataGo engine and StoreKit

**EngineTests (12)**: real engine with the bundled model, `gtp.cfg` and Metal backend.

| Test | Checks |
|---|---|
| `testHostAppStaysIdleDuringEngineTests` | The app skips its own engine start-up while hosting the tests |
| `testEveryDifficultyLevelReachesTheEngine` | Easy 100 / Amateur 500 / Advanced 1000 / Pro 2500 visits become the engine's limits |
| `testDifficultyLevelControlsSearchBudget` | All four levels, openings Q16 and D4: the search uses the level's whole budget and stops there (give or take the playouts its 4 threads already started); the chosen move never gets more than the budget; each level searches over 1.5× more than the one below |
| `testEveryHandicapLevelPlacesTheStandardStones` | Handicap 1–9: standard star points, White moves first, komi 0.5, stones stay |
| `testHandicapSetupSurvivesUndo` | Undo never removes handicap stones; cannot undo past the setup |
| `testScoreEvenGameMatchesExactAreaCount` | A finished game with a known area count scores exactly `B+11.5` (7.5 komi); komi unchanged |
| `testScoreHandicapGameIncludesChineseCompensation` | Same board from a 2-stone game scores exactly `B+16.5` (0.5 komi, White +1 per handicap stone) |
| `testUndoAtGameOverThenPassGivesTheSameScore` | Undo of the last pass at game over, then passing again, gives the same `B+11.5` |
| `testFinalScoreIsRoundedAndKeepsKomi` | Results end in .5 with half-point komi; scoring never changes the game's komi |
| `testMultiStoneSuicideIsIllegal` | Chinese rules: multi-stone suicide is refused |
| `testImmediateKoRecaptureIsIllegal` | Immediate ko recapture is refused; a ko threat elsewhere is allowed |
| `testOutOfTurnRequestsKeepHistory` | Out-of-turn moves are refused and counted, without losing the game record |

**StoreTests (9)**: the app's `StoreManager` against Apple's local StoreKit test environment
(`SKTestSession` with `Weiqi/Products.storekit`).

| Test | Checks |
|---|---|
| `testProductIsConfiguredAsNonConsumable` | `com.cwave.weiqi.unlock_levels` loads: non-consumable, name, price |
| `testLevelsAreLockedWithoutPurchase` | Locked by default |
| `testPurchaseUnlocksLevels` | Buying unlocks Advanced/Pro, no error |
| `testPurchaseIsRememberedAtNextLaunch` | A relaunched app finds the purchase by itself |
| `testRefundLocksLevelsAgain` | A refund locks Advanced/Pro again |
| `testRestorePurchases` | Restore Purchases unlocks a previous purchase |
| `testAskToBuyStaysLockedUntilApproved` | Ask to Buy stays locked while pending and unlocks when approved |
| `testFailedPurchaseShowsErrorAndStaysLocked` | A failed purchase shows an error and stays locked |
| `testOfflineStoreKeepsLevelsLockedAndCanRetry` | Offline: no product, nothing can be bought, stays locked; "Load Store Info" works once online |

**ModelTests (6)**: settings and saved-game persistence.

| Test | Checks |
|---|---|
| `testDefaultSettingsForFirstLaunch` | First launch: I'm Black, no handicap, Amateur |
| `testSettingsRoundTripForEveryModeHandicapAndLevel` | Every mode × handicap × level is saved and loaded |
| `testLegacyPlayAsTitlesStillLoad` | Settings saved by older versions still load |
| `testGameRecordRoundTrip` | Saved moves (including passes) round-trip; clearing works |
| `testFinishedGameResultRoundTrip` | The result of a finished game is saved with its move count |
| `testBoardCoordinates` | GTP coordinates (no column I, rows from the bottom) |

### `WeiqiUITests` — end to end, tapping the app like a user

All UI tests share `WeiqiUITestCase`. After every test it checks that the engine refused no out-of-turn
request. This is the turn-order audit: the app never asked the engine to move for the wrong color.

**GameplayUITests (13)**

| Test | Checks |
|---|---|
| `testEveryPlayAsMode` | All 4 modes: player names, who moves first, KataGo moves only on its turns, self-play continues, Pass/Undo/Redo availability |
| `testPlayAsWithHandicap` | Two Players with handicap: White first, nobody moves by itself, both colors pass. AI vs AI with handicap keeps playing |
| `testPlayAsBlackUndoReturnsToMyTurn` | My stone where tapped and one White reply; Undo takes back both; Redo puts the same stones back |
| `testPlayAsWhiteKataGoOpensAndUndo` | KataGo (Black) opens; Undo returns to your turn |
| `testTwoPlayersUndoIsOneMove` | Two Players: Undo/Redo is one move |
| `testAIvsAINewGameAvailableAndNoStaleMoves` | AI vs AI: NEW GAME always enabled; no old moves leak into the new game |
| `testHandicapAsBlackKataGoOpensAndUndo` | 2 stones as Black: KataGo opens; Undo disabled until you move; handicap stones stay |
| `testHandicapAsWhiteIMoveFirst` | 3 stones as White: you move first |
| `testHandicapBoundaries` | Stepper limits 0…9, the "who receives the stones" footer, 9-stone and 1-stone games |
| `testCaptureHandicapScreens` | Screenshots of the New Game sheet and a handicap game (attached to the result bundle) |
| `testPaymentGatesAdvancedAndProLevels` | Free: banner, lock and paywall (price button + Restore Purchases) instead of START GAME. Premium: no paywall. Both: Easy/Amateur always playable |
| `testProGameWhenPurchased` | Premium only: a Pro game starts and KataGo plays; Pass and PLACE stay off while it thinks |
| `testGameOverUndoAndRelaunch` | Two passes: "Counting score…", an x.5 result, locked board. Relaunch: same result without re-scoring or the dialog. Undo then pass: same result. NEW GAME works |

**BoardUITests (3)**: stones read from screenshots.

| Test | Checks |
|---|---|
| `testEveryHandicapLevelOnTheBoard` | None and 1–9: exactly the standard star points on screen, komi 7.5 / 0.5 in the engine, right side to move, Undo off |
| `testPlacingStonesAndCoordinates` | Taps at A19, J10, T1 put stones exactly there, colors alternate, an occupied point can't be selected |
| `testIllegalMovesAreRefusedOnTheBoard` | Ko retake and multi-stone suicide show "Illegal move" and change nothing; the retake after a ko threat works |

**GameFlowUITests (8)**

| Test | Checks |
|---|---|
| `testFirstLaunchDefaults` | No saved data: a game as Black on Amateur without handicap; New Game shows those choices |
| `testEveryLevelAppliesToTheEngine` | Each playable level picked in New Game reaches the engine (Free: Easy/Amateur; Premium: all four) and stays selected; a locked level never does |
| `testSettingsSurviveRelaunch` | Three mode/level/handicap combinations: after a relaunch the engine, the board and New Game show the saved choices |
| `testCancelNewGameKeepsTheGame` | Cancel (or swiping the sheet down) keeps the game, the side and the level; play goes on |
| `testPassAgainstKataGo` | KataGo answers a pass with a move; passes between moves never end the game |
| `testUndoTakesBackAPass` | Undo takes back my pass with KataGo's reply; KataGo doesn't move by itself; Redo puts both back |
| `testRelaunchMidGameAndWhileKataGoThinks` | Relaunch after a pass restores everything; closing the app while KataGo thinks: it moves right after the relaunch |
| `testLongSelfPlayStaysStable` | 30 self-play moves (Pro in Premium): no crash, memory grows less than 150 MB from move 10 to 30, NEW GAME works |

**AnalysisUITests (1)**

| Test | Checks |
|---|---|
| `testAnalysisRecommendationsAndPlace` | The eye button shows winrate, score lead and ranked candidates; the Guide opens; tapping a candidate previews it and PLACE plays it; candidates refresh; turning it off restores the status line |

**LocalizationUITests (2)**

| Test | Checks |
|---|---|
| `testJapanese`, `testSimplifiedChinese` | New Game sheet, handicap line, status line and Game Over dialog are translated, with no English left. Screenshots are attached for the visual check |

### Coverage by area

| Area | Covered by |
|---|---|
| Play As | `testEveryPlayAsMode`, `testPlayAsWithHandicap`, the Undo tests, `testAIvsAINewGameAvailableAndNoStaleMoves`, the turn-order audit |
| Difficulty | `testEveryLevelAppliesToTheEngine`, `testEveryDifficultyLevelReachesTheEngine`, `testDifficultyLevelControlsSearchBudget`, `testProGameWhenPurchased` |
| Handicap | `testEveryHandicapLevelOnTheBoard`, `testEveryHandicapLevelPlacesTheStandardStones`, `testHandicapSetupSurvivesUndo`, `testHandicapBoundaries`, the two handicap UI tests |
| Score accuracy | `testScoreEvenGameMatchesExactAreaCount`, `testScoreHandicapGameIncludesChineseCompensation`, `testUndoAtGameOverThenPassGivesTheSameScore`, `testFinalScoreIsRoundedAndKeepsKomi`, `testGameOverUndoAndRelaunch` |
| Rules and coordinates | `BoardUITests`, `testMultiStoneSuicideIsIllegal`, `testImmediateKoRecaptureIsIllegal`, `testOutOfTurnRequestsKeepHistory`, `testBoardCoordinates` |
| Pass, Undo / Redo, game end | `testPassAgainstKataGo`, `testUndoTakesBackAPass`, `testPlayAsBlackUndoReturnsToMyTurn`, `testGameOverUndoAndRelaunch` |
| New Game sheet | `testCancelNewGameKeepsTheGame`, `testFirstLaunchDefaults`, `testSettingsSurviveRelaunch` |
| Persistence | `ModelTests`, `testSettingsSurviveRelaunch`, `testRelaunchMidGameAndWhileKataGoThinks`, `testGameOverUndoAndRelaunch` |
| Analysis | `testAnalysisRecommendationsAndPlace` |
| Stability and memory | `testLongSelfPlayStaysStable` |
| Languages | `LocalizationUITests` |
| Payment (Free) | `testPaymentGatesAdvancedAndProLevels` (Free), `testEveryLevelAppliesToTheEngine` (Free), `StoreTests` |
| Premium | `testPaymentGatesAdvancedAndProLevels`, `testEveryLevelAppliesToTheEngine`, `testProGameWhenPurchased`, `testSettingsSurviveRelaunch`, `testLongSelfPlayStaysStable` (all in Premium) |

---

## 4. Running tests yourself

**Xcode:** select the **Weiqi** scheme and an iOS 26.x simulator, then **Product > Test** (⌘U). This runs
Free and Premium; the Test navigator groups results per configuration.

**One test, one configuration:**
```bash
xcodebuild test -project Weiqi.xcodeproj -scheme Weiqi -testPlan Weiqi -only-test-configuration Premium \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -collect-test-diagnostics never \
  -only-testing:WeiqiUITests/GameplayUITests/testProGameWhenPurchased
```
Use `-only-testing:WeiqiTests/StoreTests` for a whole class, or `-only-testing:WeiqiTests` for a target.

### Payment setup (for manual purchase testing)
- **Product:** `com.cwave.weiqi.unlock_levels`, Non-Consumable. It unlocks Advanced (1000 visits) and Pro
  (2500 visits). It must match App Store Connect (see `in_app_purchase_guide.md`).
- **Simulator (⌘R):** the scheme's Run action uses `Weiqi/Products.storekit`, local StoreKit at a test price of
  $1.99. Manage purchases with **Debug > StoreKit > Manage Transactions**.
- **Real device:** archives and TestFlight use the App Store sandbox. Sign in under
  **Settings > App Store > Sandbox Account**.
- **Edit `Products.storekit` only in Xcode's StoreKit editor.** A hand-written file that StoreKit can't decode
  silently loads no product. `testProductIsConfiguredAsNonConsumable` catches that.

---

## 5. Manual checklist

These checks need a person to look or listen. Use a real device when possible, otherwise an iPhone and an iPad
simulator, with the Release build.

1. **Launch:** the splash screen gives way to the board. Settings shows the new version and build number.
2. **Turn indicator:** in all four Play As modes, the turn ring and the thinking spinner follow the side to move.
3. **Free user:** Easy/Amateur start. Advanced/Pro show the lock and paywall. On a device the button shows the
   App Store Connect price.
4. **Buying Premium:**
   - Simulator: **Unlock for $1.99**, then confirm.
   - Device: sandbox account or TestFlight.

   The lock and banner disappear and Advanced/Pro start. Cancelling the purchase sheet changes nothing.
5. **Premium user:**
   - Pro thinks noticeably longer per move.
   - The purchase survives a relaunch.
   - Reinstall, then **Restore Purchases**: it comes back.
   - A refund in Manage Transactions locks again.
6. **Passing and score:**
   - KataGo's pass shows a toast.
   - Two passes show "Counting score…", then a result like `B+3.5` with dead stones and territory marked.
   - The result matches a Chinese count: stones + territory − 7.5 komi (0.5 with handicap, White +1 per
     handicap stone).
7. **Sound and haptics** toggles work: a stone sound for every move.
8. **Languages:** look through the `t18_*` screenshots in the result bundle. Also check the main screen, the
   paywall and the toasts in Japanese and Simplified Chinese. No text may be clipped or overlap.
9. **Memory on a device:** play 30 or more moves on Pro (or AI vs AI) with Xcode's memory gauge open (Debug
   navigator). Memory must level off, not climb with every move.
10. **Update from the previous release** (optional; do it when the saved-game format or the handicap rules
    changed):
    1. Build the previous release from its git tag and install it on a simulator.
    2. Start a handicap game and play a move.
    3. Install the new build over it with `xcrun simctl install` (this keeps the app's data).
    4. Launch: the game comes back unchanged.

---

## 6. Release checklist

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` (never in `Info.plist`), then run
   `xcodegen generate`.
2. Run `scripts/run_tests.sh` and get `ALL PASSED`. That covers Free and Premium on iPhone and iPad, plus the
   Release device build, its version and the absence of test hooks.
3. Do the manual checklist.
4. In Xcode, **Product > Archive** (Release), then upload to App Store Connect.

---

## 7. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| App aborts as soon as KataGo thinks, on the **iOS 27.0 simulator** | Apple's simulator Metal driver asserts in MPSGraph (`MTLSimDevice newHeapWithDescriptor:`). Use an iOS 26.x simulator. Real devices are unaffected |
| "Application failed preflight checks" | The simulator was still booting. The script boots first. Manually: `xcrun simctl boot <udid>` then `xcrun simctl bootstatus <udid> -b` |
| StoreTests fail with "Unable to Complete Request" | StoreKit's test service still points at a replaced app build. The script uninstalls the app before each run. Manually: `xcrun simctl uninstall <udid> com.cwave.weiqi` |
| No product loads in local StoreKit | `Products.storekit` can't be decoded. Look for "Error decoding configuration file" in `xcrun simctl spawn <udid> log show --last 5m --predicate 'process CONTAINS "Octane"'` |
| A new test file doesn't run (0 tests) | Run `xcodegen generate` (the script does this) |
| xcodebuild hangs for ~10 min after the tests | It is collecting diagnostics; pass `-collect-test-diagnostics never` (the script does this) |
| A UI test can't find a row in the New Game sheet on iPad | The row is below the fold; scroll with the `reveal(_:)` helper |
| The first tap after launch does nothing | The splash screen still covers the app while it fades out. `waitForEngineReady()` waits for it |
| `testLongSelfPlayStaysStable` fails on memory | Memory grows with every move. The Metal backend must drain an autorelease pool per evaluation (`MPSGraphModelHandle.apply` in `metalbackend.swift`); without it the app grew about 20 MB per move at Amateur |
| A UI test fails with "Timed out while synthesizing event" during a long run | macOS display/idle sleep froze the simulator mid-test. `scripts/run_tests.sh` runs `caffeinate -dimsu -w $$` automatically |

---

## 8. Adding tests

- **Engine or StoreKit logic:** put the test in `WeiqiTests` (runs inside the app; `@testable import Weiqi` is
  available).
- **User flows:** put it in `WeiqiUITests` as a subclass of `WeiqiUITestCase`, and reuse its helpers:
  - games: `startNewGame`, `play`, `tapPoint`, `waitForState`, `moveNumber`, `turn`, `actionButton`;
  - the board and engine: `boardStones`, `engineStatus`, `waitForEngine`;
  - the New Game sheet: `openNewGameSheet`, `levelButton`, `isModeSelected`, `handicapLabel`, `setHandicap`,
    `reveal`;
  - launches: `relaunch(environment:arguments:)`.
- **Bug fixes:** add a test that fails before the fix and passes after it.
- **New files:** run `xcodegen generate`, then `scripts/run_tests.sh`.

---

## Last full run

**2026-10-26, version 1.15 (16), Xcode 27.0, iOS 26.2 simulators: `ALL PASSED`**

| Run | WeiqiTests | WeiqiUITests |
|---|---|---|
| iPhone 17, Free | 27/27 passed | 26 passed, 1 skipped |
| iPhone 17, Premium | 27/27 passed | 27/27 passed |
| iPad mini (A17 Pro), Free | 27/27 passed | 26 passed, 1 skipped |
| iPad mini (A17 Pro), Premium | 27/27 passed | 27/27 passed |
| Release build for generic iOS devices (version + no Debug hooks) | Passed | |
