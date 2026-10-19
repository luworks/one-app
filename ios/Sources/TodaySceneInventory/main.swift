import Foundation
import TodayScenes

// Export the actual typed registry; clients provide conservative repository source dependencies.
struct Inputs: Decodable {
    let sources: [String]
    let locks: [String]
}
struct Manifest: Encodable {
    let schema = 1
    let locks: [String]
    let scenes: [Entry]
    struct Entry: Encodable {
        let id: String
        let scenarios: [String]
        let sources: [String]
    }
}

do {
    guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--sources-json" else {
        throw CocoaError(.fileReadInvalidFileName)
    }
    let inputs = try JSONDecoder().decode(Inputs.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
    let manifest = Manifest(locks: inputs.locks, scenes: SceneRegistry.all.map {
        Manifest.Entry(id: $0.id.rawValue, scenarios: $0.scenarios.map(\.rawValue).sorted(), sources: inputs.sources)
    })
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(manifest))
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    FileHandle.standardError.write(Data("today-scenes: invalid registry export input\n".utf8))
    exit(2)
}
