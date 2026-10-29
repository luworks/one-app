#if os(iOS)
  import Foundation
  import Security
  import os

  /// A strict JSON schema shared by every hosted planner operation.
  struct HostedSchema: Encodable, Sendable {
    var type: String?
    var properties: [String: HostedSchema]?
    var required: [String]?
    var additionalProperties: Bool?
    var anyOf: [HostedSchema]?
    var items: [HostedSchema]?
    var enumValues: [String]?

    enum CodingKeys: String, CodingKey {
      case type, properties, required, additionalProperties, anyOf, items
      case enumValues = "enum"
    }

    static let string = Self(type: "string")
    static let integer = Self(type: "integer")
    static let boolean = Self(type: "boolean")
    static func object(_ fields: [String: Self]) -> Self {
      Self(
        type: "object", properties: fields, required: fields.keys.sorted(),
        additionalProperties: false)
    }
    static func nullable(_ schema: Self) -> Self {
      Self(anyOf: [schema, Self(type: "null")])
    }
    static func enumeration(_ values: [String]) -> Self {
      Self(type: "string", enumValues: values)
    }
    static func array(_ schema: Self) -> Self {
      // JSON Schema's items is a single schema, encoded separately below.
      Self(type: "array", items: [schema])
    }

    func encode(to encoder: any Encoder) throws {
      var c = encoder.container(keyedBy: CodingKeys.self)
      try c.encodeIfPresent(type, forKey: .type)
      try c.encodeIfPresent(properties, forKey: .properties)
      try c.encodeIfPresent(required, forKey: .required)
      try c.encodeIfPresent(additionalProperties, forKey: .additionalProperties)
      try c.encodeIfPresent(anyOf, forKey: .anyOf)
      try c.encodeIfPresent(enumValues, forKey: .enumValues)
      if let item = items?.first { try c.encode(item, forKey: .items) }
    }
  }

  /// Calls our proxy; no OpenAI API key is ever stored in the app.
  enum HostedGPT {
    struct Configuration: Sendable {
      let endpoint: URL
      let bearer: String?
      let simulator: Bool
    }

    enum Failure: Error, Equatable { case unavailable, rejected, incomplete, invalidResponse }

    static var configuration: Configuration? {
      #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-gptSimulatorProxy")
          || ProcessInfo.processInfo.environment["TODAY_GPT_SIMULATOR_PROXY"] == "1"
        {
          return Configuration(
            endpoint: URL(string: "http://127.0.0.1:8789/v1/responses")!, bearer: nil,
            simulator: true)
        }
      #endif
      guard let raw = Bundle.main.object(forInfoDictionaryKey: "TodayAIEndpoint") as? String,
        let endpoint = URL(string: raw), endpoint.scheme == "https", endpoint.host != nil,
        endpoint.user == nil, endpoint.password == nil, endpoint.query == nil,
        endpoint.fragment == nil, let bearer = sessionBearer(), !bearer.isEmpty
      else { return nil }
      return Configuration(endpoint: endpoint, bearer: bearer, simulator: false)
    }

    static var isAvailable: Bool { configuration != nil }
    private static let log = Logger(subsystem: "com.luworks.one", category: "HostedGPT")
    private static let session: URLSession = {
      let config = URLSessionConfiguration.ephemeral
      config.urlCache = nil
      config.httpCookieStorage = nil
      config.httpMaximumConnectionsPerHost = 4
      config.timeoutIntervalForRequest = 15
      config.timeoutIntervalForResource = 20
      return URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }()

    private final class NoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
      func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
      ) { completionHandler(nil) }
    }

    private static func sessionBearer() -> String? {
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.luworks.today.ai-session",
        kSecAttrAccount as String: "bearer",
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
      ]
      var result: CFTypeRef?
      guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
        let data = result as? Data
      else { return nil }
      return String(data: data, encoding: .utf8)
    }

    private struct Request: Encodable {
      let model = "gpt-6-luna"
      let reasoning = Reasoning(effort: "medium")
      let store = false
      let max_output_tokens = 4096
      let instructions: String
      let input: String
      let text: TextFormat
      struct Reasoning: Encodable { let effort: String }
      struct TextFormat: Encodable {
        let format: Format
        struct Format: Encodable {
          let type = "json_schema"
          let name: String
          let strict = true
          let schema: HostedSchema
        }
      }
    }

    private struct Response: Decodable {
      let status: String
      let model: String
      let output: [Output]
      let usage: Usage?
      struct Output: Decodable {
        let type: String
        let content: [Content]?
      }
      struct Content: Decodable {
        let type: String
        let text: String?
      }
      struct Usage: Decodable {
        let input_tokens: Int
        let output_tokens: Int
      }
    }

    static func generate<Value: Decodable & Sendable>(
      _ type: Value.Type, stage: String, instructions: String, input: String, schema: HostedSchema
    ) async throws -> Value {
      guard let configuration else { throw Failure.unavailable }
      try Task.checkCancellation()
      let id = UUID().uuidString
      let body = Request(
        instructions: instructions, input: input,
        text: .init(format: .init(name: stage, schema: schema)))
      var request = URLRequest(url: configuration.endpoint)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(id, forHTTPHeaderField: "X-Today-Request-ID")
      request.setValue(stage, forHTTPHeaderField: "X-Today-Stage")
      if configuration.simulator {
        request.setValue("simulator", forHTTPHeaderField: "X-Today-Development")
      } else if let bearer = configuration.bearer {
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
      }
      request.httpBody = try JSONEncoder().encode(body)
      guard (request.httpBody?.count ?? 0) <= 32_000 else { throw Failure.rejected }
      do {
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
          data.count <= 256_000
        else { throw Failure.rejected }
        let decoded = try decodeResponse(type, data: data)
        log.info(
          "GPT_CALL id=\(id, privacy: .public) stage=\(stage, privacy: .public) result=model_success input_tokens=\(decoded.inputTokens) output_tokens=\(decoded.outputTokens)"
        )
        return decoded.value
      } catch {
        let outcome: String
        if Task.isCancelled {
          outcome = "model_cancelled"
        } else if (error as? URLError)?.code == .timedOut {
          outcome = "model_timeout"
        } else {
          outcome = "model_error"
        }
        log.info(
          "GPT_CALL id=\(id, privacy: .public) stage=\(stage, privacy: .public) result=\(outcome, privacy: .public)"
        )
        throw error
      }
    }

    /// Refusals, truncation and a misconfigured backend cannot become planner output.
    static func decodeResponse<Value: Decodable & Sendable>(
      _ type: Value.Type, data: Data
    ) throws -> (value: Value, inputTokens: Int, outputTokens: Int) {
      let result = try JSONDecoder().decode(Response.self, from: data)
      guard result.status == "completed", result.model == "gpt-6-luna" else {
        throw Failure.incomplete
      }
      let text = result.output.filter { $0.type == "message" }.flatMap { $0.content ?? [] }
        .filter { $0.type == "output_text" }.compactMap(\.text).joined()
      guard !text.isEmpty, let content = text.data(using: .utf8) else {
        throw Failure.invalidResponse
      }
      let value = try JSONDecoder().decode(type, from: content)
      return (value, result.usage?.input_tokens ?? 0, result.usage?.output_tokens ?? 0)
    }

  }
#endif
