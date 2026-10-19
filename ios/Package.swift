// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TodayModules",
    platforms: [.macOS(.v14), .iOS("27.0")],
    products: [
        .library(name: "TodayCore", targets: ["TodayCore"]),
        .library(name: "TodayShared", targets: ["TodayShared"]),
        .library(name: "TodayData", targets: ["TodayData"]),
        .library(name: "TodayPlatform", targets: ["TodayPlatform"]),
        .library(name: "TodayDesignSystem", targets: ["TodayDesignSystem"]),
        .library(name: "FeatureClock", targets: ["FeatureClock"]),
        .library(name: "FeatureHealth", targets: ["FeatureHealth"]),
        .library(name: "TodayTestSupport", targets: ["TodayTestSupport"]),
    ],
    targets: [
        .target(name: "TodayCore"),
        .target(name: "TodayShared"),
        .target(name: "TodayData", dependencies: ["TodayCore", "TodayShared"],
                linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "TodayPlatform", dependencies: ["TodayCore", "TodayShared"]),
        .target(name: "TodayDesignSystem", dependencies: ["TodayCore"]),
        .target(name: "FeatureClock", dependencies: ["TodayCore", "TodayDesignSystem", "TodayPlatform"],
                path: "Sources/Features/FeatureClock", exclude: ["README.md"]),
        .target(name: "FeatureHealth", dependencies: ["TodayCore", "TodayDesignSystem", "TodayPlatform"],
                path: "Sources/Features/FeatureHealth"),
        .target(name: "TodayTestSupport", dependencies: ["TodayCore", "TodayShared"]),
        .testTarget(name: "TodayTests", dependencies: ["TodayCore", "TodayShared", "TodayData", "TodayTestSupport"],
                    path: "Eval/Tests/OneLogicTests",
                    resources: [.copy("capture-cases.json"), .copy("conversation-journeys.json")]),
    ],
    swiftLanguageModes: [.v6]
)
