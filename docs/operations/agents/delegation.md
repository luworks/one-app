# Delegating authorized Today work

Use [Zhugeliang](zhugeliang.md) for authority and patrol decisions. A work package states the original goal/Issue, latest steering, scope, owner, acceptance endpoint, existing authorization and evidence location. Give one writer ownership of each change; retain existing owners and keep unrelated worktrees untouched.

## Autonomy and tools

Workers own implementation, focused regression checks, ordinary repairs, PR creation, required review responses and authorized merging through the actual endpoint. Do not split work into prepare/approval/start gates or wait for the root to choose ordinary technical details. Do not invent formal receipts, extra review gates or evidence requirements.

Discover live provider/model IDs through `orchestrator_capabilities`. Explicitly select GPT 6.1 Sol with medium reasoning when available, as the owner's default; if unavailable, record the actual capability gap rather than installing routing infrastructure or silently claiming that model ran. Use native subagents for same-provider work only when they support the chosen model. Use T3 `delegate_task` for cross-provider or T3-owned work, and for any task needing `isolation:"worktree"`. Parent uncommitted changes are not copied into that checkout.

A delegated task is child work. `t3_thread_launch` / `create_threads` create top-level conversations and require an explicit request for separate/new conversations; “subagent” alone does not authorize them. Keep returned `taskId` values and use `task_status` / `task_cancel`. Use a distinct `clientRequestId` for each new task/round and the same value for retries of that round.

Every independent review round uses a new `delegate_task`, including the original brief, prior findings, responses and unresolved objections. Never use `t3_thread_send` on `childThreadId` to continue a review. Unfinished delegated work also gets a fresh task with the completed and remaining portions; ordinary continuation of an existing top-level conversation may use `mode="auto"`.

## Shared resources and checks

Default to the AGENTS single UI runner rule. The owner's explicit current allowance permits compatible parallel work, with host capacity of about three heavy runners at most, subject to actual load; this is a ceiling, not a target or permanent entitlement. Each runner owns its named simulator UDID and derived-data directory. Preserve real mutual exclusion for a UDID, derived-data path and conflicting build/test processes; avoid duplicate builds and cold boots.

The existing performance lead coordinates actual contention and measurement windows. Workers coordinate necessary dependencies directly with that owner. The root does not issue five- or ten-minute micro-windows or approve each phase. Continue independent work while a real resource is unavailable; do not replace a healthy performance or preview owner.

Choose the smallest meaningful checks under AGENTS. Reuse passing evidence that still applies; rerun only for a concrete changed risk. Preserve assertions when repairing a shared helper/selector failure. State build, logic, simulator UI and device evidence separately, and identify unchecked behavior. An ordinary documentation change needs manual diff/link checks, not app builds or tests.

## Delivery records

Keep routine progress and blockers in the worker's thread/PR for root patrol, without proactive root messages or requested acknowledgments. Automatic platform notifications stay enabled. Record development actions and Issue/PR links through `tests/qa/journal.py`; retain generated evidence in the primary checkout's `tests/results/`. Commit compact summaries and reusable fixtures, not private runtime databases or large artifacts.

Link each PR created or worked on using `link_pull_request` immediately when available; verify with `list_thread_pull_requests` before handoff. Use T3's PR watcher when asked to monitor and available, rather than a polling loop; unwatch before returning ownership to the user. Merge under actual repository requirements, without an invented CI or mandatory extra agent. A blocked permission remains blocked until authorized; waiting does not authorize it.
