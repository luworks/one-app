import Foundation

/// The local half of an already accepted system creation. No success receipt may escape
/// until this succeeds. A failed compensation retains its original error and real identity.
public enum ReminderCreationCommit {
  public struct CompensationFailure: LocalizedError {
    public let local: Error
    public let compensation: Error
    public var errorDescription: String? {
      "Local save failed: \(local.localizedDescription). The Apple reminder could not be removed: \(compensation.localizedDescription). Retry keeps the same reminder identity."
    }
  }

  public static func persist(save: () throws -> Void, compensate: () throws -> Void) throws {
    do { try save() } catch {
      let local = error
      do { try compensate() } catch {
        throw CompensationFailure(local: local, compensation: error)
      }
      throw local
    }
  }
}
