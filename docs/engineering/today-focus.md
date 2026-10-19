# Today Focus v1

Baseline: `324760cc8a1c4c6d138d2ae5abf76346b89b9e9c` (verified clean worktree).

## Semantics and scope

Settle hides an explicitly chosen occurrence from the active Today attention list. It remains recoverable in Settled. Snooze hides it until a finite user-chosen instant; the existing Today clock/foreground refresh and relaunch reveal expired items. Neither operation completes a reminder, changes dates, moves a meeting, cancels an event, changes an alarm/notification, nor writes EventKit. Individual overdue hiding is the owner's explicit exception to the otherwise-visible overdue rule. AI has no Focus mutation capability.

Today retains its timeline. Leading swipe offers Settle and Snooze; trailing Delete remains separately destructive. Active, Snoozed and Settled have accessible collapsible counts and explicit Restore. Calendar and Reminders retain source records. Hidden meetings remain in the busy intervals used for free gaps and suggested times; planner inputs are unchanged.

Delete uses PR108's existing `TaskActions.deleteConfirmed` / `ReminderDeletionReceipt`, after that dependency is integrated. It must not call the older queued reminder deletion path. Calendar deletion revalidates the exact ID/occurrence and permission, commits EventKit first, then removes a local mirror. Recurrence scope remains explicit. External absence cannot create an Undo that resurrects someone else's deletion; supported Undo is receipt-guarded compensation.

## Data and identities

No change to the nine SwiftData models, module One, schema, existing identifiers or keys. No content mirror, database, sync engine or scheduler is added. A typed versioned overlay stores only provider/account/calendar/item/occurrence identities, attention state and change time; source content stays in existing models and EventKit. Apple identifiers come from actual EventKit source/calendar/item objects, never titles. Local identifiers use encoded persistent IDs. Repeating events use occurrence dates; recurring reminders use their current due occurrence, so the next reminder remains active. Changed IDs are not guessed or reassigned by title.

The initial Activity metadata candidate was rejected: `ActivityStore.openOrRecover` can replace a damaged Activity file, coupling core attention state to history recovery. The minimal overlay instead uses an atomic app-private JSON file beside existing local state, independently versioned and read back. Corrupt/newer formats fail without deleting/replacing the file. Activity pause, category switches, clear, retention and export do not own this file. Delete All Today Data explicitly clears it and never writes Apple sources. Test instances choose isolated memory or disk locations through the retained action capability.

Source refresh uses the same identity without touching overlay state. Missing/revoked sources never synthesize objects from the overlay; restoration only acts on a currently resolved source record. Reauthorization uses exact identities. Rescheduled recurring occurrences and rekeyed identifiers conservatively remain distinct; stale overlay records cannot create source content. Google is only a future provider namespace boundary, without modules, OAuth or network work.

## Verification contract

Focused disk/version/failure, elapsed-time/DST, occurrence and source-refresh tests; Activity Off/clear independence; hidden-busy scheduling; confirmed deletion effects. Native Today screenshots before/after at the same viewport and 3–5 focused Settle/Snooze/Restore/Undo/persistence journeys. Synthetic fixtures are versioned under `tests/fixtures`; raw evidence and QA SQLite belong to the primary checkout's `tests/results`. Build, logic, simulator EventKit and physical-device evidence remain separate.

## Read-only adapter contract

`FocusIdentityResolution` is a Sendable value enum: `available(FocusIdentity)`, `localOnly`, `unavailable`, `permissionDenied`, `notFound`. Calendar and Reminder services add a `focusIdentity` query; only the adapters read mutable EventKit objects, on their existing main actor. No query calls prepare/connect/reconcile, requests access or writes a source. `account` in the value is the actual EventKit **source identifier**, not a cross-device stable account claim; `calendar` and `item` retain their actual EventKit identifiers. Existing `externalID` serialization and sync maps are untouched.

The installed Xcode 27.1 SDK's `EventKit/EKEvent.h` documents `occurrenceDate` as the original date of a recurring occurrence, retained when detached/rescheduled. Apple events therefore use this original occurrence date, while event lookups validate exact identifiers and the requested current/original occurrence. Local recurring events use their generated occurrence instant; recurring reminders use the actual current due instant. An undated repeating source with no distinguishable occurrence cannot receive an unbounded series-wide decision. Local-only identities use the canonical existing encoded SwiftData persistent identifier (including its store namespace), never a title or regenerated model UUID.

An optional opaque `localReference` anchor identifies the same existing local mirror when permission is temporarily unavailable. It does not substitute for a newly resolved different source/account/calendar/occurrence, and never permits creation, source relinking or restoring a source deleted elsewhere. Old/unresolved overlay records remain locally clearable; they never synthesize content. The only format key is version `1`, with `records` containing identity, state, changedAt and optional localReference. The file path is derived once from the retained store location, independently of Activity recording or recovery operations.

## Focused review resolution

The single focused review identified four concrete risks. Exact Calendar IDs that still exist at a different requested time now return unavailable/failure, rather than a false absence/deletion. The existing series-only action for local repeating models is retained: the frozen model has no occurrence exception field, so a direct `.thisEvent` request is rejected before source mutation. Native system events retain the existing this-occurrence/all-future choice. Purely local series retain their exact backup Undo; source series do not offer a lossy recreation Undo. One-off Calendar compensation is explicitly labelled as a new copy in the default calendar and is blocked if the original source reappears.

A newly resolved different source item atomically detaches stale local anchors, while retaining old decisions as clearable orphan records. Occurrences of the same source item retain distinct anchors. This prevents A-settled → B-active → permission-revoked from applying A's choice to B. Clearing an unavailable choice only removes local attention state; it does not recreate source content.

Production path: `Application Support/Activity/activity.focus-v1.json`; an isolated UI disk store uses `<store-name>.activity.focus-v1.json`. The stable sibling name is chosen from the retained composition location once, never from a recovered/damaged filename. The overlay contains no title, note, source content or credential.

An explicit Restore must also work after the source's scheduled day. Version 1 therefore retains an `active` attention marker for a resolved restored item; it is visible in Today without changing the source date. Default/untracked active items need no record. Expired snoozes and explicit active markers share the Returned to Today presentation when their source is outside the current timeline. Clear choice on an unavailable source removes the record entirely. Undo restores the prior raw local decision; an expired prior snooze restores an active marker, rather than losing the returned attention item. Foreground and tab appearance refresh the existing clock immediately; there is no background notification promise.
