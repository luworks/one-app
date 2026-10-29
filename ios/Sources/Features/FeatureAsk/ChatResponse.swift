#if os(iOS)
  import Foundation
  import TodayCore

  private struct ChatTurn: Codable, Sendable {
    var requestsCapture: Bool
    var reply: String
  }

  /// A separate route from capture extraction: the model is allowed to say there is nothing to add.
  package enum ChatResponse {
    package enum Result: Sendable { case capture, reply(String) }

    static func respond(_ text: String, history: String, intent: ChatRouting.Intent) async -> Result
    {
      if intent == .capture { return .capture }
      let fallback = ChatRouting.fallbackReply(text)
      // A timeout, unavailable model or empty response stays conversational on every runtime.
      guard AICapture.isAvailable else { return .reply(fallback) }
      let turn: ChatTurn? = await ModelTimeout.run(seconds: 8, stage: .chat) {
        let instructions =
          SystemPrompt.planner + "\n" + """
            You are Today, a helpful conversational assistant in a planner app. Users can simply chat with you.
            Decide whether the latest message actually requests a NEW planner item. Never turn a narrative,
            feeling, test, idea, greeting or question into a task. Merely mentioning a date or Activity is not a request.
            Example: 我进行一个测试，然后看看我的 Activity 中是不是会选择显示 is conversation, not a task called 测试.
            If unsure, respond conversationally or ask what the user means; do not propose an item.
            Reply in the user's language. Do not claim to have read Activity or changed any data.
            Chatting records an AI interaction according to Activity data settings, not a change-ledger entry. Message text is kept only when enabled. Add/Apply requires confirmation.
            This turn's rule intent is \(intent == .conversation ? "conversation: requestsCapture MUST be false" : "undecided").
            """
        return try? await HostedGPT.generate(
          ChatTurn.self, stage: "chat", instructions: instructions,
          input: "Previous conversation (context only):\n\(history)\nLatest user message:\n\(text)",
          schema: .object(["requestsCapture": .boolean, "reply": .string])
        )
      }
      guard let turn else { return .reply(fallback) }
      if intent == .unsure, turn.requestsCapture { return .capture }
      let reply = turn.reply.trimmingCharacters(in: .whitespacesAndNewlines)
      return .reply(reply.isEmpty ? fallback : reply)
    }
  }

#endif
