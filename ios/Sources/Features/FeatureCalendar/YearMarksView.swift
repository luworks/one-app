#if os(iOS)
import TodayCore
import TodayPlatform
import TodayDesignSystem
import SwiftUI

/// The Settings choice behind the Year view's holiday numbers. Stored as "auto" (follow region and language), "none" or the chosen sets.
enum YearMarkSettings {
    static let holidaysKey = "today.setting.yearHolidays"
    static let auto = "auto"

    static func sets(_ stored: String, locale: Locale) -> Set<HolidaySet> {
        HolidaySet.resolve(stored, region: locale.region?.identifier, language: locale.language.languageCode?.identifier)
    }
}

/// Settings → Holidays in Year: which sets of holidays and festivals show as red day numbers.
package struct YearHolidaysSettingsView: View {
    @Environment(PlannerPresentation.self) private var presentation
    package init(presentation: PlannerPresentation) {
        _stored = AppStorage(wrappedValue: YearMarkSettings.auto, YearMarkSettings.holidaysKey, store: presentation.defaults)
    }

    @AppStorage(YearMarkSettings.holidaysKey) private var stored = YearMarkSettings.auto

    package var body: some View {
        Form {
            Section {
                ForEach(HolidaySet.allCases) { set in
                    Toggle(isOn: binding(set)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(set.title)
                            Text(set.note).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("settings.yearHolidays.\(set.rawValue)")
                }
            } footer: {
                Text("A holiday or festival shows as a red day number in the Calendar's Year view. Dates are worked out on the phone, for any year. Nothing leaves it.")
            }
        }
        .navigationTitle("Holidays in Year")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(_ set: HolidaySet) -> Binding<Bool> {
        Binding {
            YearMarkSettings.sets(stored, locale: presentation.locale).contains(set)
        } set: { on in
            var sets = YearMarkSettings.sets(stored, locale: presentation.locale)
            if on { sets.insert(set) } else { sets.remove(set) }
            stored = HolidaySet.store(sets)
        }
    }
}

/// The key to the Year view: one line per mark, opened from the (i) next to the year.
package struct YearKeySheet: View {
    package init() {}
    @Environment(\.dismiss) private var dismiss

    package var body: some View {
        NavigationStack {
            List {
                row(AnyView(Text("26").font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundStyle(DayTint.holiday)),
                    "Holiday or festival", "Chosen holiday sets and visible system holiday calendars.")
                row(AnyView(RoundedRectangle(cornerRadius: 3).fill(EventTint.fill(.blue)).frame(width: 32, height: 16)),
                    "Multi-day event", "All-day events lasting several days, in their calendar color.")
                row(AnyView(Text("5").font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .frame(width: 24, height: 20).background(DayTint.busyDay, in: RoundedRectangle(cornerRadius: 4))),
                    "Unusually busy", "Three or more of your own one-off items, among your busiest days of the year. Repeating items and holidays are not counted.")
                row(AnyView(Text("17").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                    .frame(width: 20, height: 20).background(Circle().fill(Color.red))),
                    "Today", "")
            }
            .performanceDestination("calendar.year.key")
            .navigationTitle("Year")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
        .accessibilityIdentifier("calendar.year.keySheet")
    }

    private func row(_ mark: AnyView, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 14) {
            mark.frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if !detail.isEmpty { Text(detail).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#endif
