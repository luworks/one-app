import Foundation
import SwiftData

/// A few items around today so the first launch isn't empty. Inserted once; Delete all data removes them.
enum SampleData {
    static func resetFlags() {
        UserDefaults.standard.removeObject(forKey: "one.sampleData.v1")
        UserDefaults.standard.removeObject(forKey: "one.sampleData.dev.v1")
    }

    /// `-devData`: the full dev dataset on top of the basic sample, in a fresh in-memory store. Use it in a simulator
    /// (`xcrun simctl launch <udid> com.luworks.one -devData`); on a phone it would schedule its alarms for real.
    static var isDevData: Bool { ProcessInfo.processInfo.arguments.contains("-devData") }

    /// Chats across every sidebar group (and one archived), more events across the week, alarms (on, off, repeating, once),
    /// reminders in each list (flagged, overdue, completed, ringing as an alarm). Everything is made up.
    static func insertDevExtras(_ context: ModelContext) {
        let key = "one.sampleData.dev.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let cal = Calendar.current
        let now = Date.now
        let today = cal.startOfDay(for: now)
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int) -> Date {
            let d = cal.date(byAdding: .day, value: dayOffset, to: today) ?? today
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: d) ?? d
        }

        // Chats.
        func chat(_ title: String, ago: TimeInterval, archived: Bool = false, _ lines: [(ChatMessage.Role, String)]) {
            let when = now.addingTimeInterval(-ago)
            let thread = ChatThread(title: title, messages: lines.map { ChatMessage(role: $0.0, text: $0.1) }, createdAt: when, updatedAt: when)
            thread.archived = archived
            context.insert(thread)
        }
        let hour: TimeInterval = 3600, day: TimeInterval = 86_400
        chat("Plan my day", ago: 2 * hour, [
            (.user, "Plan my day"),
            (.ai, "Here's a plan around your meetings. Meetings stay fixed; only tasks move. Nothing changes until you apply it."),
            (.ai, "Planned 3 tasks for today."),
        ])
        chat("Call Alex tomorrow at 3pm", ago: 5 * hour, [
            (.user, "Call Alex tomorrow at 3pm"),
            (.ai, "Here's what I understood. Nothing is added until you confirm."),
            (.user, "make it 4pm"),
            (.ai, "Updated. Nothing is added until you confirm."),
            (.ai, "Added “Call Alex” · Planned Tomorrow 16:00."),
        ])
        chat("Move the dentist to tomorrow", ago: day + 3 * hour, [
            (.user, "Move the dentist to tomorrow"),
            (.ai, "Here's the change. Nothing changes until you apply it."),
            (.ai, "Moved “Dentist” to Tomorrow 15:00."),
        ])
        chat("What's left today?", ago: 3 * day, [
            (.user, "What's left today?"),
            (.ai, "Today: 3 open tasks and 2 upcoming events.\n· Buy milk\n· Water the plants"),
        ])
        chat("明早7点叫我起床", ago: 9 * day, [
            (.user, "明早7点叫我起床"),
            (.ai, "Here's what I understood. Nothing is added until you confirm."),
            (.ai, "Added “起床” · Planned Tomorrow 07:00 · Rings as alarm."),
        ])
        chat("Send the Q3 report by Friday", ago: 40 * day, [
            (.user, "Send the Q3 report by Friday"),
            (.ai, "Added “Send the Q3 report” · Due Friday."),
        ])
        chat("Book a hotel in Rome for March", ago: 60 * day, archived: true, [
            (.user, "Book a hotel in Rome for March"),
            (.ai, "Added “Book a hotel in Rome” · No date, goes to your Inbox."),
        ])

        // Alarms.
        let wake = OneAlarm(hour: 6, minute: 30, label: "Wake up", weekdays: [2, 3, 4, 5, 6])
        context.insert(wake)
        let run = OneAlarm(hour: 8, minute: 30, label: "Weekend run", weekdays: [7, 1])
        run.isOn = false
        context.insert(run)
        context.insert(OneAlarm(hour: 22, minute: 30, label: "Wind down", weekdays: [1, 2, 3, 4, 5], snooze: false))
        context.insert(OneAlarm(hour: 13, minute: 0, label: "Take medicine"))

        // More events across the week.
        for (title, start, minutes) in [
            ("Design review", at(1, 14, 0), 60), ("Gym", at(0, 18, 30), 60), ("Dinner with Mia", at(3, 19, 0), 120),
            ("Flight to Tokyo", at(5, 8, 15), 180), ("1:1 with Sam", at(2, 11, 0), 30),
        ] {
            context.insert(OneEvent(title: title, start: start, durationMinutes: minutes))
        }
        let weekly = OneEvent(title: "Weekly sync", start: at(1, 11, 0), durationMinutes: 45)
        weekly.repeatRule = RepeatRule.weekly.rawValue
        context.insert(weekly)
        let birthday = OneEvent(title: "Mia's birthday", start: at(4, 0, 0), durationMinutes: 1440)
        birthday.isAllDay = true
        context.insert(birthday)

        // More reminders: flagged, scheduled, undated, completed, and one that rings as an alarm.
        func task(_ title: String, list: String, due: Date? = nil, planned: Date? = nil, flagged: Bool = false, done: Bool = false) {
            let t = OneTask(title: title, plannedStart: planned, due: due)
            t.listName = list
            t.flagged = flagged
            context.insert(t)
            if done { t.toggleDone() }
        }
        task("Book flights to Tokyo", list: "Work", due: at(3, 17, 0), flagged: true)
        task("Renew passport", list: "Reminders", due: at(14, 9, 0))
        task("Order birthday gift", list: "Home", due: at(3, 12, 0), flagged: true)
        task("Backup photos", list: "Home")
        task("Reply to Sam", list: "Work", planned: at(0, 17, 0))
        task("Send invoice", list: "Work", done: true)
        task("Call plumber", list: "Home", done: true)
        task("Pick up parcel", list: "Reminders", done: true)
        let trash = OneTask(title: "Take out the trash", plannedStart: at(0, 21, 0))
        trash.listName = "Home"
        trash.reminderOffsetMinutes = 0
        trash.ringsAsAlarm = true
        context.insert(trash)
    }

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
            ("Product sync", at(0, 9, 0), 25),
            ("Lunch with Priya", at(0, 12, 15), 45),
            ("Dentist", at(0, 15, 0), 30),
            ("Weekly review", at(1, 10, 0), 30),
        ]
        for (title, start, minutes) in events {
            context.insert(OneEvent(title: title, start: start, durationMinutes: minutes))
        }
        let standup = OneEvent(title: "Standup", start: at(0, 9, 45), durationMinutes: 15)
        standup.repeatRule = RepeatRule.weekdays.rawValue
        context.insert(standup)
        let offsite = OneEvent(title: "Team offsite", start: at(2, 0, 0), durationMinutes: 2 * 1440)
        offsite.isAllDay = true
        context.insert(offsite)

        let demo = OneTask(title: "Prepare the demo", plannedStart: at(0, 13, 30), durationMinutes: 45, due: at(1, 17, 0))
        demo.listName = "Work"
        demo.flagged = true
        demo.checklist = [ChecklistItem(title: "Outline", done: true), ChecklistItem(title: "Slides"), ChecklistItem(title: "Rehearse")]
        context.insert(demo)
        context.insert(OneTask(title: "Write up design review notes", plannedStart: at(0, 16, 0)))
        let milk = OneTask(title: "Buy milk", due: today)
        milk.listName = "Home"
        milk.tags = ["errands"]
        context.insert(milk)
        let plants = OneTask(title: "Water the plants", due: today)
        plants.listName = "Home"
        plants.repeatRule = RepeatRule.weekly.rawValue
        context.insert(plants)
        context.insert(OneTask(title: "Pay studio invoice", due: at(-1, 17, 0)))
        context.insert(OneTask(title: "Read that design article"))
    }
}
