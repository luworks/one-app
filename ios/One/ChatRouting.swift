import Foundation

/// Decide whether a NEW message asks for a planner item before extracting its kind or dates.
/// Uncertainty is a conversation, never permission to manufacture an obligation.
enum ChatRouting {
    enum Intent: Equatable { case capture, conversation, unsure }

    private static func has(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func intent(_ raw: String) -> Intent {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Talking ABOUT reminders, or explicitly declining one, is not asking for one.
        if has(text, #"don['’]t (?:add|create|set|remind|wake)|do not (?:add|create|set|remind|wake)|不要(?:创建|添加|提醒|设)|不用(?:创建|添加|提醒|设)|(?:不要|不用|别).*(?:叫醒|叫我起床)|只是聊|just (?:chatting|talking)|\bhow (?:do|can) (?:i|you)\b|怎么(?:创建|添加|设)|如何"#) { return .conversation }
        if has(text, #"^(?:i (?:already|just|have)|i've) (?:set|added|created|finished|completed)|我(?:已经|刚刚|刚才).*(?:了|过)|我记得|^i (?:remember|asked)\b|^(?:what (?:does|is)|can you explain)|是什么意思|怎么用"#) { return .conversation }
        // Embedded command words in an explanation question or a past report are not a new request.
        if has(text, #"^(?:what happens\b|why (?:did|does|do|would)\b|how (?:does|would)\b|(?:can|could) you (?:explain|tell me|show me)\b)|^(?:为什么|怎么(?:才能|会|设置|添加|创建)|如何)|^(?:yesterday|last night|this morning)[, ]+i (?:set|added|created)\b|^我(?:昨天|昨晚|今天早上)(?:设置了|设了|添加了|创建了)"#) { return .conversation }
        // Alarm verbs must be the request itself, not words embedded in a question or report.
        let alarmRequest = has(text, #"^(?:(?:please|can you|could you|would you)\s+)?(?:(?:set|create|add) (?:me )?(?:an? )?(?:alarm|timer)\b|wake me\b)|^(?:(?:请|可以|能不能|能|可不可以)(?:你)?(?:帮我)?|帮我)?(?:(?:设|定|加|创建).{0,12}(?:闹钟|计时器)|[明天早上晚今后午晨点分半零一二三四五六七八九十两0-9:：\s]*(?:叫醒我|叫我起床))"#)
        if Dialogue.startsNewItem(text) || alarmRequest { return .capture }
        if has(text, #"^(?:hi|hello|hey|thanks|thank you|good morning|good night)\b|^(?:你好|嗨|谢谢|早上好|晚安)|\bi(?: am| was|'m| have| already| just)\b|我(?:正在|在|刚|已经|进行|只是)|(?:感觉|心情|很累|累了|难过|聊聊)|\b(?:feel|feeling)\b|activity|活动记录"#) { return .conversation }
        if has(text, #"^(?:write|draft|compose|make) (?:me|us)\b|^(?:帮我写|给我写|给我讲)|^(?:write|tell|make).*(?:poem|story|joke|诗|故事|笑话)|\b(?:already|finished|completed|yesterday)\b|已经|昨天"#) { return .conversation }
        // Keep terse planner input working, including no-date errands. Dates alone are not an intent.
        if has(text, #"^(?:(?:please|can you|could you)\s+)?(?:buy|pay|send|email|submit|sign|print|book|order|pack|clean|wash|write|finish|fix|water|take out|pick up|drop off|return|renew|file|read|study|prepare|update|reply|follow up|check|call|get|cook|make|gym|workout|run|jog|swim|yoga|walk)\b|^(?:请|帮我)?(?:买|付|交|发|寄|回复|写|整理|订|预订|预约|打电话|取|拿|洗|倒垃圾|遛狗|充电|续|缴|健身|跑步|游泳|瑜伽)"#) { return .capture }
        if isQuestion(text) { return .conversation }
        // First-person intentions can be a story or a request; let the model ask/decide, rather than guessing from a date.
        if has(text, #"\bi (?:want|need|plan|wonder)\b|我(?:想|要|打算)"#) { return .unsure }
        let parsed = CaptureParser.parse(text)
        if (parsed.hasDay || parsed.hour != nil), has(text, #"\b(?:meeting|appointment|lunch|dinner|dentist|flight|class|interview)\b|会议|开会|面试|上课|聚餐|航班|看牙|体检"#) { return .capture }
        return .unsure
    }

    /// Only a time-only answer may precede the conversation guard, and only with an open time context.
    /// Strip a few complete answer wrappers, never arbitrary question/story words that happen to contain a time.
    static func contextualTimeAnswer(_ raw: String, hasTimeContext: Bool,
                                     now: Date = .now, calendar: Calendar = .current) -> String? {
        guard hasTimeContext else { return nil }
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: #"[?？]+$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"^(?:how about|what about)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"(?:[,，]\s*)?(?:可以吗|行吗|好吗)$"#, with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Dialogue.isOnlyWhen(text, now: now, calendar: calendar) else { return nil }
        return text
    }

    static func isQuestion(_ text: String) -> Bool {
        has(text, #"[?？]|什么|怎么|吗|多少|几|是不是|^(?:what|how|when|which|why|do |is |am |any)"#)
    }

    static func isAgendaQuestion(_ text: String) -> Bool {
        isQuestion(text) && has(text, #"\b(?:my (?:schedule|agenda|tasks|events|meetings)|what(?:'s| is) (?:on my|next)|free time)\b|(?:今天|今日).*(?:安排|日程|待办|任务|会议)|接下来.*(?:安排|什么)|空闲"#)
            && !has(text, #"activity|活动记录"#)
    }

    static func fallbackReply(_ text: String) -> String {
        let chinese = has(text, #"\p{Han}"#)
        if has(text, #"activity|活动记录"#) {
            return chinese
                ? "可以，普通聊天不会创建任务、日程或闹钟，也不会产生变更记录。确认添加或应用修改后，才会留下对应的变更记录。聊天也会按 Activity 数据设置记录 AI 交互；是否保留消息文字可在设置中更改。"
                : "Chatting doesn't create a task, event or alarm, or a change in Activity. Confirming Add or Apply records the corresponding change. Activity data also records AI interactions according to your settings, including message text when enabled."
        }
        if has(text, #"^(?:thanks|thank you|谢谢)"#) { return chinese ? "不客气，随时聊。" : "You're welcome. I'm here if you'd like to chat." }
        if has(text, #"^(?:hi|hello|hey|你好|嗨|早上好)"#) { return chinese ? "你好！今天想聊些什么？" : "Hello! What's on your mind?" }
        return chinese
            ? "我们可以直接聊聊。你想继续说说吗？如果想记录待办、日程或闹钟，也可以明确告诉我。"
            : "We can just chat. Tell me more about what's on your mind. If you'd like to save a task, event or alarm, you can ask me explicitly."
    }
}
