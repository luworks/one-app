#if os(iOS)
  import Foundation
  import TodayCore
  import os

  /// Opt-in synthetic QA attribution. No prompts, replies, titles, item IDs or error descriptions.
  enum ModelCallTrace {
    enum Stage: String, Sendable { case routing, chat, kind, title, proposals, edit, rank }
    struct Scope: Sendable {
      let id = UUID()
      let stage: Stage
      let started = DispatchTime.now().uptimeNanoseconds
      let turn = ModelCallTrace.turnID
    }
    @TaskLocal static var turnID: UUID?
    @TaskLocal static var current: Scope?
    private static let enabled = ProcessInfo.processInfo.arguments.contains("-intelligenceTrace")
    private static let logger = Logger(
      subsystem: "com.luworks.today.intelligence", category: "calls")

    /// Child tasks inherit the diagnostic turn, including work that finishes after a deadline.
    static func withTurn<T>(_ work: () -> T) -> T {
      guard enabled else { return work() }
      return $turnID.withValue(UUID()) {
        $current.withValue(Scope(stage: .routing)) {
          selection("turn_started")
          defer { selection("turn_routed") }
          return work()
        }
      }
    }

    static func scoped<T: Sendable>(
      _ stage: Stage, work: @Sendable () async -> T
    ) async -> T {
      guard enabled, current?.stage != stage else { return await work() }
      return await $current.withValue(Scope(stage: stage), operation: work)
    }

    /// Surround the actual hosted model call, before any error becomes nil.
    static func generate<T: Sendable>(
      _ stage: Stage, work: () async throws -> T
    ) async rethrows -> T {
      guard enabled else { return try await work() }
      let scope = current.flatMap { $0.stage == stage ? $0 : nil } ?? Scope(stage: stage)
      emit("api_started", scope: scope)
      do {
        let value = try await work()
        emit("api_returned", scope: scope)
        return value
      } catch {
        emit(
          error is CancellationError ? "api_cancelled" : "api_error", scope: scope,
          errorType: errorClass(error))
        throw error
      }
    }

    static func bounded<T: Sendable>(
      _ stage: Stage, seconds: Double, work: @escaping @Sendable () async -> T?
    ) async -> T? {
      await scoped(stage) {
        do {
          let result = try await AsyncDeadline.run(for: .seconds(seconds), operation: work)
          selection(result == nil ? "fallback_nil" : "result_available")
          return result
        } catch {
          selection(
            error is AsyncDeadline.TimedOut
              ? "deadline_timeout"
              : error is CancellationError ? "caller_cancelled" : "deadline_error")
          return nil
        }
      }
    }

    static func selection(_ event: String) {
      guard let current else { return }
      emit(event, scope: current)
    }

    private static func errorClass(_ error: any Error) -> String {
      // Type only: associated values and localized/debug descriptions may contain user text.
      return String(reflecting: type(of: error))
    }

    private static func emit(_ event: String, scope: Scope, errorType: String? = nil) {
      guard enabled else { return }
      var fields: [String: Any] = [
        "version": 1, "call": scope.id.uuidString, "stage": scope.stage.rawValue,
        "event": event,
        "elapsed_ms": Double(DispatchTime.now().uptimeNanoseconds - scope.started) / 1_000_000,
      ]
      if let turn = scope.turn { fields["turn"] = turn.uuidString }
      if event == "turn_started" {
        fields["wall_clock_unix_ms"] = Date().timeIntervalSince1970 * 1000
        fields["system_timezone"] = TimeZone.current.identifier
        fields["system_locale"] = Locale.current.identifier
      }
      if event == "api_started" {
        fields["reported_variant"] = "gpt-6-luna"
        fields["metadata_source"] = "hosted_configuration"
      }
      if let errorType { fields["error_type"] = errorType }
      guard
        let data = try? JSONSerialization.data(
          withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes]),
        let line = String(data: data, encoding: .utf8)
      else { return }
      logger.info("TODAY_MODEL_CALL \(line, privacy: .public)")
    }
  }
#endif
