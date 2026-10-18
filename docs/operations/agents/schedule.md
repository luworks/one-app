# Root patrol schedule: descriptor and deployment status

[Zhugeliang](zhugeliang.md) owns the method; [delegation](delegation.md) owns worker behavior. This file describes the authorized cadence and prompt. It does not create a schedule or prove a live worker exists.

## Authorized configuration

The owner's current Today root is the single controller. Desired interval: **20 minutes**, T3 structured schedule `{"type":"interval","everyMs":1200000}`. Bind it to that existing root; do not create another Zhuge thread, timer or optional-role schedule. Only the root configures the live T3 schedule after these documents reach `origin/main`. The docs worker must not schedule anything.

Keep full runtime configuration, root identity, task ID, enabled state, prompt version, actual readback and run evidence privately in the primary checkout's `tests/results/`, indexed through `tests/qa/journal.py` in the root's canonical `steward-setup` session. Do not commit raw T3 configuration or private thread inventory. Back up an existing configuration, reread before changing it, preserve unrelated fields, then read back the result. An ambiguous response requires inspection before retrying.

## Readback status at documentation delivery

Live Today schedule setup/readback is pending the root's action. No task ID, next-run timestamp, enabled state or successful patrol is asserted here. The owner's supplied pre-edit observation was `tasks: []` for both the one-app and job-finder T3 projects; this worker did not independently query or change their schedules. That snapshot is not a claim about later live state.

The requested source path `doc/operations/agent-governance/zhugeliang-schedule-history.md` is absent from job-finder `origin/main` revision `75ba51af7f6a31a72109a4f1cd9fd3fe4f34d8f7` (`git show` reports it is not in that revision). Its presence in a local checkout is not source authority. The source's current coordination references describe historical Codex heartbeat and retired Ubuntu-specific supervision; the owner identifies the historical cadence as 20 minutes. Neither history nor those files establish an active T3 scheduler. Do not restore old job-finder tasks or copy their historical state, private data or host rules.

## Prompt draft for the root

Keep the live prompt compact: document entrypoints, authorized scope, hard boundaries, stopping conditions and reporting only. Put changing progress and handles in the private setup/state record, not in an ever-growing prompt.

```text
Fetch origin main, then use git show origin/main:<path> to read
AGENTS.md, CLAUDE.md, ios/README.md, and docs/operations/agents/{zhugeliang,delegation,team,schedule}.md.
Do not overwrite dirty or active worktrees. If loading fails, record the gap.
Act as this existing Today root's sole coordinator under the latest owner steering.
Recover original goals and the private steward-setup state; inspect compact activity,
known subtasks, new project threads and actual relevant PR/Issue states with bounded reads.
Follow the loaded patrol and delegation policy: root coordinates/read-only;
implementation, tests, heavy diagnosis and integration are delegated. Keep healthy
owners, deduplicate queued next steps, resume concrete unfinished authorized work,
and settle only at its real endpoint. Never revive paused/completed goals or add backlog.
Workers retain evidence in their own threads/PRs; preserve platform notifications.
Respect existing resource ownership and actual capacity. No heavy patrol tests,
redundant passing checks, CI loops, unsolicited installs or production actions.
Keep real permission gaps blocked. On owner pause/cancellation stop the affected work;
when all current endpoints are met, record completion and disable this supervision.
Record only useful changes in the private QA journal/state. Quiet check: one local
line, "Patrol: no change." Notify the user in Chinese only for material changes,
failures or concrete decisions. No acknowledgments or formal no-decision footer.
```

The shell must expand the four documentation paths individually; braces above are prompt shorthand, not a literal `git show` path. Git history/PRs carry policy revisions; private readback carries deployment truth. Configuration accepted, schedule enabled, patrol executed and effective supervision are separate states.
