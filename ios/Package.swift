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
            sources: ["Capture.swift", "Logic.swift", "ConversationHistory.swift", "Dialogue.swift", "ListGuess.swift", "QuickTime.swift", "ReminderSuggest.swift", "NewReminderDraft.swift"]
        ),
        .testTarget(
            name: "OneLogicTests",
            dependencies: ["OneLogic"],
            path: "Eval/Tests/OneLogicTests",
            resources: [.copy("capture-cases.json")]
        ),
    ]
)
