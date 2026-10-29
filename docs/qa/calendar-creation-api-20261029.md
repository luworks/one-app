# Explicit calendar creation prerequisite

Baseline: `71420e5ef6029a5508870f4fc4a5120ee7894b08`.

After the user's explicit Save confirmation, call
`try calendar.create(draft, calendarID: selectedID)` through `CalendarService`.
Pass nil for the existing default-calendar path. Filter `calendars()` using
`allowsContentModifications` for a destination picker; the live adapter validates
again at commit time. Hidden calendars remain valid explicit destinations.

The receipt is `.localOnly` when sync is disabled and no system calendar was
selected, or `.committed(externalID:)` after EventKit's committing save returns.
Missing/read-only selections throw without falling back. EventKit errors propagate.
The API rejects drafts with an external ID and does not mutate or persist the
local model. The composer must persist the returned ID and local model, keep a
recoverable draft on failure, and show success only after its local save succeeds.
This API is not a cross-store transaction and adds no background authority.
Existing save/edit/recurrence/invite paths and native editors are unchanged.

Coverage added: host logic tests for default/selected resolution, invalid targets,
commit errors, missing receipts and disconnected behavior; iOS contract test for
mock dispatch, destination validation, failure/retry and draft identity.

Local verification: `./dev format` and `./dev format --check` passed.
`./dev test unit --only TodayTests/CalendarCreationTests` could not start because
another task holds `host-heavy.lock`. `./dev lint` could not start because the
verified swiftlint tool is missing. Normal PR CI supplies unit and native compiler
checks. The new iOS integration test is compiled by normal CI; execution requires
a later explicit integration lane. No local native build, simulator UI or phone
work was performed. Actions are recorded in the primary checkout QA journal,
session `calendar-creation-20261029`.
