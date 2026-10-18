// swift-tools-version: 5.10
// Eval harness (run from ios/: `swift test`): compiles the app's pure-logic files for macOS and runs them under `swift test`.
import PackageDescription

let package = Package(
    name: "OneEval",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "OneLogic",
            path: "One",
            sources: ["Capture.swift", "Logic.swift", "ConversationHistory.swift", "Dialogue.swift", "ListGuess.swift", "QuickTime.swift", "ReminderSuggest.swift", "NewReminderDraft.swift", "TimerDial.swift", "Pomodoro.swift", "IntentLogic.swift", "EventMatch.swift", "ClockLogic.swift", "OverdueTidy.swift", "LedgerLogic.swift", "AutonomyPolicy.swift", "HealthLogic.swift", "EveningReview.swift", "EditingLogic.swift", "RowSubtitle.swift", "MessageCopy.swift", "AskSuggestions.swift", "AppearanceLogic.swift", "ActivityEvent.swift", "ActivityStore.swift", "ActivityRecorder.swift", "ActivityLedger.swift", "ActivityEvents.swift", "ActivityExport.swift", "TimerList.swift", "TimerPhrase.swift", "CaptureLeadIn.swift", "CaptureCardState.swift", "CalendarAlarms.swift", "HealthMetrics.swift", "HealthSampleSeries.swift", "PillOrder.swift"]
        ),
        // Code shared by the app and the TodayWidgets extension (the widget snapshot and "next items" logic).
        .target(
            name: "OneShared",
            path: "Shared",
            sources: ["WidgetSnapshot.swift", "NextUpSpeech.swift", "TravelTime.swift", "ShareInbox.swift", "LockScreenNext.swift", "ActivityOutbox.swift"]
        ),
        .testTarget(
            name: "OneLogicTests",
            dependencies: ["OneLogic", "OneShared"],
            path: "Eval/Tests/OneLogicTests",
            resources: [.copy("capture-cases.json")]
        ),
    ]
)
