import Foundation
import SwiftData

/// A few items around today so the first launch isn't empty. Inserted once; 清空全部数据 removes them.
enum SampleData {
    static func insertIfNeeded(_ context: ModelContext) {
        let key = "one.sampleData.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int) -> Date {
            let d = cal.date(byAdding: .day, value: dayOffset, to: today) ?? today
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: d) ?? d
        }

        let events: [(String, Date, Int)] = [
            ("产品同步", at(0, 9, 0), 25),
            ("和 Priya 吃午饭", at(0, 12, 15), 45),
            ("牙医", at(0, 15, 0), 30),
            ("周会", at(1, 10, 0), 30),
        ]
        for (title, start, minutes) in events {
            context.insert(OneEvent(title: title, start: start, durationMinutes: minutes))
        }

        context.insert(OneTask(title: "准备演示", plannedStart: at(0, 13, 30), durationMinutes: 45, due: at(1, 17, 0)))
        context.insert(OneTask(title: "整理设计评审笔记", plannedStart: at(0, 16, 0)))
        context.insert(OneTask(title: "买牛奶", due: today))
        context.insert(OneTask(title: "付工作室发票", due: at(-1, 17, 0)))
        context.insert(OneTask(title: "看看那篇设计文章"))
    }
}
