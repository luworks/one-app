import Foundation
import TodayShared

/// Nonblocking travel read boundary. Live implementations may schedule their own location/network work.
@MainActor
public protocol TravelTimeProviding: AnyObject {
  var version: Int { get }
  func seconds(
    eventID: String, start: Date, isAllDay: Bool, place: TravelPlace?, now: Date,
    askPermission: Bool
  ) -> TimeInterval?
  func label(eventID: String, start: Date, isAllDay: Bool, place: TravelPlace?, now: Date)
    -> String?
  func widgetFields(eventID: String, start: Date, isAllDay: Bool, place: TravelPlace?, now: Date)
    -> (minutes: Int, leaveBy: Date)?
}
