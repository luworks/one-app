# Ask feature integration

This lane moves the eleven complete Ask implementation files from `ios/One/` to
`ios/Sources/Features/FeatureAsk/`, deleting the originals. It does not edit the
package, project, model bridge, shared components, or Shell. The root owns those
integration changes. All new cross-target implementation APIs use `package`
access; the app reaches them through TodayShell's public entry.

## Dependencies and shared presentation

FeatureAsk directly imports One, TodayCore, TodayShared, TodayData,
TodayPlatform and TodayDesignSystem. One supplies the existing persisted models
and native model-bound operations, including CalendarSync, TaskActions,
CaptureUndo, Capture insertion, Ledger/GrantStore, ActivityCenter and UndoToast.
Each source imports only the modules it names. There is no FeatureClock,
FeatureHealth or editor-feature import.

The baseline already moved CaptureCard, CaptureTitleButton, CardFooter and
ListMenu to `TodayDesignSystem/CaptureCards.swift`; this lane reuses those exact
implementations. Root must expose their needed types/initializers/body with
package access, including the title editor's own dependencies. CaptureProposal
and the batch/compact-row implementation remain solely in FeatureAsk.

## Shell editor host

```swift
package init(
    thread: ChatThread? = nil,
    calendar: CalendarSync,
    now: @escaping () -> Date,
    onBack: @escaping (Bool) -> Void,
    onAdded: @escaping (Capture) -> Void,
    onOpenDay: @escaping (Date) -> Void,
    onOpenTask: @escaping (OneTask, @escaping () -> Void) -> Void,
    onOpenAlarm: @escaping (OneAlarm, @escaping () -> Void) -> Void
)
```

Supply the same live calendar adapter and `{ TodayClock.now }` clock used by
Shell. Ask passes these to its suggestion context; edit candidates use the same
calendar adapter. All actions are required. Shell preserves the existing back-transition,
post-insertion, and event-day navigation behavior. For task/alarm Open it stores
the typed model and the supplied dismissal handler, and presents the real editor
above the still-open Ask modal. Bind the same model container and UndoToast into
that host; retain AIResponseTraceHistory over the editors. Invoke the supplied
handler once from the editor sheet's `onDismiss`, including interactive dismissal,
then release it. It calls the real `refreshCardTitles()` and persists updated
stored cards. Do not dismiss Ask merely to open an editor: that would trigger its
existing disappearance/cancellation behavior.

## Native scene actions

AskView.swift exports the actual mutation bodies as MainActor package functions
on `AskNativeActions`. AskView invokes these same functions; scenes must call
them rather than reimplement mutations or install a service registry.

```swift
applyChange(_ change: PendingChange, context: ModelContext, calendar: CalendarSync) -> AskActionFeedback
applyPlan(_ rows: [(task: OneTask, start: Date)]? = nil,
          plan: inout [(task: OneTask, start: Date)], grant: AIGrant?,
          approval: LedgerApproval = .asked,
          context: ModelContext) -> AskActionFeedback
applyPlanAlways(plan: inout [(task: OneTask, start: Date)],
                grant: inout AIGrant?, context: ModelContext,
                onApproved: (Int) -> Void) -> AskActionFeedback
applyTidy(rows: inout [TidyRow], context: ModelContext) -> AskActionFeedback
```

`AskActionFeedback.messages` contains the existing English replies;
`undo` contains the existing label and real native Undo closure. The calling UI
appends messages and retains/renders Undo. AskView's wrapper continues recording
card resolution and `ActivityEvents.aiUndo`, preserving its thread ID and
animation. SceneCatalog should record the corresponding card resolution at its
explicit button action, and record aiUndo before invoking feedback.undo.action.
For Always, `onApproved(count)` runs after GrantStore grants permission and before
plan application, preserving the native ordering; use it for the real plan-card
resolution event. There is no default empty action.

The actual cards have package constructors: MessageView(message:),
CaptureProposal(capture:batchSize:batch:anchor:) or CaptureProposal(StoredCard),
CaptureStack(proposals:lists:onAdd:onSkip:onAddAll:onUndo:onOpen:onRename:),
TidyRow(task:oldDue:choice:), TidyCard(rows:onApply:onCancel:),
PlanCard(plan:grantUntil:onApply:onAlways:onCancel:),
PendingChange(subject:delete:title:oldText:newStart:notes:attendees:),
ChangeCard(change:onApply:onCancel:) and UndoRow(label:action:).
PlanCard's Always handler and all CaptureStack actions are required. The expanded
capture card also receives the real Undo/Open/Rename callbacks.

## Preserved behavior and evidence

Capture Add/Add all, saved-card state, Undo/Open/Rename, routing, follow-ups,
dictation, suggestions and model prompts retain their real implementations.
Preparation remains read-only; only Add/Apply or the existing seven-day grant
writes. Plan candidates, fixed event obstacles and AutonomyPolicy filtering are
unchanged. Moving a task changes plannedStart, never due; tidy explicitly changes
due through OverdueTidy.newDue, retaining its date/time policy. Calendar failures
retain their rollback/message behavior and attendee warning. No persistence model
or encoded field changed.

ModelTimeout.run and AICapture.withTimeout still use the real
TodayCore.AsyncDeadline.run primitive. Classification/capture/chat retain their
8-second bounds, edit selection its 20-second bound and suggestion ranking its
2-second bound. No structured task-group replacement was introduced.

Validation in this lane: Swift frontend parsing of all eleven moved sources,
whitespace validation, focused source comparison and ownership/import checks.
No build, module typecheck, logic test, simulator UI or device execution is
claimed. Root must wire package dependencies/access, update Shell/SceneCatalog
call sites and perform the integrated build and proportionate behavioral checks.
QA actions are recorded in the canonical
`/Users/yuanlu/code/one-app/tests/results/activity.sqlite` journal under
`ask-reconstruction-20261018`.
