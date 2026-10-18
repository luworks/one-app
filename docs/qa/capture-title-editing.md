# Capture titles and title editing

Issue: https://github.com/luworks/one-app/issues/64

The owner screenshot shows an Added 23:00 alarm titled `的时候，必须要睡觉`
from `今天晚上11点的时候提醒我，必须要睡觉`. Source inspection confirms the
residual connector and noninteractive title risks; it cannot identify which AI
path generated that screenshot.

The app uses on-device Foundation Models where available, with CaptureParser as
fallback. This change improves model title guidance and applies the same bounded
request cleanup to draft, structured-action and when-action model output. The
fallback preserves `必须要睡觉`, today and 23:00. It classifies this request as a
reminder; a real model may classify an alarm. Modality is intentionally retained.
Mapping synthetic model output is not evidence of actual model generation.

The title itself opens one shared adaptive Save/Cancel title sheet. Pending Save
only edits the draft; Add remains mandatory. An Added title Save resolves the
saved item again and changes only its title/label. It records a `renamed` Activity
entry and offers title Undo through the existing toast. Reminder Activity Undo
also supports rename with a changed-again guard. Creation Undo remains available
on the card. Save and title Undo never recreate a missing item.

Saved titles refresh the current card/StoredCard, when the chat opens, and when
Open's full editor closes. Alarm hour/minute, weekdays, isOn, createdAt, snooze and
sound are not assigned by title editing. Reminder due/planned/repeat are not
assigned. Local events stay local; linked events edit the existing EventKit title
with thisEvent scope, preserving the current Calendar fields. Full AlarmEditor
is deliberately not used for title-only edits because it also enables/rebases an
alarm on Save.

Stable accessibility IDs: capture-title, capture-title-field,
capture-title-save, capture-title-cancel. The sheet uses native Form, semantic
fonts and adaptive colors. Compact pending rows still expand the existing preview;
the expanded title then opens this shared editor.

Source review found and resolved two EventKit write risks: accidental creation of
Calendar copies for local events, and overwriting remote date/repeat fields via
the general save function. No additional broad review round was run.

## Verification status

- git diff --check passed.
- Four focused logic methods added in CaptureTitleCleanupTests, with permanent
  inline inputs cataloged in tests/fixtures/README.md.
- Three targeted UI methods added in AskCardStaysTests: reported title/time,
  pending title Save/Cancel/Add, Added alarm Save/Cancel/actual-item/reopen/Undo.
- Swift, build and UI execution pending coordinated resource release. No actual
  FoundationModels generation or physical-device evidence is claimed.

## Distinct followups and production pipeline

- `05ea0d9`: request syntax cleanup and title editing. Standard simulator on
  integrated `dc51a26` (same application inputs as `2e71f8e`) passed all three
  selected methods, 0 failures, 106.6 test seconds. Complete evidence:
  primary `tests/results/runs/compatibility-header-integrated-20261018/standard-ai/`
  (`ui.xcresult`, `ui.log`, `summary.json`; journal_errors empty). This binary did
  not contain the later filler, missing-time gate or semantic changes. Runner
  shutdown succeeded; live simctl confirmed Standard Shutdown and DD returned.
- `5b748b2`: additional owner-reported 18:00 temporal filler, preserving negation.
- `6dfada8`: pending alarms without time have disabled Add and a defensive guard
  in AskView.commit; no invented time and no demotion to a reminder.
- `21a09fe`, `c404593`: new semantic scope after the second screenshot. The prior
  single-item path used a parser title and optional Foundation Models KIND
  classification; changing the multi-item AICapture prompt alone could not make
  single-item titles semantic. The new `AICapture.refineTitle` API invokes one
  title-only on-device generation with a 4-second bound. The context-routing
  task owns its single final Understander.parse hook; both changes must integrate
  before claiming the new single-item path is production-used.

The new generator has no date, time, type or recurrence fields to return. It
retains the original user request verbatim in optional Capture.notes, so concise
paraphrasing does not discard the sleep-score motivation or original modality.
Notes map into OneTask.note and additive default-empty OneAlarm.note/OneEvent.note;
old StoredCard Capture JSON decodes without notes. The preview and existing Open
editors display retained context. The fallback is explicitly conservative: split
an explicit motivation clause into notes, with a narrow positive watch/sleep
normalization. It is not a general semantic model. Source review found an
opposite-purpose normalization risk and added a positive-intent/negation guard
plus a permanent regression.

`CaptureTitleCleanupTests` now includes injected production-generator output,
model unavailable, timeout/late-result rejection, scheduling invariance and old
Capture decoding seams. These do not establish actual Foundation Models quality.
`CaptureTitleQualityExportTests` consumes the permanent PR #67 frozen fixture,
only the watch/sleep/no-eating development subset, and exports actual fallback
content to canonical evidence. It does not read expected answers or execute
reserved cases. Host-only observations leave UI gates and persisted pre-confirm
writes null/unmeasured. Foundation Models remains unmeasured unless executed on
an available device; simulator success is not model-quality evidence.

## Executed focused logic and development content observations

At `c404593`, the shared-mutex `swift test --jobs 2` filter ran eight
CaptureTitleCleanupTests and six LedgerFormatTests: all 14 passed. The exporter
failed its own split check: suggested `no-eating-zh` is reserved, so it was not
executed. Its selection was corrected to development `no-peanuts-en` in
`3afab1a`; one accidental unchanged exporter retry caused by a wrong working
path is retained, followed by the corrected exporter passing. No passing logic
suite was repeated. The actual development output then revealed that allergy
context remained in the title and notes was null. `9b6ea3c` moves that explicit
reason into verbatim notes and preserves the negative action as `Do not eat
peanuts`. Only the affected fallback method and exporter were rerun: 2/2 passed.
The production title/timeout/availability/invariance/backward-decoding checks
passed; this remains host logic evidence, not Foundation Models generation.

All command logs and raw observations are under primary
`tests/results/runs/capture-title-logic-20261018/`. `logic.log` records the
original 14-pass plus exporter failure; `export-repaired.log` retains the
unchanged failed retry; `export-final.log` records the repaired exporter pass;
`semantic-reviewed.log` records the final 2/2 pass. Completed evidence is indexed
by path/hash in the QA journal.

Frozen development content results (actual production parser/offline refinement):

- watch-sleep-zh: `佩戴Apple Watch记录睡眠`, 21:00, original request including
  sleep-score motivation retained in notes.
- must-sleep-zh: `必须要睡觉`, 23:00, urgency retained in title.
- no-peanuts-en before: `not to eat peanuts; I am allergic`, 12:00, notes null.
  After `9b6ea3c`: `Do not eat peanuts`, 12:00, original allergy request in notes.

The raw before/after artifacts are retained in `fallback-development-final/`
and `fallback-development-reviewed/`, with app SHA and backend attribution.
Their reviewed observation adapters omit only unobservable UI gate and persisted
write fields. They keep observed title/time/notes unchanged, including the earlier
null notes. The original scorer red report is preserved. Attributed content
review records the old allergy notes gap as an observed semantic failure;
after repair the three observed content outputs each satisfy the five content
dimensions. Overall turn status remains unmeasured because UI gate/writes are
unknown; Foundation Models quality and reserved validation remain unmeasured.
The host executor never reads expected titles or executes reserved inputs.

Production single-item activation depends on PR #69's Understander final-result
hook. A combined incremental app build and targeted UI on the new semantic/notes
revision remain pending with the compatibility coordinator. The old 3/3 UI result
must not be generalized to these followups. No physical device was installed or
used by this task.
