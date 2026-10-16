import XCTest
@testable import OneLogic

/// NL-capture eval. Prints accuracy per split; fails if a split drops below its ratchet.
/// Raise the ratchet after a round that improves it; never lower it.
final class CaptureEvalTests: XCTestCase {
    static let ratchet = ["train": 44, "test": 22]

    struct Case: Decodable {
        let split: String
        let input: String
        let title: String
        let day: Int
        let hasDay: Bool
        let hour: Int?
        let minute: Int?
        let `repeat`: String?
        let kind: String?
        let duration: Int?
    }

    struct Suite: Decodable {
        let now: String
        let timeZone: String
        let cases: [Case]
    }

    func testCaptureEval() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "capture-cases", withExtension: "json"))
        let suite = try JSONDecoder().decode(Suite.self, from: Data(contentsOf: url))

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: suite.timeZone))
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.timeZone = cal.timeZone
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let now = try XCTUnwrap(fmt.date(from: suite.now))
        let today = cal.startOfDay(for: now)

        var passed: [String: Int] = [:]
        var total: [String: Int] = [:]
        var trainFailures: [String] = []

        for c in suite.cases {
            let got = CaptureParser.parse(c.input, now: now, calendar: cal)
            let gotDay = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: got.day)).day ?? -99
            var problems: [String] = []
            if got.title != c.title { problems.append("title '\(got.title)'≠'\(c.title)'") }
            if gotDay != c.day { problems.append("day \(gotDay)≠\(c.day)") }
            if got.hasDay != c.hasDay { problems.append("hasDay \(got.hasDay)≠\(c.hasDay)") }
            if got.hour != c.hour { problems.append("hour \(String(describing: got.hour))≠\(String(describing: c.hour))") }
            if c.hour != nil, got.minute != (c.minute ?? 0) { problems.append("minute \(got.minute)≠\(c.minute ?? 0)") }
            if let kind = c.kind, got.kind.rawValue != kind { problems.append("kind \(got.kind.rawValue)≠\(kind)") }
            if let duration = c.duration, got.durationMinutes != duration {
                problems.append("duration \(String(describing: got.durationMinutes))≠\(duration)")
            }
            if got.repeatRule != c.repeat { problems.append("repeat \(String(describing: got.repeatRule))≠\(String(describing: c.repeat))") }

            total[c.split, default: 0] += 1
            if problems.isEmpty {
                passed[c.split, default: 0] += 1
            } else if c.split == "train" {
                trainFailures.append("  ✗ \(c.input): " + problems.joined(separator: ", "))
            }
        }

        for split in ["train", "test"] {
            print("CAPTURE \(split): \(passed[split, default: 0])/\(total[split, default: 0])")
        }
        if !trainFailures.isEmpty { print("Train failures:\n" + trainFailures.joined(separator: "\n")) }

        for (split, floor) in Self.ratchet {
            XCTAssertGreaterThanOrEqual(passed[split, default: 0], floor, "\(split) dropped below ratchet")
        }
    }
}
