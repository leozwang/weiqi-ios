# iOS coverage of the Android release test plan

The Android app (`weiqi`) has the same game rules. Its release test plan,
[`doc/test_plan.md`](../weiqi/doc/test_plan.md), lists cases T1–T19, U1, M1–M5 and P1–P10. This page maps
each case to the iOS test that covers it. The reverse direction is in the Android repo:
[`doc/ios_test_mapping.md`](../weiqi/doc/ios_test_mapping.md).

How the iOS tests check the same things:
- **Engine log → engine status.** Android reads the engine log (`adb logcat`). In Debug builds, the iOS app
  shows an invisible engine status that UI tests read. It reports the search limit, komi, handicap, the
  moves replayed at load, the app's memory footprint, and how many out-of-turn requests the engine refused.
- **Board.** Both read stones from screenshots.
- **Engine-only checks.** `WeiqiTests` send GTP commands to the real engine for checks that would need hundreds
  of taps. Examples: the exact score of a 357-stone game, and the visits of each level.
- **Two runs.** Every test runs in both test-plan configurations: **Free** (premium off) and **Premium**
  (premium on). See [TESTING.md](TESTING.md).

Status values:
- **Covered**: an iOS test checks the same behavior.
- **Covered (iOS form)**: the same behavior, checked the way iOS or the App Store works. The note says how.
- **Manual**: covered by the iOS manual checklist only ([TESTING.md §5](TESTING.md#5-manual-checklist)).
- **N/A**: specific to Android.

## Pre-release checks

| Android | iOS | Status |
|---|---|---|
| 1. Version bumped in all places | The version lives only in `project.yml`. `scripts/run_tests.sh` checks that the built Release app has that version | Covered |
| 2. No local debug overrides (premium bypass) | The test hooks (purchase pin, reset, engine status) are `#if DEBUG`. The script fails if the Release binary contains them | Covered |
| 3. Build, install and launch the release build; confirm the version | The script builds Release for devices. Manual checklist 1: launch the Release build; Settings shows the version | Covered + Manual |

## Test cases

| Android | iOS tests | Status |
|---|---|---|
| T1 First-run GPU tuning | `GameFlowUITests.testFirstLaunchDefaults` (first launch, no saved data). The script uninstalls before each run, so every run starts from a clean install | N/A for tuning: the Metal backend has no OpenCL tuning step |
| T2 Normal start and update | Every UI test launches the app and waits for the engine (`waitForEngineReady`, 90 s limit). iOS reads `gtp.cfg` from the app bundle at every launch, so an update always uses the new config | Covered; re-extraction is N/A |
| T3 Difficulty | `GameFlowUITests.testEveryLevelAppliesToTheEngine` (each level picked in New Game reaches the engine: 100 / 500, plus 1000 / 2500 in Premium). Also `EngineTests.testEveryDifficultyLevelReachesTheEngine` | Covered |
| T4 Handicap | `BoardUITests.testEveryHandicapLevelOnTheBoard` (None and 1–9: stones read from the screen, komi 7.5/0.5, who moves first, Undo off). Also `EngineTests.testEveryHandicapLevelPlacesTheStandardStones`, `GameplayUITests.testHandicapBoundaries` (who-gets-the-stones line), `testHandicapAsBlackKataGoOpensAndUndo` | Covered |
| T5 Play as | `GameplayUITests.testEveryPlayAsMode`, `testPlayAsWithHandicap`, `testHandicapAsWhiteIMoveFirst`, `testHandicapAsBlackKataGoOpensAndUndo`, `testAIvsAINewGameAvailableAndNoStaleMoves`. The turn-order audit (T19) proves the AI only plays its own color | Covered. iOS AI vs AI has no PAUSE/STEP (by design) |
| T6 Moves | `BoardUITests.testPlacingStonesAndCoordinates` (stone where tapped, occupied point not selectable). `GameplayUITests.testPlayAsBlackUndoReturnsToMyTurn` (KataGo replies with one White stone). `testProGameWhenPurchased` (Pass and PLACE off while KataGo thinks) | Covered. NEW GAME stays enabled while KataGo thinks (iOS decision) |
| T7 Pass and game end | `GameFlowUITests.testPassAgainstKataGo` (KataGo answers a pass). `GameplayUITests.testGameOverUndoAndRelaunch`: two passes end the game, "Counting score…" shows, the result ends in .5. BACK TO BOARD keeps "Game Over" and the result on a locked board, and NEW GAME works. `testPlayAsWithHandicap` (both colors can pass) | Covered. The game end uses Two Players: KataGo does not pass back while it can still gain points. Territory display: Manual (M3) |
| T8 Undo and redo | `GameFlowUITests.testUndoTakesBackAPass` (with a pass in the record). `GameplayUITests.testPlayAsBlackUndoReturnsToMyTurn`, `testPlayAsWhiteKataGoOpensAndUndo`, `testTwoPlayersUndoIsOneMove`, `testHandicapAsBlackKataGoOpensAndUndo` | Covered |
| T9 Cancel | `GameFlowUITests.testCancelNewGameKeepsTheGame`: change level, side and handicap, then Cancel. Swiping the sheet down does the same. The game, side and level stay, and play goes on | Covered |
| T10 Save and restore | `GameFlowUITests.testRelaunchMidGameAndWhileKataGoThinks`: relaunch after a pass; then close the app while KataGo thinks. KataGo moves right after the relaunch. The engine status shows how many moves were replayed | Covered |
| T11 Analysis | `AnalysisUITests.testAnalysisRecommendationsAndPlace`: winrate, score lead and candidates appear and refresh. Tapping a candidate previews it, PLACE plays it, and turning analysis off restores the status line | Covered. Territory dots: Manual (M3) |
| T12 Stability and memory | `GameFlowUITests.testLongSelfPlayStaysStable`: 30 self-play moves (Pro in Premium, Amateur in Free). No crash; memory grows by less than 150 MB between moves 10 and 30; NEW GAME works afterwards | Covered on the simulator; Manual on a device (checklist 9) |
| T13 Search budget | `EngineTests.testDifficultyLevelControlsSearchBudget`: all four levels, openings Q16 and D4. The search stops at the budget, the chosen move never gets more visits than the budget, and each level searches over 1.5× more than the level below | Covered (iOS form): checked at engine level, so Free runs it for all four levels too |
| T14 Rules and coordinates | `BoardUITests.testPlacingStonesAndCoordinates` (A19, J10, T1), `testIllegalMovesAreRefusedOnTheBoard` (ko retake and multi-stone suicide show "Illegal move"; retake after a threat works). Also `EngineTests` ko/suicide and `ModelTests.testBoardCoordinates` | Covered |
| T15 Exact score | `EngineTests.testScoreEvenGameMatchesExactAreaCount` (`B+11.5`), `testScoreHandicapGameIncludesChineseCompensation` (`B+16.5`), `testUndoAtGameOverThenPassGivesTheSameScore`. Komi is unchanged after scoring | Covered (iOS form): the same 357-stone game, sent to the engine instead of tapped. The UI part of "Undo at game over, pass again: same result" is in `testGameOverUndoAndRelaunch` |
| T16 Game over and relaunch | `GameplayUITests.testGameOverUndoAndRelaunch` (same result after relaunch, no dialog, no re-scoring, Undo resumes). Also `ModelTests.testFinishedGameResultRoundTrip` | Covered |
| T17 Settings | `GameFlowUITests.testFirstLaunchDefaults`, `testSettingsSurviveRelaunch` (I'm White + 3 stones, Two Players + 9 stones, AI vs AI; Advanced/Pro in Premium). Also `ModelTests` (every combination saved and loaded) | Covered. On iOS the first launch starts a game with the defaults right away instead of opening New Game |
| T18 Languages | `LocalizationUITests.testJapanese`, `testSimplifiedChinese`: New Game sheet, handicap line, status line, Game Over dialog; no English left | Covered |
| T19 Turn order | `WeiqiUITestCase.tearDownWithError`: after every UI test the engine's refusal count must be 0. Also `EngineTests.testOutOfTurnRequestsKeepHistory` | Covered |
| U1 Update from the previous release | Build the previous release, install it on a simulator, start a handicap game and play a move. Then install the new build over it (`xcrun simctl install` keeps the data) and launch. `ModelTests.testLegacyPlayAsTitlesStillLoad` covers old settings | Manual (optional, as on Android): checklist 10 |

## Manual checks

| Android | iOS |
|---|---|
| M1 Turn indicator and progress bar | Manual checklist 2 (turn ring and thinking spinner) |
| M2 AI pass and illegal move | "Illegal move" is automated (`BoardUITests.testIllegalMovesAreRefusedOnTheBoard`). KataGo's pass message: manual checklist 6 |
| M3 Result display | Manual checklist 6 |
| M4 Sound | Manual checklist 7 (sound and haptics toggles) |
| M5 Languages, visual | `LocalizationUITests` attaches screenshots (`t18_*`) to the result bundle; look through them (manual checklist 8) |

## Premium and payment

iOS tests the purchase flows against a local StoreKit test session (`StoreTests`), which Google Play has no
equivalent for. The real App Store sandbox is a manual check.

| Android | iOS tests | Status |
|---|---|---|
| P1 Locked state | `GameplayUITests.testPaymentGatesAdvancedAndProLevels` (Free: banner, locks, paywall), `GameFlowUITests.testEveryLevelAppliesToTheEngine` (Free: Easy and Amateur apply), `StoreTests.testLevelsAreLockedWithoutPurchase` | Covered |
| P2 Purchase sheet opens | Free paywall shows the price button (`testPaymentGatesAdvancedAndProLevels`); the product loads with its price (`StoreTests.testProductIsConfiguredAsNonConsumable`). Opening the sheet: manual checklist 4 | Covered + Manual |
| P3 Cancel purchase | Manual checklist 4 (cancelling changes nothing). `testEveryLevelAppliesToTheEngine` (Free): a locked level picked and cancelled never reaches the engine | Covered + Manual |
| P4 Billing offline | `StoreTests.testOfflineStoreKeepsLevelsLockedAndCanRetry` (no product offline, stays locked, "Load Store Info" retry works) | Covered |
| P5 Successful purchase | `StoreTests.testPurchaseUnlocksLevels`; sandbox purchase: manual checklist 4 | Covered + Manual |
| P6 Declined payment | `StoreTests.testFailedPurchaseShowsErrorAndStaysLocked` | Covered |
| P7 Pending payment | `StoreTests.testAskToBuyStaysLockedUntilApproved` | Covered |
| P8 Purchase restored | `StoreTests.testPurchaseIsRememberedAtNextLaunch`, `testRestorePurchases`; reinstall: manual checklist 5 | Covered + Manual |
| P9 Refund and revoke | `StoreTests.testRefundLocksLevelsAgain` | Covered |
| P10 Premium unlocked | Premium configuration: `testPaymentGatesAdvancedAndProLevels`, `testEveryLevelAppliesToTheEngine` (all four levels), `testProGameWhenPurchased`, `testSettingsSurviveRelaunch` (Advanced, Pro) | Covered |

## Remaining differences (by decision)

- The first launch starts a game with the default settings (Android opens New Game).
- NEW GAME stays enabled while KataGo thinks, also in AI vs AI. AI vs AI has no PAUSE or STEP.
- iOS has Settings (version, sound and haptics toggles) and a Restore Purchases button.
