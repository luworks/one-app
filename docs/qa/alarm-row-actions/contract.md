# Today alarm row actions

## Scope and ownership

`OneAlarm` is Today's persistent alarm record. `alarmKitID` links it to exactly one
alarm in Today's AlarmKit namespace; labels are never used as identity. There is
currently no imported/read-only alarm model or Apple Clock ingestion adapter.
Rows for reminders/events that ring are still their source items: this change does
not turn Stop, Settle or Snooze into completion or source deletion.

Apple's public [`AlarmManager.alarms`](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarms)
returns alarms belonging to the current client, not Apple Clock or another app.
[`schedule(id:configuration:)`](https://developer.apple.com/documentation/alarmkit/alarmmanager/schedule(id:configuration:))
is asynchronous and throwing; [`cancel(id:)`](https://developer.apple.com/documentation/alarmkit/alarmmanager/cancel(id:))
is synchronous and throwing. This implementation offers no private Clock URL/API,
no fake imported alarm edits and no title-based source lookup.

## Write boundary

All operations are `@MainActor`, including `ModelContext` use. No mutable model or
context crosses actors. Required `AlarmService.commit` accepts an edited attached
record or a new detached record. For an attached record it reads the prior saved
settings from the same container and restores those before awaiting system work.
It retains the stable ID, validates local uniqueness and preserves the separate
editor fields as the retry draft. A new editor retains its pending system ID
across retries, including a failed compensation.

The live Ringer serializes commit with existing reconciliation. Busy writes fail
visibly; queued sync is drained after the action unlocks. Before system writes it
checks authorization, enumerates only the client's alarms and excludes active
Today timer IDs. Editing an alarm currently ringing, snoozing or paused fails
visibly. It cancels the old schedule, schedules the proposal under the same ID,
then saves the local model and confirmed signature. Success means both steps
returned successfully. It never changes reminder deadline, planned time or done.

System and local storage are not atomic. A failed commit restores the saved local
settings and attempts to restore the old system schedule (or cancel a failed new
schedule). A failed compensation produces an explicit error. Existing records
clear the confirmed signature and persist recovery intent, so a missing one-time
alarm is not interpreted as having fired; reconciliation can retry the same ID.
If that recovery save also fails, the error remains visible; no success is claimed.
This is compensation, not a crash-atomic cross-system transaction.

`cancel` performs system cancellation only and never deletes or saves a model.
The delete action removes and saves the local record only after cancellation
succeeds. Cancellation failure retains the row. A local deletion-save failure
reinserts the row and reports that the system alarm was cancelled but the row
could not be deleted; Save can restore it or Delete can retry. This partial state
is explicit rather than claiming restored ringing. Successful Delete offers Undo;
Undo uses commit under the same system ID and never inserts on schedule failure.

## Verification boundaries

The native UI journeys use the real rows, SwiftData and editor with the injected
`TestAlarmService`; they do not prove physical AlarmKit scheduling/ringing or
Apple Clock interoperability. Integration checks exercise the shared persistence
and compensation implementation, paired schedule/cancel failures and retry,
equal-label identity separation, local-save compensation and stable new IDs.
Physical device AlarmKit behavior remains a separate, unperformed gate.
