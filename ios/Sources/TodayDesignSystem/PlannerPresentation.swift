#if os(iOS)
import Foundation
import Observation
import TodayCore

/// Required display-time and preference context, installed by each executable's composition root.
/// It contains no live adapter lookup or process-global fallback.
@MainActor
@Observable
package final class PlannerPresentation {
    package let runtime: PlannerRuntime
    package let defaults: UserDefaults

    package init(runtime: PlannerRuntime, defaults: UserDefaults) {
        self.runtime = runtime
        self.defaults = defaults
    }

    package var now: Date { runtime.now() }
    package var calendar: Calendar { runtime.calendar }
    package var locale: Locale { runtime.locale }
}
#endif
