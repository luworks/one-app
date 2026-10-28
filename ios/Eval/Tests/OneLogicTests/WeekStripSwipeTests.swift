import Foundation
import Testing
import TodayCore

@Test func weekStripSwipeCommitsOncePerGesture() {
  var swipe = WeekStripSwipe()
  #expect(swipe.update(x: -35, y: 0) == nil)
  #expect(swipe.update(x: -40, y: 50) == nil)
  #expect(swipe.update(x: -36, y: 0) == 1)
  #expect(swipe.update(x: -300, y: 0) == nil)
  #expect(swipe.update(x: 100, y: 0) == nil)
  swipe.reset()
  #expect(swipe.update(x: 36, y: 0) == -1)
}
