import Foundation
import os

/// Bounds a request even when its operation ignores cancellation.
/// Each call owns its worker, timer and completion state; abandoned results are discarded.
public enum AsyncDeadline {
  public struct TimedOut: Error, Sendable, Equatable {
    public init() {}
  }

  public static func run<Value: Sendable>(
    for limit: Duration,
    operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    try await run(timeout: { try await Task.sleep(for: limit) }, operation: operation)
  }

  // Injectable suspension lets tests order completion without wall-clock races.
  static func run<Value: Sendable>(
    timeout: @escaping @Sendable () async throws -> Void,
    operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    let request = Request<Value>()
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        guard request.install(continuation) else { return }
        // These tasks must not be task-group children: a group waits for an
        // uncooperative operation even after its caller has timed out.
        let worker = Task {
          do {
            try Task.checkCancellation()
            let value = try await operation()
            request.finish(.success(value))
          } catch {
            request.finish(.failure(error))
          }
        }
        request.own(worker)
        let timer = Task {
          do { try await timeout() } catch { return }
          request.finish(.failure(TimedOut()))
        }
        request.own(timer)
      }
    } onCancel: {
      request.finish(.failure(CancellationError()))
    }
  }

  private final class Request<Value: Sendable>: Sendable {
    private struct State {
      var result: Result<Value, any Error>?
      var continuation: CheckedContinuation<Value, any Error>?
      var tasks: [Task<Void, Never>] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func install(_ continuation: CheckedContinuation<Value, any Error>) -> Bool {
      let result: Result<Value, any Error>? = state.withLock { state in
        if let result = state.result { return result }
        state.continuation = continuation
        return nil
      }
      if let result {
        continuation.resume(with: result)
        return false
      }
      return true
    }

    func own(_ task: Task<Void, Never>) {
      let finished = state.withLock { state in
        guard state.result == nil else { return true }
        state.tasks.append(task)
        return false
      }
      // Completion may precede installation of either task handle.
      if finished { task.cancel() }
    }

    func finish(_ result: Result<Value, any Error>) {
      let completion = state.withLock {
        state -> (CheckedContinuation<Value, any Error>?, [Task<Void, Never>]) in
        guard state.result == nil else { return (nil, []) }
        state.result = result
        let completion = (state.continuation, state.tasks)
        state.continuation = nil
        state.tasks = []
        return completion
      }
      // Cancel and resume outside the lock; cancellation handlers may reenter.
      for task in completion.1 { task.cancel() }
      completion.0?.resume(with: result)
    }
  }
}
