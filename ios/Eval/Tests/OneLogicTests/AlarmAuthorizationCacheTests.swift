import XCTest

@testable import TodayCore

@MainActor
final class AlarmAuthorizationCacheTests: XCTestCase {
  func testDeniedRequestReturnsWithoutAnotherSystemRead() async {
    let cache = AlarmAuthorizationCache()
    await cache.request { .denied }
    XCTAssertEqual(cache.state, .denied)
    await cache.request { throw CancellationError() }
    XCTAssertEqual(cache.state, .denied)
  }

  func testSuspendedRefreshLeavesMainActorResponsiveAndCannotOverwriteDenial() async {
    let cache = AlarmAuthorizationCache()
    let read = SuspendedRead()
    let refresh = Task { await cache.refresh { await read.value() } }
    await read.waitUntilStarted()
    // This actor turn runs while the system read is suspended.
    await cache.request { .denied }
    XCTAssertEqual(cache.state, .denied)
    await read.finish(.authorized)
    await refresh.value
    XCTAssertEqual(cache.state, .denied)
  }

  func testForegroundRefreshRevokesStaleGrantAndAcceptsCurrentState() async {
    let cache = AlarmAuthorizationCache()
    cache.receive(.authorized)
    let read = SuspendedRead()
    let refresh = Task { await cache.refresh { await read.value() } }
    await read.waitUntilStarted()
    XCTAssertEqual(cache.state, .unavailable)
    await read.finish(.denied)
    await refresh.value
    XCTAssertEqual(cache.state, .denied)
    await cache.refresh { .authorized }
    XCTAssertEqual(cache.state, .authorized)
  }

  func testUpdateWinsOverOlderRequestAndRequestError() async {
    let cache = AlarmAuthorizationCache()
    await cache.request {
      cache.receive(.denied)
      return .authorized
    }
    XCTAssertEqual(cache.state, .denied)
    await cache.request {
      cache.receive(.authorized)
      throw CancellationError()
    }
    XCTAssertEqual(cache.state, .authorized)
    await cache.request { throw CancellationError() }
    XCTAssertEqual(cache.state, .unavailable)
  }
}

private actor SuspendedRead {
  private var continuation: CheckedContinuation<AlarmAuthorization, Never>?
  private var started: CheckedContinuation<Void, Never>?
  func value() async -> AlarmAuthorization {
    await withCheckedContinuation {
      continuation = $0
      started?.resume()
      started = nil
    }
  }
  func waitUntilStarted() async {
    if continuation != nil { return }
    await withCheckedContinuation { started = $0 }
  }
  func finish(_ state: AlarmAuthorization) { continuation?.resume(returning: state) }
}
