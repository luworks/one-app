# Local Docker and native phone delivery, 2026-10-19

Yuan explicitly authorized local Docker portable checks plus Mac Xcode native
acceptance for this delivery, normal pushes/merges, and an in-place manual
phone installation. This authority does not create a GitHub main acceptance
receipt, disable a branch rule, change the default release preflight, or authorize
a permanent alternative installer. The existing manual devicectl command is used
only after the fixed critical leaves, exact source/toolchain and three signed
production identities have been reconciled in separate `origin: local` evidence.

Persistent evidence and the QA journal are in the primary checkout:
`tests/results/local-docker-native-phone-20261019/` and `tests/results/activity.sqlite`.
The final SHA, product hashes, completed checks, installation and launch remain
separate records there; an installation/PID is not physical interaction acceptance.
No uninstall, reset, user-data inspection or signing/provisioning change is authorized.

## Portable and native boundaries

The owned ephemeral container uses official `python:3.14.8-slim`, digest
`sha256:a2b82f3c48559aa0a8446d9af49826b6e2b2016f4cd2afabfe6013ec53729170`.
Only clean staged source is mounted read-only, with an owned results mount writable.
Git and procps supply the existing helper collection's actual dependencies.
`./dev test helpers` ran 158 tests successfully. Initial mount, package-permission
and missing-ps failures remain retained, along with image identity, command,
container logs/state/exit and removal. No other repository image, private home,
Docker socket, secret, privileged mode or global daemon setting is used.

Mac Xcode 27.1/27A9275 is selected through process `DEVELOPER_DIR`.
`./dev format --check`, `./dev lint` and business tests passed on the PR123 tree;
business executed 701 with four existing optional benchmark/export skips and
no missing results. Docker does not claim Swift/Apple-framework/Xcode execution.
PR123 merged normally as `38e86891c7094dc2cc4151e237ee38b1e6380558`.
Its first fresh critical integration run passed 3/3 with zero skips/missing/errors.

## Calendar authorization failure and repair

The fresh combined UI method failed before native imports at the Calendar
connection assertion. The original complete result is
`runs/today-qa-20261019-204958-3f4933fc/ui.xcresult`.
Directly tapping the system Allow button instead of the interruption monitor
failed identically (`205425-f8fd45f8`); that experiment was reverted.
A temporary stdout probe was not captured; a subsequent system-log probe
(`205957-d478b012`) established the exact sequence:

```
request on=true auth=0 disposed=false
result granted=true auth=0
enabled=false auth=0
```

The full-access request succeeded while the synchronous status was still
notDetermined. The adapter discarded the successful answer and saved false.
The repair keeps that positive full-access completion only in its current
instance while the status remains notDetermined. Any determined status retires
it; denied, restricted and write-only remain denied. Turning off and disposal
clear it. It is never persisted or supplied by a launch flag. Existing native
read/write validation and failure handling remain in place. Apple's
[full-access request](https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoevents(completion:))
is the source of this positive completion, not a synthetic authorization value.

An optional request closure supplies a deterministic test seam; production still
calls the real EventKit API. The new integration method
`calendarGrantPrecedesStatusUpdateWithoutOverridingRevocation` covers status lag,
refusal/error, denied/restricted/write-only, retirement after known status,
disable, and zero native-store creation. It and all three fixed main integration
leaves passed (4/4, no skips/missing/errors) in
`devtools/logs/439b4eaefd3440a9b700f25430ca43a6-xcode/TodayCI.xcresult`.
The real combined import/navigation/editor-cancel/native-unsent-Chat/Close leaf
remains mandatory; this deterministic regression is not its substitute.

The original nine models, `One` module and store paths remain. The accepted
9043647 rollback artifact is retained. Physical checks must avoid creating,
changing or deleting user items, scheduling alarms, or reading private Health
content. If physical touch control is unavailable, owner-assisted navigation
must be reported separately and cannot be inferred from installation or launch.
