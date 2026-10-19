import TodayCore
import TodayShared
import TodayData
import TodayPlatform
import TodayDesignSystem
import FeatureClock
import FeatureHealth
import Foundation
import Darwin

/// Cold start time: process start (from the kernel) to Today's first appearance.
@MainActor
enum LaunchTimer {
    private(set) static var milliseconds: Int?

    static func markFirstFrame() {
        guard milliseconds == nil else { return }
        milliseconds = elapsedMs()
        mark("first frame")
    }

    /// Debug breadcrumbs for where launch time goes.
    static func mark(_ label: String) {
        #if DEBUG
        print("LAUNCH \(label): \(elapsedMs() ?? -1)ms")
        #endif
    }

    static func elapsedMs() -> Int? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        let started = Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
        return Int((Date().timeIntervalSince1970 - started) * 1000)
    }
}
