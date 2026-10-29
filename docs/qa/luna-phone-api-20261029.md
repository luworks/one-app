# Luna phone API readiness — 2026-10-29

Backend deployed: `https://today-luna-api.1031luy.workers.dev` with dedicated D1 and
server-only shared key. App source now includes the HTTPS endpoint and actual
Settings → AI → Luna AI registration/sign-in/session/consent/usage controls.
No generic client token, OpenAI key, account credential or signing change is bundled.
Per-user quotas and session revocation are implemented; no Apple model fallback.

Real HTTPS acceptance completed on synthetic data: health200; unauthenticated
Responses401; registration200; login200 with a distinct bearer; GPT-6 Luna medium
Responses200/completed (66 input,53 output including35 reasoning tokens); session
usage1/40; logout200 then401; account deletion200 then401. Successful model round
trip:3.431 seconds. A second synthetic user at daily quota40 received429 on seven
HTTPS attempts, with zero model calls and no global-budget change. Both test users
and sessions were deleted. No personal planner or health data was sent.

D1 global accounted spend is USD0.023985 including the exact prior conservative
USD0.023951. Ceiling remains USD0.50. Production operating budget is not expanded.
See backend/luna/README.md for the account, quota, consent and API contracts.

Offline workerd/D1 tests exercise wrong credentials, distinct sessions, revocation,
account deletion, cross-user quota independence, daily denial, unknown-charge
reservation and concurrent global-budget admission. npm audit reports zero known
vulnerabilities after pinned dev-tool security overrides; production Worker imports
no npm packages. Repository lint/helpers run locally. Full iOS compilation belongs
to hosted CI, and root retains final same-SHA install-smoke + phone installation.

Read-only review found two client recovery issues and both were corrected: server
401 cannot trap an old login, and delayed usage responses cannot overwrite a newer
session. No separate hosting/account/secret blocker remains. Remaining acceptance:
hosted app build/CI and root-owned real phone sign-in/network interaction. Do not
label backend HTTP success as completed phone usability or installed readiness.
