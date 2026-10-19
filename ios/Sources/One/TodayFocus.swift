#if os(iOS)
  import Foundation
  import Observation
  import SwiftData
  import TodayCore
  import TodayData

  /// Today-only attention decisions. It never mutates a source model or invokes a source write.
  @MainActor @Observable
  package final class TodayFocus {
    @ObservationIgnored private let store: TodayFocusStore?
    @ObservationIgnored private let ledger: Ledger
    @ObservationIgnored private let runtime: PlannerRuntime
    @ObservationIgnored private var invalidatedReferences: Set<String> = []
    package private(set) var revision = 0
    package private(set) var errorMessage: String?

    package init(ledger: Ledger, runtime: PlannerRuntime) {
      self.ledger = ledger
      self.runtime = runtime
      do {
        guard let location = ledger.activity.store?.location else {
          throw CocoaError(.fileNoSuchFile)
        }
        let focusLocation: TodayFocusStore.Location
        switch location {
        case .memory: focusLocation = .memory
        case .file(let url):
          // The stable path survives Activity history clear and damaged-file recovery.
          focusLocation = .file(url.deletingPathExtension().appendingPathExtension("focus-v1.json"))
        }
        store = try TodayFocusStore(location: focusLocation)
      } catch {
        store = nil
        errorMessage = "Couldn't read saved Focus choices. Your saved file was kept."
      }
    }

    package var records: [FocusRecord] {
      _ = revision
      return store?.records ?? []
    }

    package func identity(
      resolution: FocusIdentityResolution, localReference: String?, kind: String,
      occurrence: Date?
    ) -> FocusIdentity? {
      switch resolution {
      case .available(let identity):
        reconcileAnchor(localReference, with: identity)
        return identity
      case .localOnly:
        guard let localReference else { return nil }
        let identity = FocusIdentity(
          provider: "today.local", account: "local-store", calendar: kind,
          item: localReference, occurrence: occurrence)
        reconcileAnchor(localReference, with: identity)
        return identity
      case .unavailable, .permissionDenied:
        // An opaque local anchor only protects the same mirror during a permission interruption.
        guard let localReference, !invalidatedReferences.contains(localReference) else {
          return nil
        }
        return records.first {
          $0.localReference == localReference && $0.identity.occurrence == occurrence
        }?.identity
      case .notFound: return nil
      }
    }

    /// Invalidate only an opaque association, preserving the user's decision as a recoverable orphan.
    /// The store is not Observable: read-only source resolution does not mutate SwiftUI view state.
    private func reconcileAnchor(_ reference: String?, with identity: FocusIdentity) {
      guard let reference, let store,
        store.records.contains(where: {
          $0.localReference == reference && !$0.identity.sameItem(as: identity)
        })
      else { return }
      do {
        try store.detachReference(reference, except: identity)
      } catch {
        if invalidatedReferences.insert(reference).inserted {
          Task { @MainActor [weak self] in
            self?.errorMessage =
              "Couldn't reconcile saved Focus identities. Saved choices were kept; reconnect and retry."
          }
        }
      }
    }

    package func state(for identity: FocusIdentity?, now: Date) -> TodayFocusState? {
      _ = revision
      guard let identity else { return nil }
      return store?.state(for: identity, now: now)
    }

    package static func reference(_ id: PersistentIdentifier) -> String? {
      Ledger.ref(id).map(Ledger.comparisonKey)
    }

    @discardableResult
    package func change(
      _ state: TodayFocusState?, identity: FocusIdentity?, localReference: String?,
      title: String, context: ModelContext, toast: UndoToast?
    ) -> Bool {
      guard let store, let identity else {
        toast?.showNotice(
          errorMessage ?? "This source is unavailable. Refresh its connection and try again.")
        return false
      }
      let old = store.records.first { $0.identity == identity }?.state
      guard old != state else { return true }
      do {
        try store.set(
          state: state, for: identity, now: runtime.now(), localReference: localReference)
      } catch {
        toast?.showNotice("Couldn't save this Focus choice. Nothing was changed. Try again.")
        return false
      }
      revision += 1
      let committed = store.records.first { $0.identity == identity }
      let action: LedgerAction
      let message: String
      switch state {
      case .settled:
        action = .settled
        message = "Settled “\(title)”"
      case .snoozed:
        action = .snoozed
        message = "Snoozed “\(title)”"
      case .active, nil:
        action = .restored
        message = "Restored “\(title)”"
      }
      let entry = ledger.record(
        action, kind: "focus", title: title, before: label(old), after: label(state),
        context: context)
      toast?.show(message) { [weak self] in
        guard let self else { return }
        guard store.records.first(where: { $0.identity == identity }) == committed else {
          toast?.showNotice("This Focus choice changed again. Use Restore in Today.")
          return
        }
        do {
          let restored: TodayFocusState?
          if case .snoozed(let until) = old, until <= self.runtime.now() {
            restored = .active
          } else {
            restored = old
          }
          try store.set(
            state: restored, for: identity, now: self.runtime.now(), localReference: localReference)
          self.revision += 1
          self.ledger.recordUndo(of: entry, context: context)
        } catch {
          toast?.showNotice("Couldn't undo this Focus choice. Use Restore in Today to retry.")
        }
      }
      return true
    }

    package func clear() throws {
      guard let store else { throw CocoaError(.fileReadCorruptFile) }
      try store.clear()
      revision += 1
    }

    private func label(_ state: TodayFocusState?) -> String {
      switch state {
      case .settled: "Settled in Today"
      case .snoozed(let until): "Snoozed until " + ledger.timeLabel(until)
      case .active, nil: "Active in Today"
      }
    }
  }
#endif
