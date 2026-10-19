import Foundation

@main
struct SerializationChecks {
    @MainActor
    static func main() throws {
        func expect(_ condition: Bool, _ message: String = "Check failed") { precondition(condition, message) }
        func object(_ report: DiagnosticReport) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: report.data()) as! [String: Any]
        }
        // Real serializer must accept unavailable SDK values and reject invalid numeric data.
        var report = DiagnosticReport()
        report.append([DiagnosticSample(cpuSeconds: .nan, peakMemoryBytes: -.infinity, launchTimeToFirstDraw: [])])
        expect((try object(report)["samples"] as! [Any]).isEmpty)
        expect(DiagnosticSample.LaunchBucket(lowerSeconds: -1, upperSeconds: 1, count: 1) == nil)
        expect(DiagnosticSample.LaunchBucket(lowerSeconds: 1, upperSeconds: 0, count: 1) == nil)
        expect(DiagnosticSample.LaunchBucket(lowerSeconds: 0, upperSeconds: .infinity, count: 1) == nil)
        expect(DiagnosticSample.LaunchBucket(lowerSeconds: 0, upperSeconds: 1, count: 0) == nil)

        let bucket = DiagnosticSample.LaunchBucket(lowerSeconds: 0.2, upperSeconds: 0.4, count: 3)!
        report.append((0..<25).map {
            DiagnosticSample(cpuSeconds: Double($0), peakMemoryBytes: 4_096,
                             launchTimeToFirstDraw: Array(repeating: bucket, count: 100))
        })
        let json = try object(report)
        expect(Set(json.keys) == ["schemaVersion", "samples"])
        let samples = json["samples"] as! [[String: Any]]
        expect(samples.count == 7)
        expect((samples.first!["cpuSeconds"] as! Double) == 18)
        expect((samples.last!["cpuSeconds"] as! Double) == 24)
        expect((samples.last!["peakMemoryBytes"] as! Double) == 4_096)
        let buckets = samples.last!["launchTimeToFirstDraw"] as! [[String: Any]]
        expect(buckets.count == 64)
        expect((buckets[0]["count"] as! Int) == 3)
        expect((buckets[0]["lowerSeconds"] as! Double) == 0.2)
        expect((buckets[0]["upperSeconds"] as! Double) == 0.4)
        // Fail on any new text-bearing field at any nesting level, including SDK metadata.
        func checkNumericTree(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                for child in dictionary.values { checkNumericTree(child) }
            } else if let array = value as? [Any] {
                array.forEach(checkNumericTree)
            } else { expect(value is NSNumber, "Export contains nonnumeric content") }
        }
        checkNumericTree(json)
        expect(try report.data() == report.data())

        // Exercise the public file API without registering or faking a MetricKit callback.
        let diagnostics = LocalDiagnostics()
        let url = try diagnostics.exportURL()
        let exported = try Data(contentsOf: url)
        let empty = try JSONSerialization.jsonObject(with: exported) as! [String: Any]
        expect((empty["samples"] as! [Any]).isEmpty)
        expect(url.isFileURL)
        expect(try diagnostics.exportURL() == url)
        expect(try Data(contentsOf: url) == exported)
        try FileManager.default.removeItem(at: url)
        print("PASS: serialization, invalid numeric rejection, bounded retention, numeric-only schema, explicit local export")
        print("UNVERIFIED: MetricKit delivery, simulator UI, physical device, app integration")
    }
}
