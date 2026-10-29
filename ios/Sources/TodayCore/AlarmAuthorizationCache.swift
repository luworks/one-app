import Foundation
import Observation

package enum AlarmAuthorization: Equatable, Sendable {
  case unavailable, notDetermined, denied, authorized
}

/// UI reads never call the system. Only a current snapshot may grant scheduling access.
@MainActor
@Observable
package final class AlarmAuthorizationCache {
  package private(set) var state: AlarmAuthorization = .notDetermined
  private var revision = 0
  private var refreshing = false
  private var requesting = false

  package init() {}

  package func receive(_ state: AlarmAuthorization) {
    revision += 1
    self.state = state
  }

  /// A suspended system read must not block UI work or spawn more reads on every foreground.
  package func refresh(read: @escaping @Sendable () async -> AlarmAuthorization) async {
    guard !refreshing else { return }
    refreshing = true
    let revision = self.revision
    if state == .authorized { state = .unavailable }
    let next = await read()
    refreshing = false
    guard revision == self.revision else { return }
    receive(next)
  }

  package func request(
    operation: @MainActor () async throws -> AlarmAuthorization
  ) async {
    guard !requesting else { return }
    requesting = true
    defer { requesting = false }
    let revision = self.revision
    do {
      let next = try await operation()
      guard revision == self.revision else { return }
      receive(next)
    } catch {
      // A failed request cannot manufacture authorization or undo a newer system update.
      guard revision == self.revision else { return }
      if state == .authorized { receive(.unavailable) }
    }
  }
}
