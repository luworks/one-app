import Foundation

/// Receipt for an explicitly confirmed creation; local persistence remains the caller's job.
package enum CalendarCreationReceipt: Equatable {
  case localOnly
  case committed(externalID: String)
}

package enum CalendarCreationError: Error, Equatable {
  case existingEvent
  case unavailable
  case calendarMissing
  case calendarReadOnly
  case missingIdentifier
}

/// Shared destination validation and commit boundary for live and deterministic adapters.
package enum CalendarCreation {
  package static func commit<Destination>(
    calendarID: String?, connected: Bool,
    resolve: (String?) -> Destination?, writable: (Destination) -> Bool,
    save: (Destination) throws -> String?
  ) throws -> CalendarCreationReceipt {
    guard connected else {
      guard calendarID == nil else { throw CalendarCreationError.unavailable }
      return .localOnly
    }
    guard let destination = resolve(calendarID) else { throw CalendarCreationError.calendarMissing }
    guard writable(destination) else { throw CalendarCreationError.calendarReadOnly }
    guard let id = try save(destination), !id.isEmpty else {
      throw CalendarCreationError.missingIdentifier
    }
    return .committed(externalID: id)
  }
}
