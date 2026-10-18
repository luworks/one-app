import Foundation

/// One city of the bundled list (`cities.json`, built by `scripts/build_cities.py` from GeoNames, CC BY 4.0).
struct CityRecord: Codable, Hashable, Identifiable {
    /// GeoNames id; 0 for a city made up from a time zone identifier (see `CityDatabase.city(forKey:)`).
    let id: Int
    let name: String
    /// Chinese name when GeoNames has one (simplified or traditional; `CityDatabase` reads either).
    let zh: String?
    /// ISO country code ("CN"); empty for a made-up city.
    let cc: String
    /// IANA time zone identifier ("Asia/Shanghai").
    let tz: String
    let lat: Double?
    let lon: Double?
    /// Population rank within the list, 1 = largest.
    let rank: Int
    let capital: Bool?

    init(id: Int, name: String, zh: String? = nil, cc: String = "", tz: String, lat: Double? = nil, lon: Double? = nil,
         rank: Int = 100_000, capital: Bool? = nil) {
        self.id = id
        self.name = name
        self.zh = zh
        self.cc = cc
        self.tz = tz
        self.lat = lat
        self.lon = lon
        self.rank = rank
        self.capital = capital
    }

    /// What World Clock saves: "g1816670" for a listed city, the time zone identifier for a made-up one.
    var key: String { id > 0 ? "g\(id)" : tz }

    var isCapital: Bool { capital == true }
    var timeZone: TimeZone? { TimeZone(identifier: tz) }

    /// Sort weight for results: capitals count as much larger cities (smaller is better).
    var importance: Int { rank - (isCapital ? 250 : 0) }
}

/// The offline city list: search that understands English and Chinese names, countries and diacritics, the time zone of
/// the device mapped to a city, and the saved list's migration from time zone identifiers.
struct CityDatabase {
    let cities: [CityRecord]
    private let byKey: [String: CityRecord]
    private let folded: [String: Folded]
    private let countryNames: [String: (en: String, zh: String)]

    private struct Folded {
        var name: String
        var words: [String]
        var zhHans: String
        var tz: String
    }

    init(cities: [CityRecord]) {
        self.cities = cities
        var keys: [String: CityRecord] = [:]
        var folds: [String: Folded] = [:]
        var countries: [String: (en: String, zh: String)] = [:]
        let en = Locale(identifier: "en_US"), zh = Locale(identifier: "zh_Hans")
        // One conversion for all Chinese names: a transform per name would take seconds.
        let simplifiedNames = Self.simplified(cities.map { $0.zh ?? "" }.joined(separator: "\n"))
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for (i, c) in cities.enumerated() {
            keys[c.key] = c
            let name = Self.fold(c.name)
            folds[c.key] = Folded(name: name, words: name.split(separator: " ").map(String.init),
                                  zhHans: i < simplifiedNames.count ? Self.fold(simplifiedNames[i]) : "",
                                  tz: Self.fold(c.tz.replacingOccurrences(of: "_", with: " ")))
            if countries[c.cc] == nil, !c.cc.isEmpty {
                countries[c.cc] = (Self.fold(en.localizedString(forRegionCode: c.cc) ?? c.cc),
                                   Self.fold(zh.localizedString(forRegionCode: c.cc) ?? ""))
            }
        }
        byKey = keys
        folded = folds
        countryNames = countries
    }

    static func decode(_ data: Data) throws -> CityDatabase {
        CityDatabase(cities: try JSONDecoder().decode([CityRecord].self, from: data))
    }

    // MARK: Text

    /// Lowercase, no diacritics, no apostrophes or hyphens, single spaces: "Xi’an" and "xian", "São Paulo" and "sao paulo" meet.
    static func fold(_ text: String) -> String {
        var s = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        for mark in ["'", "\u{2019}", "\u{2018}", "\u{02BB}", "-", ".", ","] { s = s.replacingOccurrences(of: mark, with: mark == "-" ? " " : "") }
        return s.split(whereSeparator: { $0 == " " }).joined(separator: " ")
    }

    /// Traditional characters to simplified, so "紐約" and "纽约" are the same search.
    static func simplified(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        return text.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? text
    }

    /// Traditional characters for readers who use them.
    static func traditional(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        return text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? text
    }

    /// The city's name as the reader's language writes it: Chinese for a Chinese interface (script by the locale), else English.
    func displayName(_ city: CityRecord, locale: Locale = .current) -> String {
        guard locale.language.languageCode?.identifier == "zh", let zh = city.zh else { return city.name }
        return locale.language.script?.identifier == "Hant" || locale.region?.identifier == "TW" || locale.region?.identifier == "HK"
            ? Self.traditional(zh) : Self.simplified(zh)
    }

    /// "China", "中国": the country of a city in the reader's language.
    static func countryName(_ cc: String, locale: Locale = .current) -> String {
        cc.isEmpty ? "" : (locale.localizedString(forRegionCode: cc) ?? cc)
    }

    // MARK: Lookup

    func city(forKey key: String) -> CityRecord? {
        if let hit = byKey[key] { return hit }
        return madeUp(fromIdentifier: key)
    }

    /// A city for a time zone identifier that no listed city uses ("Pacific/Chatham" → "Chatham").
    private func madeUp(fromIdentifier identifier: String) -> CityRecord? {
        guard TimeZone(identifier: identifier) != nil, let name = WorldClock.cityName(fromIdentifier: identifier) else { return nil }
        return CityRecord(id: 0, name: name, tz: identifier)
    }

    /// The listed city that stands for a time zone: the one named like the zone ("Los Angeles" for America/Los_Angeles),
    /// else the most important one in it. A zone no city uses gets a made-up city named after the zone.
    func city(forTimeZone identifier: String) -> CityRecord? {
        let inZone = cities.filter { $0.tz == identifier }
        let zoneName = WorldClock.cityName(fromIdentifier: identifier).map(Self.fold)
        if let named = inZone.first(where: { Self.fold($0.name) == zoneName }) { return named }
        if let best = inZone.min(by: { $0.importance < $1.importance }) { return best }
        return madeUp(fromIdentifier: identifier)
    }

    /// The saved list after an update: old entries are time zone identifiers ("Asia/Tokyo"), new ones city keys ("g1850147").
    /// Identifiers become the city that stands for the zone, unknown entries are dropped, duplicates collapse, order stays.
    func migrate(_ stored: [String]?) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for entry in stored ?? [] {
            let key: String?
            if byKey[entry] != nil { key = entry }
            else if entry.hasPrefix("g"), Int(entry.dropFirst()) != nil { key = nil }   // a listed city this version no longer has
            else { key = city(forTimeZone: entry)?.key }
            if let key, seen.insert(key).inserted { out.append(key) }
        }
        return out
    }

    // MARK: Search

    /// Cities for a query, best first. Matches English and Chinese names (also traditional), country names in either
    /// language ("china", "中国"), and time zone names; ignores case and diacritics. Order: exact name, name start, word start,
    /// Chinese name, name contains, country, time zone; inside each, bigger cities and capitals first. An empty query lists
    /// everything, most important first.
    func search(_ query: String, limit: Int? = nil) -> [CityRecord] {
        let q = Self.fold(query)
        let qHans = Self.fold(Self.simplified(query.trimmingCharacters(in: .whitespacesAndNewlines)))
        var ranked: [(tier: Int, city: CityRecord)] = []
        for city in cities {
            guard let f = folded[city.key] else { continue }
            let tier: Int?
            if q.isEmpty { tier = 0 }
            else if f.name == q { tier = 0 }
            else if f.name.hasPrefix(q) { tier = 1 }
            else if f.words.contains(where: { $0.hasPrefix(q) }) { tier = 2 }
            else if !f.zhHans.isEmpty, f.zhHans == qHans { tier = 0 }
            else if !f.zhHans.isEmpty, f.zhHans.hasPrefix(qHans) { tier = 1 }
            else if f.name.contains(q) { tier = 3 }
            else if !f.zhHans.isEmpty, f.zhHans.contains(qHans) { tier = 3 }
            else if q.count >= 2, let country = countryNames[city.cc],
                    country.en.contains(q) || (!country.zh.isEmpty && country.zh.contains(qHans)) { tier = 4 }
            else if q.count >= 2, f.tz.contains(q) { tier = 5 }
            else { tier = nil }
            if let tier { ranked.append((tier, city)) }
        }
        ranked.sort { a, b in
            a.tier != b.tier ? a.tier < b.tier : (a.city.importance != b.city.importance ? a.city.importance < b.city.importance : a.city.id < b.city.id)
        }
        let result = ranked.map(\.city)
        return limit.map { Array(result.prefix($0)) } ?? result
    }
}
