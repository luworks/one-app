# GPT-6 Luna migration boundary

Owner direction (2026-10-29): replace Apple Foundation Models with GPT and compare
low, medium, high and xhigh with a total paid evaluation budget below USD 0.50.

The synthetic comparison is separate from the app migration. The current app has
model calls for uncertain-kind classification, title refinement, chat response,
edit selection and suggestion ranking. Rules, local validation, confirmation,
EventKit commits, Activity receipts and Undo remain authoritative.

A shared OpenAI API key must remain on a server. No production AI endpoint or
mobile authentication configuration was found in this checkout. The owner has
been asked whether an existing backend is available. Integration needs that
endpoint/authentication contract or a new backend deployment, plus a clear
product explanation of which chat/context fields leave the phone. Do not embed
the evaluation key into an application build or silently upload full local data.

The replacement should use a single bounded typed Responses adapter, fixed
server-side model/effort, authenticated clients and server-side per-user quotas.
Pass only the context needed for each operation. Model errors return to the
existing local rules; Apple model calls must not remain as a hidden fallback.
Keep IDs in the supplied candidate set and preserve all existing Add/Apply and
one-off reminder authorization boundaries. Request cancellation and timeouts
must cancel the network task; record usage without chat text by default.

Acceptance needs CI checks plus explicitly scoped app journeys for chat,
capture, title, edits, suggestions, unavailable network and malformed responses.
Standalone API accuracy is not evidence of app writes or phone usability.
