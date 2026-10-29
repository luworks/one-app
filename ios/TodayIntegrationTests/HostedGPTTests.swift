#if os(iOS)
  import Foundation
  import Testing
  @testable import FeatureAsk

  struct HostedGPTTests {
    private struct Title: Decodable, Sendable { let title: String }

    private func response(
      status: String = "completed", model: String = "gpt-6-luna", refusal: Bool = false
    ) throws -> Data {
      let title = String(decoding: try JSONEncoder().encode(["title": "Call Alex"]), as: UTF8.self)
      return try JSONSerialization.data(withJSONObject: [
        "status": status, "model": model,
        "output": [
          ["type": "reasoning", "content": [["type": "output_text", "text": "reasoning"]]],
          [
            "type": "message",
            "content": [["type": refusal ? "refusal" : "output_text", "text": title]],
          ],
        ],
        "usage": ["input_tokens": 100, "output_tokens": 70],
      ])
    }

    @Test
    func completedMessageDecodesWithoutMistakingReasoningForOutput() throws {
      let result = try HostedGPT.decodeResponse(Title.self, data: response())
      #expect(result.value.title == "Call Alex")
      #expect(result.inputTokens == 100)
      #expect(result.outputTokens == 70)
    }

    @Test
    func truncatedResponseCannotBecomeAPartialPlannerAction() throws {
      let data = try response(status: "incomplete")
      #expect(throws: HostedGPT.Failure.incomplete) {
        try HostedGPT.decodeResponse(Title.self, data: data)
      }
    }

    @Test
    func wrongModelCannotSilentlyReplaceTheConfiguredModel() throws {
      let data = try response(model: "another-model")
      #expect(throws: HostedGPT.Failure.incomplete) {
        try HostedGPT.decodeResponse(Title.self, data: data)
      }
    }

    @Test
    func refusalCannotBeReportedAsASuccessfulPlannerResponse() throws {
      let data = try response(refusal: true)
      #expect(throws: HostedGPT.Failure.invalidResponse) {
        try HostedGPT.decodeResponse(Title.self, data: data)
      }
    }
  }
#endif
