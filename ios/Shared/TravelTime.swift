import Foundation

// Travel time to an event ("Drive 18 min · Leave by 14:20"), like Apple Calendar's Time to Leave.
// Pure logic only (Foundation): which events get an estimate, cache keys, when to refresh, the leave-by time and the label.
// The MapKit requests live in the app (`One/TravelTimes.swift`); the widget only shows what the app wrote.

/// Where an event takes place: the text of its location, plus the coordinate Apple Calendar keeps when the place was
/// picked from Maps (then no address search is needed).
struct TravelPlace: Hashable, Codable {
    var address: String
    var latitude: Double?
    var longitude: Double?

    init(address: String, latitude: Double? = nil, longitude: Double? = nil) {
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// One cached result. `seconds == nil` records a failed lookup, so it isn't retried before the next refresh.
struct TravelEstimate: Codable, Equatable {
    var seconds: TimeInterval?
    var computedAt: Date
}

enum TravelTime {
    /// Recompute an estimate at most this often (traffic changes; so does where you are).
    static let refreshInterval: TimeInterval = 15 * 60
    /// Under this, you're basically there: no hint.
    static let minimumSeconds: TimeInterval = 60
    /// Over this, the address search most likely found the wrong place (another city): no hint.
    static let maximumSeconds: TimeInterval = 5 * 3600

    /// Locations that are not places you travel to (video calls, links, "Online").
    private static let virtualMarkers = ["://", "zoom.us", "teams.microsoft", "meet.google", "webex.com", "facetime"]
    private static let virtualNames: Set<String> = ["zoom", "microsoft teams", "microsoft teams meeting", "teams", "google meet",
                                                     "meet", "facetime", "online", "virtual", "remote", "webex", "skype", "phone",
                                                     "call", "tbd", "n/a"]

    /// True when `location` names a physical place worth a travel estimate.
    static func isPhysical(_ location: String) -> Bool {
        let text = location.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return false }
        if virtualNames.contains(text) { return false }
        return !virtualMarkers.contains { text.contains($0) }
    }

    /// Only upcoming, timed events today or tomorrow with a physical location get an estimate
    /// (and so any network request at all). An event already under way gets none.
    static func isEligible(start: Date, isAllDay: Bool, location: String, now: Date, calendar: Calendar = .current) -> Bool {
        guard !isAllDay, start > now, isPhysical(location) else { return false }
        let today = calendar.startOfDay(for: now)
        guard let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: today) else { return false }
        return start < dayAfterTomorrow
    }

    /// Cache key: one estimate per event, per day, per address (editing the location starts over).
    /// `eventID` is the Apple Calendar identifier (a repeating event shares it, hence the day).
    static func cacheKey(eventID: String, start: Date, address: String, calendar: Calendar = .current) -> String {
        let d = calendar.dateComponents([.year, .month, .day], from: start)
        let day = String(format: "%04d-%02d-%02d", d.year ?? 0, d.month ?? 0, d.day ?? 0)
        let place = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(eventID)|\(day)|\(place)"
    }

    /// The day part of a cache key, for pruning.
    static func day(ofKey key: String) -> String? {
        let parts = key.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        return parts.count >= 2 ? String(parts[1]) : nil
    }

    /// Ask MapKit again? When nothing is cached, or the cached result (success or failure) is at least 15 minutes old.
    static func needsRefresh(_ cached: TravelEstimate?, now: Date, interval: TimeInterval = refreshInterval) -> Bool {
        guard let cached else { return true }
        return now.timeIntervalSince(cached.computedAt) >= interval
    }

    /// The travel time worth showing, in seconds, or nil (failed lookup, too short, implausibly long).
    static func usable(_ estimate: TravelEstimate?) -> TimeInterval? {
        guard let s = estimate?.seconds, s >= minimumSeconds, s <= maximumSeconds else { return nil }
        return s
    }

    /// When to leave: the event's start minus the travel time, rounded down to a whole minute
    /// (so "Leave by" is never later than needed).
    static func leaveBy(start: Date, travelSeconds: TimeInterval) -> Date {
        let raw = start.addingTimeInterval(-travelSeconds).timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (raw / 60).rounded(.down) * 60)
    }

    /// Travel minutes as shown: rounded up, at least 1.
    static func minutes(_ seconds: TimeInterval) -> Int {
        max(1, Int((seconds / 60).rounded(.up)))
    }

    /// "18 min", "1 h", "1 h 5 min".
    static func durationText(seconds: TimeInterval) -> String {
        let m = minutes(seconds)
        if m < 60 { return "\(m) min" }
        let h = m / 60, r = m % 60
        return r == 0 ? "\(h) h" : "\(h) h \(r) min"
    }

    /// "Leave by 14:20", or "Leave now" once that time has come (until the event starts).
    /// `time` formats the leave-by time (the views pass the user's 12/24-hour format).
    static func leaveText(leaveBy: Date, now: Date, time: (Date) -> String) -> String {
        leaveBy <= now ? "Leave now" : "Leave by \(time(leaveBy))"
    }

    /// The row's line: "Drive 18 min · Leave by 14:20".
    static func label(start: Date, travelSeconds: TimeInterval, now: Date, time: (Date) -> String) -> String {
        let leave = leaveBy(start: start, travelSeconds: travelSeconds)
        return "Drive \(durationText(seconds: travelSeconds)) · \(leaveText(leaveBy: leave, now: now, time: time))"
    }

    /// Drops cached estimates for days before `now`'s day (keys whose day can't be read go too).
    static func pruned(_ cache: [String: TravelEstimate], now: Date, calendar: Calendar = .current) -> [String: TravelEstimate] {
        let d = calendar.dateComponents([.year, .month, .day], from: now)
        let today = String(format: "%04d-%02d-%02d", d.year ?? 0, d.month ?? 0, d.day ?? 0)
        return cache.filter { key, _ in
            guard let day = day(ofKey: key) else { return false }
            return day >= today
        }
    }

    /// Location permission: ask only while it was never asked, travel time is on, and an event that needs it is upcoming.
    static func shouldAskPermission(notDetermined: Bool, enabled: Bool, hasEligibleEvent: Bool) -> Bool {
        notDetermined && enabled && hasEligibleEvent
    }

    /// Which lookups to start now: the soonest first, at most `limit` at a time (MapKit throttles bursts).
    static func nextRequests<ID>(_ candidates: [(id: ID, start: Date)], inFlight: Int, limit: Int = 3) -> [ID] {
        let room = max(0, limit - inFlight)
        return candidates.sorted { $0.start < $1.start }.prefix(room).map(\.id)
    }
}
