# Existing event save investigation — issue #79

Status: iOS 27 compatibility fallback implemented; focused simulator verification in progress.
A build alone is not completion of the owner-reported bug.

- Clean inherited base: `edb7d737710cfae5603dd3ec462c4f04da8ac842`.
- Screenshot is the native EventKitUI editor, not the local SwiftUI `EventEditor`.
- `NativeEvents.edit` presents `EKEventEditViewController` directly; its retained
  delegate dismisses on saved, canceled and deleted completion. The public SDK
  documents unchanged Done as canceled completion. The separate existing-event
  watcher compensates only for deletion; it is not a save-success signal.
- Baseline `EventSaveTests/testExistingNativeEventUnchangedSaveCloses` failed:
  tapping Done left Edit Event visible after five seconds. The failure hierarchy
  includes the remote EventKitUI service and its Done button marked Disabled.
- One focused experiment set the edit delegate before assigning event/store and
  the presentation delegate after presentation. The same regression failed. This
  ineffective production edit was removed; it must not be presented as a fix.
- `EventSaveTests/testExistingLocalEventUnchangedSaveCloses` passed, including
  opening the same local daily event again after saving.
- The initial native changed-title check stopped before saving because its Title
  selector did not match the native field. The observed identifier is title-field;
  the corrected-selector run then timed out opening Edit Event before reaching
  the title edit. Changed-event saving/persistence remains unverified; these are
  harness/entry blockers, not evidence of a failed EventKit save.

The local editor separately uses `try? context.save()` and ignores a nil external
save result. This is a source finding, not a reproduced storage failure and not
an explanation of the screenshot. It was not changed speculatively in this PR.

Do not infer save success from elapsed time, a store-change notification or the
absence of an error alert. Do not dirty an unchanged event merely to enable a
system button, because that can write metadata or notify invitees. A safe next
implementation needs a public supported completion path or a deliberately scoped
editor fallback that preserves unedited EventKit fields and exposes actual save
errors. No signing, schema, migration or phone actions were taken.

Apple's forum has a related iOS 27 native editor report (FB23371618), including
repeat-event scope/cancel problems. It corroborates a platform risk, not the cause
of this app's failure: https://developer.apple.com/forums/thread/835780

## Reusable input and retained evidence

`tests/fixtures/event-save.json` and `ios/OneUITests/EventSaveTests.swift` contain
the versioned input/journeys. The tests use the existing simulator-only EventKit
hooks; they do not access a real user's calendar. All raw logs and complete
xcresult bundles are under the primary checkout:

`tests/results/runs/calendar-save-20261018/`

- `baseline/`: original implementation, native unchanged regression failure.
- `delegate-first/`: harness refused an already booted owned device; no UI test.
- `delegate-first-ui/`: initialization-order experiment, unchanged save failed.
- `changed-and-local/`: local unchanged passed; native title selector failed.
- `native-changed-selector/`: corrected native title-field check.

The QA Activity SQLite journal session is `calendar-save-20261018`; runner events
record commands, test results and indexed artifact paths/hashes. Only the named
Today-EventSave simulator and its independent fixed cache were used. No logic or
full UI suite was run. Physical iCloud/Family calendar save and server errors are
unverified.

## iOS 27 compatibility fallback

The public native editor exposes completion delegates and cancellation, but no
programmatic save/Done API. The original event belongs to the same store assigned
to the controller, and changing delegate initialization order did not help.
Rather than fabricate a change, existing events on iOS 27 now open a small
EventKit-backed form. New events retain the native editor. Earlier iOS versions
retain their existing path.

Done without edits closes without a write. Edited title, dates, all-day, location
and notes are applied only when changed, to the exact original EKEvent and store;
all other properties are retained. Recurring changes ask this occurrence or all
future events. An event that disappeared is not recreated. Read-only calendars
explain their restriction. EventKit save errors stay in the form with the draft;
failed pending changes on the EKEvent are reset, without dropping the draft.

More Options opens the original native editor by direct UIKit presentation,
retaining alerts, repeat, invitees, calendar, attachments and deletion. It is
available before editing, so unsaved drafts cannot silently be discarded. Native
saved/deleted completion closes the fallback too; cancellation returns to it.
The system's unchanged Done limitation still exists *inside More Options*; Cancel
returns to the working fallback Done. This is a compatibility fallback, not a
claim that the system service was repaired.

Apple API references:
- [Native completion delegate](https://developer.apple.com/documentation/eventkitui/ekeventeditviewdelegate/eventeditviewcontroller(_:didcompletewith:))
- [Explicit EventKit save and error handling](https://developer.apple.com/documentation/eventkit/ekeventstore/save(_:span:commit:))
- [Refresh and deleted-event detection](https://developer.apple.com/documentation/eventkit/ekobject/refresh())

Focused checks retain the original Calendar return/reopen assertions. Test-only
metadata seeds notes, a URL and two alerts to check preservation across relaunch.
A DEBUG-only save failure injection tests error/draft retention; it does not
represent an observed real server failure. Local unchanged save/reopen was already
green and is intentionally not rerun. Physical iCloud/Family behavior, invitations,
recurrence UI and More Options completion remain unverified unless recorded below.
