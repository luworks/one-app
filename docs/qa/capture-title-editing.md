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
