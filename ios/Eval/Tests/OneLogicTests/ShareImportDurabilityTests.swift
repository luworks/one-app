import XCTest

@testable import TodayShared

final class ShareImportDurabilityTests: XCTestCase {
  enum Failure: Error { case save }

  /// A file-backed transaction stand-in. Production commits OneTask + ShareImportReceipt in SwiftData instead.
  struct Store: Codable {
    var tasks: [SharedReminder] = []
    var receipts: Set<UUID> = []

    static func load(_ url: URL) throws -> Self {
      guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
      return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    func save(_ url: URL) throws { try JSONEncoder().encode(self).write(to: url, options: .atomic) }

    static func commit(_ drafts: [SharedReminder], at url: URL) throws -> [UUID] {
      var store = try load(url)
      store.tasks += drafts
      store.receipts.formUnion(drafts.map(\.id))
      try store.save(url)
      return drafts.map(\.id)
    }
  }

  func withFiles(_ body: (URL, URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "share-import-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(
      directory.appendingPathComponent("inbox.json"), directory.appendingPathComponent("store.json")
    )
  }

  func draft(_ title: String) -> SharedReminder {
    SharedReminder(
      title: title, note: "Original note", due: Date(timeIntervalSince1970: 86400),
      sharedAt: Date(timeIntervalSince1970: 86400))
  }

  @discardableResult
  func run(_ inbox: URL, _ store: URL, acknowledge: ((Set<UUID>) -> Bool)? = nil) throws
    -> ShareImport.Result<UUID>
  {
    try ShareImport.run(
      at: inbox, committedIDs: { try Store.load(store).receipts },
      persist: { try Store.commit($0, at: store) }, acknowledge: acknowledge)
  }

  func testFailedPersistenceKeepsTheDurableDraftAndDoesNotReportSuccess() throws {
    try withFiles { inbox, store in
      let originalDraft = draft("Keep this draft")
      XCTAssertTrue(ShareInbox.append(originalDraft, at: inbox))
      let original = try Data(contentsOf: inbox)
      var reportedSuccess = false
      var acknowledgments = 0
      XCTAssertThrowsError(
        try {
          let _: ShareImport.Result<UUID> = try ShareImport.run(
            at: inbox, committedIDs: { [] },
            persist: { pending in
              XCTAssertEqual(pending, [originalDraft])
              throw Failure.save
            },
            acknowledge: { _ in
              acknowledgments += 1
              return true
            })
          reportedSuccess = true
        }())
      XCTAssertFalse(reportedSuccess)
      XCTAssertEqual(acknowledgments, 0)
      XCTAssertEqual(try Data(contentsOf: inbox), original)
      XCTAssertTrue(try Store.load(store).tasks.isEmpty)
      XCTAssertEqual(
        try run(inbox, store).added, [originalDraft.id], "the same draft can be retried")
      XCTAssertEqual(try Store.load(store).tasks, [originalDraft])
    }
  }

  func testCommitThenFailedAcknowledgmentSurvivesReloadWithoutDuplicate() throws {
    try withFiles { inbox, store in
      let item = draft("Committed once")
      XCTAssertTrue(ShareInbox.append(item, at: inbox))
      let first = try run(inbox, store, acknowledge: { _ in false })
      XCTAssertEqual(first.added, [item.id])
      XCTAssertFalse(first.acknowledged)
      XCTAssertEqual(try ShareInbox.read(at: inbox), [item])
      // Every call reopens both files; no in-memory identity cache survives the simulated relaunch.
      let retry = try run(inbox, store)
      XCTAssertTrue(retry.added.isEmpty)
      XCTAssertTrue(retry.acknowledged)
      XCTAssertEqual(try Store.load(store).tasks, [item])
      XCTAssertTrue(try ShareInbox.read(at: inbox).isEmpty)
    }
  }

  func testUndoAfterCommitAndFailedAcknowledgmentDoesNotResurrectTask() throws {
    try withFiles { inbox, store in
      let item = draft("Undo me")
      XCTAssertTrue(ShareInbox.append(item, at: inbox))
      try run(inbox, store, acknowledge: { _ in false })
      var committed = try Store.load(store)
      committed.tasks.removeAll()  // Undo deletes the task, not its import receipt.
      try committed.save(store)
      XCTAssertTrue(try run(inbox, store).added.isEmpty)
      XCTAssertTrue(try Store.load(store).tasks.isEmpty)
      XCTAssertEqual(try Store.load(store).receipts, [item.id])
    }
  }

  func testAcknowledgmentPreservesAnAppendAfterTheRead() throws {
    try withFiles { inbox, store in
      let first = draft("First")
      let later = draft("Arrived during save")
      XCTAssertTrue(ShareInbox.append(first, at: inbox))
      let result = try ShareImport.run(
        at: inbox, committedIDs: { try Store.load(store).receipts },
        persist: { pending in
          XCTAssertTrue(ShareInbox.append(later, at: inbox))
          return try Store.commit(pending, at: store)
        })
      XCTAssertEqual(result.added, [first.id])
      XCTAssertEqual(try ShareInbox.read(at: inbox), [later])
      XCTAssertEqual(try run(inbox, store).added, [later.id])
      XCTAssertEqual(Set(try Store.load(store).tasks.map(\.id)), [first.id, later.id])
    }
  }

  func testCorruptInboxRemainsByteForByteUnchanged() throws {
    try withFiles { inbox, store in
      let bytes = Data(#"[{"title":"Keep the original draft""#.utf8)
      try bytes.write(to: inbox)
      XCTAssertThrowsError(try run(inbox, store))
      XCTAssertFalse(ShareInbox.acknowledge([UUID()], at: inbox))
      XCTAssertFalse(ShareInbox.append(draft("New"), at: inbox))
      XCTAssertEqual(try Data(contentsOf: inbox), bytes)
      XCTAssertTrue(try Store.load(store).receipts.isEmpty)
    }
  }

  func testSuccessfulImportIsNotImportedAgainEvenWithRepeatedIDInInbox() throws {
    try withFiles { inbox, store in
      let item = draft("One approved share")
      XCTAssertTrue(ShareInbox.append(item, at: inbox))
      XCTAssertTrue(ShareInbox.append(item, at: inbox))
      XCTAssertEqual(try run(inbox, store).added, [item.id])
      XCTAssertEqual(try Store.load(store).tasks, [item])
      XCTAssertTrue(try run(inbox, store).added.isEmpty)
      // A stale replay of the original inbox after relaunch is also consumed without inserting.
      XCTAssertTrue(ShareInbox.append(item, at: inbox))
      XCTAssertTrue(try run(inbox, store).added.isEmpty)
      XCTAssertEqual(try Store.load(store).tasks, [item])
    }
  }
}
