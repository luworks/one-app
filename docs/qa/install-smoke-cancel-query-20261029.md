# Install-smoke diagnosis, 2026-10-29

Verified origin/main ce6de43d56041316f68e3c519d73802cede76ef3. Hosted run 40944969567 tested b31ad6e264879672d0b9c242e1f70f607ee972b4 and failed in 255.825 s.

Imports: native reminder/apple/app/persisted open state and imported event presence passed. Reminder editor task.title appeared after the user touch. Cancel resolved via its label to identifier xmark. The subsequent frame resolution failed with an AX matching-snapshot timeout; retry/diagnostic work consumed most of the run. Failure hierarchy contains a visible Button with label Cancel, identifier xmark, frame {24,286,44,44}.

The spindump samples TodayMock main thread in its event loop/mach_msg for 230 samples (0.006 s CPU). Test-runner stack is in readyCoordinate -> XCUIElement.frame -> resolution failure diagnostics, then waiting for its spindump. This does not establish a product main-thread deadlock, nor does it prove the entire preceding interval was responsive. Exact underlying hosted AX failure remains UNKNOWN.

Bounded change: add task.cancel identifier to the existing compact Cancel control; use that exact identifier in the regression. Preserve isHittable, visible-frame checks, real touch, task.title removal, <10 s combined response, all four tabs, native imported event/reminder presence and exact unsent Chat draft checks. Local runner explicitly grants Calendar and Reminders only for this preconnected method, propagating grant failures.

Local setup: generated project/dependency lock through ./dev; one attempt stopped before building for missing workspace lock, another compiled successfully but correctly rejected publication because source changed during build. Both executed zero UI methods. Final frozen-source execution uses the same cache and owned Today-Dev-39fea6f8, iPhone 18 Pro Max / iOS 27.0. Hosted uses iPhone Duo / iOS 27.1; local is comparable, not identical. Device panel could not discover the new simulator after following its refresh advice; no alternative manual control session was opened.

Full hosted artifacts retained and hash-verified under QA journal session install-smoke-hosted-40944969567. No phone, API calls, signing or backend work. Final hosted acceptance still required on the consolidated main SHA before installation.

## Validation

`./dev test ui --only TodayUITests/TodayReminderCompletionTests/testPreconnectedImportedTimelineStaysResponsive --timeout 600`: 1/1 passed, 99.271 s test duration; editor open 3.175 s, cancel 2.129 s, combined response 5.304 s < 10 s. Exact identifier frame resolution took 0.422 s for cancel preparation. All native-import, navigation and unsent-draft assertions passed unchanged. Full run including incremental build and cold simulator setup: 227.883 s.

Durable UI evidence: primary `tests/results/runs/today-qa-20261029-132634-dffc8cad/` (complete xcresult, UI/build logs, summary, journal). Hosted diagnosis: primary `tests/results/install-smoke-repair-20261029/`; hash-verified archive indexed under `install-smoke-hosted-40944969567`.

`./dev test helpers` passed with the exact-grant/failure-propagation regression included; `./dev format --check` and `./dev lint` passed. No full suite or physical-device validation. The local pass supports the bounded selector repair; hosted failure elimination remains unverified until final same-SHA main install-smoke passes.
