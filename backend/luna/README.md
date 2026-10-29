# Today Luna API

Phone clients use `https://today-luna-api.1031luy.workers.dev/v1/responses`.
The app includes this public HTTPS URL, never the shared OpenAI key. Settings → AI →
Luna AI provides account creation/sign-in, explicit cloud-upload consent, daily usage,
cloud-AI disable, sign-out and AI-account deletion. Username/password accounts are
independent of the user's Apple/OpenAI accounts. Password recovery is not implemented;
the initial-rollout screen states this before registration.

The Worker is deployed in the owner's existing Cloudflare account; its dedicated D1
ID is in `wrangler.jsonc`. Existing Workers, account plans, DNS and signing are untouched.
`OPENAI_API_KEY` is a Worker secret uploaded from the authorized local key file using
Wrangler stdin; it is neither a plain-text binding nor a source/config/bundle value.

## Contract

| Route | Method | Authorization / result |
| --- | --- | --- |
| `/health` | GET | Non-secret readiness/model/effort |
| `/auth/register` | POST | Username + password ≥12 characters; issues a unique random session |
| `/auth/login` | POST | Valid password; issues a new unique session |
| `/auth/session` | GET | Bearer; username and daily call usage/limit |
| `/auth/logout` | POST | Revokes this bearer |
| `/auth/account` | DELETE | Deletes this AI user and all their sessions; local planner data remains |
| `/v1/responses` | POST | Bearer; bounded strict-schema Responses request |

Passwords use per-user random salt + PBKDF2-SHA256 (100,000 iterations). Random
256-bit sessions expire after 30 days; only their SHA-256 hashes are stored server-side.
Mobile sessions use Keychain, WhenUnlockedThisDeviceOnly. A disabled cloud toggle
prevents model authorization but still permits session management. Revoked/expired
sessions return the UI to sign-in; stale usage responses cannot republish an old login.
Offline sign-out clears local credentials and states that remote revocation is unconfirmed.

Requests are limited to24KB total,8KB instructions and12KB input, enforced by both
mobile transport and server. The existing feature-specific prompts and bounded context
remain authoritative; do not upload whole local data stores. The server fixes
`gpt-6-luna`, medium reasoning, store=false and4096 total output tokens; no tools,
model substitution, redirects, automatic retries or Apple fallback. D1 stores account
credentials/session hashes, counters and accounting metadata, not chat or planner text.

## Quotas and evaluation budget

Atomic D1 counters enforce6 calls/minute and40 calls/UTC day per user. Signup is
limited to100 active accounts and3 registrations/day/IP; login is rate limited per
IP and username. Account deletion does not refund global model spending. A message
can use multiple calls, including optional suggestion/title requests.

The global table starts with the exact prior conservative evaluation spend
USD0.023951 and a **USD0.50 cumulative ceiling**, preserving the owner's validation
budget. Before each model request, reserve USD0.01 atomically; after a valid usage
receipt, replace the reservation with conservatively rounded token cost. Unknown
outcomes keep their reservation across restarts. Denied calls never reach OpenAI.
Never reset the table, recreate the database or raise the ceiling to bypass the cap.
An ongoing production allowance beyond this bounded rollout needs a separate owner
budget decision; this implementation does not authorize one.

## Verification and operations

`npm ci && npm test && npm audit --audit-level=high` runs offline workerd/D1 tests
with no paid API calls. The production module has no npm runtime dependencies.
Pinned dev dependencies and security overrides are in package-lock.json. The local
Miniflare test compatibility date is2026-07-30 (its stable runtime); deployed Worker
compatibility is2026-10-29. No date-specific Worker feature is used.

`python3 smoke.py --output <fresh-private-results>/https-e2e.json` performs one paid
synthetic request after registration/login, verifies usage, logout and deletion,
and always attempts deletion of its synthetic account. It refuses to overwrite a
receipt and never prints passwords/tokens. Requests identify the client honestly as
TodayAPISmoke; the default Python-urllib user agent is rejected by Cloudflare1010.
The app uses Today-iOS as its client identifier. No Cloudflare security setting was widened.

Deployment uses the existing authorized Wrangler profile, `wrangler d1 execute DB
--remote --file schema.sql` and `wrangler deploy`. Schema is additive/idempotent;
its INSERT OR IGNORE never resets existing accounting. Upload secret values through
private stdin, never command-line literals or committed files. Reapply no schema or
secret unless required by a reviewed change.

Retained evidence: primary checkout tests/results/luna-production-20261029/:
`https-e2e-v2.json`, `https-quota.json`, redacted secret-upload.log. E2E observed distinct
sessions, one real GPT medium response, usage1/40, logout→401, delete→401 and test-user
cleanup. A second synthetic account was saturated through the admin-owned D1 counter;
seven real HTTPS calls returned429, zero paid calls were created and budget stayed
unchanged. Both synthetic users/sessions were deleted. No phone install/UI test was run
by this implementation owner; root owns same-SHA CI/smoke and phone acceptance.
