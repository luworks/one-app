# Activity data store: what to record, where to keep it, how it grows into iCloud

Research date 2026-10-17. Research only: no app code was changed. Scope: the Activity screen's data (`LedgerEntry`, `Ledger.swift`, `LedgerLogic.swift`, `AutonomyPolicy.swift`, `ActivityView.swift`) and the larger "record everything the user and the AI do" store that the owner wants to build on top of it.

## 中文摘要

结论：现在不要上 CSV，也不要上 iCloud。先在 App 自己的容器里建一个独立的 SQLite 文件（`activity.sqlite`，只追加的事件表，WAL 模式，带索引，用系统自带的 SQLite，不加第三方依赖），把现有账本、AI 对话与卡片决定、使用行为、系统事件分成四层记进去；Widget、Share 扩展不直接写数据库，只往 App Group 里丢小 JSONL 文件，App 启动时再收进来。CSV 只作为"导出给人看"的格式，JSONL 作为导出和日后同步的格式。数据表一开始就按 CloudKit 的要求设计（UUID、设备 id、不可变行、JSON 属性），等有了付费账号，只同步第 1、2 层，用 `CKSyncEngine`，不用 SwiftData 的 CloudKit 同步。免费 Apple ID 完全不能用 iCloud/CloudKit（Apple 能力表已核实），所以第一阶段纯本地：存储 + 记录器 + AI 卡片/建议的事件 + JSONL 导出，一个 agent 一天能做完；设置页（暂停、清除）、CSV 导出和真机测速放在 1b（再约一天）。

---

## 1. Conclusion

Keep a **separate, app-private SQLite file** (system `SQLite3`, WAL, `user_version` migrations, no third-party dependency at first) as the Activity store, with one narrow append-only `event` table whose rows are immutable, carry a UUID and a device id, and keep free text in dedicated columns so it can be redacted, exported or left out. Move the existing SwiftData `LedgerEntry` into it in two steps (dual write, then cut over), and keep `AIGrant` and every planner model in SwiftData. Do not use CSV as the store, and do not sync through SwiftData+CloudKit: the free Apple ID cannot use iCloud at all, and a SwiftData sync would also push 100k+ usage rows we do not want in the user's iCloud. When the paid account arrives, sync only tiers 1 and 2 (changes, AI decisions) with `CKSyncEngine` into a private zone, with encrypted fields; usage and system events stay on the device. Anything sent to the product team ("desensitized data may be uploaded later") is a separate, explicit, later pipeline that does not exist today and cannot read the user's private iCloud.

Five-line version:
1. Store: separate `activity.sqlite` in the app container (not the App Group); SwiftData keeps planner data only.
2. Extensions (Share, widgets) never open the database: they drop JSONL files in the App Group; the app drains them (the `ShareInbox` pattern the project already uses).
3. CSV: export only. JSONL: export, outbox and future sync payload. SQLite: the store.
4. iCloud/CloudKit: impossible on a free Apple ID (verified), planned for the paid account as `CKSyncEngine` over tiers 1+2; the schema is CloudKit-ready from day one.
5. Phase 1 (one agent, one day, free account): `ActivityStore` + recorder + tier 2 events + JSONL export + `swift test`; Phase 1b adds the Settings page, CSV, tier 4 events and device benchmark. The ledger and Activity screen stay untouched until Phase 2.

### Decisions already taken by the owner (this document follows them)
- Local storage only until the paid Apple Developer account exists; no iCloud work now.
- Privacy is not the design focus: the product states what it records and where it lives (in-app note plus the Activity screen), with pause, clear and export as cheap basics. Section 7 is deliberately one page.
- Product improvement: most data stays on the user's side (device, later their iCloud). Redacted data may later be uploaded to the product team. This is a later phase and a later decision (section 7.3).

---

## 2. What to record

### 2.1 Four tiers

| Tier | What | Examples (`kind`) | Personal content? |
|---|---|---|---|
| 1 Changes (exists) | The ledger: who changed what, when, before → after, approval, Undo | `change.created`, `change.completed`, `change.moved`, `change.undone`, `grant.granted` | Yes: title, before, after (task/event names, times). Delete snapshots contain the full reminder |
| 2 AI conversation and decisions | Turns, routing, cards shown vs applied, chips shown vs tapped | `ai.turn`, `ai.card.shown`, `ai.card.resolved` (applied / cancelled / edited), `ai.chips.shown`, `ai.chip.tapped`, `ai.undo` | Metadata by default. Chat text already lives in `ChatThread`; the event stores `thread` id, lengths, language, route, never a copy. Edited-card diffs (field, before, after) are the one text-bearing record, kept in a content table with its own retention |
| 3 Usage and interaction | Screens, gestures, quick-add, durations | `ui.screen.open`, `ui.gesture.swipe_action`, `ui.menu.choice`, `ui.quickadd.start/commit/cancel` (with `ms`), `ui.search` (length and result count only) | Metadata only. No titles, no search text |
| 4 System and agents | Things that happen without a tap | `sys.sync.pass`, `sys.sync.conflict`, `sys.intent.run`, `sys.share.import`, `sys.widget.refresh`, `sys.permission.changed`, `sys.error` | Metadata only. Error text is stripped of titles |

### 2.2 Common envelope and tier-specific fields

Every row has: `uid` (UUID), `ts` (unix ms UTC), `tz` (minutes east of UTC at write time), `day` (local yyyymmdd at write time, so grouping survives a time-zone change), `tier`, `kind`, `actor`, `channel`, `session` (app launch id), `v` (schema version of that kind), `props` (JSON, no free text).

Per tier, the extra fields:
- Tier 1: `subject_kind`, `subject_ref` (reminder id), `approval`, `title`, `before_txt`, `after_txt`, `before_ts`, `after_ts`, `undo_of`; Undo `snapshot` in its own table.
- Tier 2 `props`: `route` (foundation-model / rules), `lang`, `len_in`, `latency_ms`, `model`, `prompt` version, `items_proposed`, `kinds`, `ranked_ids` for chips, `edited_fields`, `dwell_ms`.
- Tier 3 `props`: `screen`, `gesture`, `ms`, `taps`.
- Tier 4 `props`: `source`, `outcome`, `count`, `error_code`.

### 2.3 Size and volume (estimates)

Current policy: raw events default to Forever across all tiers; the finite-period behavior and 30-day Undo snapshot window are described in `ios/README.md`. The table below is the original sizing proposal, not the current retention policy.

Basis: a heavy active day (about 8 app opens). Row size basis is the measurement in section 3.2: 156 bytes per row for an 11-column row with three indexes at 1M rows (about 40 bytes of title). Rows with more JSON or text are taken as 200 to 300 bytes. Counts per day are my estimates, not measured on real usage; Phase 1 should log real counts for two weeks and replace these numbers.

| Tier | Events / active day | Bytes / event | Rows / year | MB / year (raw) | Retention proposal |
|---|---|---|---|---|---|
| 1 Changes | 40 | 300 (delete snapshots about 1 KB, 3 per day) | 15k | 5 | 1 year (today 90 days); delete snapshots after 30 days (Undo is stale by then) |
| 2 AI decisions | 80 (15 turns × about 4 records, plus chips) | 250 | 29k | 7 | 180 days of rows; edited-card text 180 days; daily rollup kept forever |
| 3 Usage | 500 | 130 | 180k | 24 | Raw 30 days, then `rollup_daily` forever (about 2 MB per year) |
| 4 System | 50 | 200 | 18k | 4 | Errors and conflicts 90 days; counters rolled up forever |
| Total | about 670 | | about 240k | about 40 MB raw | Steady state after retention: about 15 to 20 MB |

At three times heavier use, 1M rows is reached in about 1.4 years of raw data, which the store handles (section 3.2). Forever retention does not roll up or prune raw events, so storage continues to grow.

Steady-state cost on the phone is small. The cost that matters is write frequency (battery), so events are batched: the recorder buffers in memory and commits every 1 to 2 seconds or on backgrounding, in one transaction.

---

## 3. Storage options for this app

### 3.1 Comparison

Scale used below: Activity needs day grouping, filter by actor or tier, "Show more" paging, text search over titles, group-by aggregates for learning loops, and Undo lookups by reminder.

| Option | Write throughput | Activity-screen queries | Migration / schema evolution | Extensions (widget, Share, Intents) | Size / battery | Pure-Swift tests | Multi-device / conflicts | Verdict |
|---|---|---|---|---|---|---|---|---|
| (i) Keep SwiftData `LedgerEntry`, extend | About 13.6k rows/s (measured, batch 1000, Mac) | Fetch + sort + predicate fine; **no group-by**, aggregates mean loading objects; `fetchOffset` ok | Lightweight migration for added optional fields; ok | Widget and Share must not open the store (already the rule); Intents run in the app process | Fine to about 100k rows; every row materialises as a model object | Model needs SwiftData, so only the logic is testable under `swift test` (as today) | `LedgerEntry` has non-optional properties without defaults, so it cannot join CloudKit as is | Fine for tier 1 alone; wrong for tiers 2 to 4 |
| (ii) SwiftData + CloudKit private DB | Same as (i) plus sync cost | Same | CloudKit schema is additive-only once in production; no unique attributes, relationships optional | Needs iCloud + Push + Background Modes | Would sync every usage row to the user's iCloud | Same | Last-writer-wins per record; fine for append-only | **Blocked on free Apple ID** (verified); wrong shape for tier 3 even when unblocked |
| (iii) Separate SQLite file (system SQLite or GRDB), WAL, indexes, optional FTS5 | About 270k to 330k rows/s with 3 indexes (measured) | Index seek on `(tier, ts)` in under 0.1 ms; group-by and rollups in SQL | `PRAGMA user_version` + ordered migration list (GRDB `DatabaseMigrator` if adopted) | App-private file; extensions use outbox files (below) | 156 B per row at 1M rows; short batched transactions | Plain `swift test` against `:memory:` or a temp file; `import SQLite3` works on macOS and iOS | Append-only immutable rows with UUIDs merge by union; sync is a separate layer (`CKSyncEngine`) | **Recommended** |
| (iv) Core Data | `NSBatchInsertRequest` is faster than object inserts (not benchmarked here) | Group-by via `propertiesToGroupBy`; clumsy | Mapping models, heavy | Same sharing hazards as any SQLite | Same engine as SwiftData | Needs Core Data stack | `NSPersistentCloudKitContainer` has the same constraints as (ii) | Adds a second persistence stack for no gain |
| (v) Append-only JSONL files (Parquet not available natively on iOS) | Very high (one `write`), nothing to index | Reading the last page is easy; filters, search, group-by and Undo lookups need a full scan or an index you build yourself | Excellent (new keys are ignored) | Safe if each writer owns its own file | Grows linearly; scan cost O(N) | Easy | Union merge; file per device per day avoids merge conflicts | Best as **outbox, export and sync payload**, not as the query store |
| (vi) iCloud Drive documents | n/a | n/a | n/a | n/a | n/a | n/a | File-level conflicts | **Blocked on free Apple ID** (verified). Never put a live SQLite/WAL file in iCloud Drive |
| (vii) CSV | High | Same limits as (v), plus the problems in section 4 | Poor (positional columns) | Concurrent appends corrupt rows | Larger than JSONL for nested data | Easy | Poor | **Export format only** (section 4) |

### 3.2 Measurements (mine, reproducible)

Method: a throwaway SwiftPM executable (not in the repo) on a Mac (macOS 26.6, Apple Silicon, release build, system SQLite 3.51 and the SDK's SwiftData). Rows: 11 columns with title/before/after strings (about 40 bytes of title), batch size 1000, `journal_mode=WAL`, `synchronous=NORMAL`. SwiftData model: the same fields with `#Index` on `date` and `(actor, date)`, like `LedgerEntry`.

| Test | Result |
|---|---|
| SQLite insert, 3 indexes | 1k rows: 455k rows/s; 100k: 271k rows/s (0.37 s); 1M: 327k rows/s (3.1 s), file 156 MB |
| SQLite insert, no secondary index, 1M | 790k rows/s (indexes cost about 2.4x, still fast) |
| SQLite: newest 150 rows filtered by actor, at 1M rows | 0.016 ms (index seek; measures the index walk, not Swift decoding) |
| SQLite: offset 10,000 page of 150, at 1M | 0.195 ms |
| SQLite: group by day over all 1M rows | 290 ms (so aggregates should read rollups or a bounded window) |
| SQLite: one-day count at 1M | 1.8 ms |
| SQLite: `LIKE '%text%'` scan | 13 ms at 100k rows, 379 ms at 1M |
| SQLite: delete oldest 10% (prune) | 14 ms at 100k, 187 ms at 1M |
| SwiftData insert (batch 1000, save each batch) | 1k: 9.5k rows/s; 10k: 13.6k rows/s; 100k: 13.6k rows/s (7.4 s) |
| SwiftData: newest 150 filtered by actor | 2.3 ms at 1k, 10k and 100k (it materialises 150 models) |
| SwiftData: `fetchCount` | 7.2 ms at 100k |
| SwiftData: prune oldest 10% | 34 ms at 100k |

How to read it: a year of the heaviest estimate is about 240k rows. SwiftData would need about 18 s of save time for that on a Mac (a phone will be slower; unmeasured), and it has no group-by. SQLite does the same in under one second. The "page of 150" is fast in both, so the Activity screen itself is not the problem. The problems are aggregates and volume once tiers 2 to 4 are recorded.

Not measured: iPhone numbers, battery, and `NSBatchInsertRequest`. Phase 1 should re-run the insert test on the device.

Chinese text and FTS5 (also measured, 100k rows, half with Chinese titles):

| Tokenizer | Query `milk` | Query `牛奶` (2 chars) | Query `买牛奶` (3 chars) |
|---|---|---|---|
| FTS5 `unicode61` | match | **0 rows** (a run of Chinese characters is one token) | **0 rows** |
| FTS5 `trigram` | match | **0 rows** (needs 3 or more characters) | 50,000 rows |
| `LIKE '%牛奶%'` | n/a | works, 8 to 9 ms scan at 100k rows | works |

Consequence: for this owner's data (mostly Chinese titles) FTS5 is not a fix. Search over the Activity titles (tier 1 and 2 text, roughly 20k to 50k rows a year) should use `LIKE` on a bounded window; add FTS5 `trigram` on the content table only if rows pass about 200k, and keep a `LIKE` fallback for two-character queries. FTS5 is compiled into the Mac's system SQLite; I did not verify it on the iOS runtime (Phase 1 test).

### 3.3 Why a separate file and not the App Group

- GRDB's own sharing guide: "Preventing errors that may happen due to database sharing is difficult. It is extremely difficult on iOS. And it is almost impossible to test. Always consider sharing plain files, or any other inter-process communication technique, before sharing an SQLite database." The cause is iOS killing a process that holds a file or SQLite lock while it is suspended (crash code `0xDEAD10CC`).
- NetNewsWire fixed the same crash by no longer sharing the database: the extension writes a plist in the shared container and the app reads it later.
- The project already follows this pattern (`ShareInbox`: the extension appends `share-inbox.json`, the app imports it when it becomes active).

So: `activity.sqlite` lives in Application Support of the app container (it is included in device backups by default; not re-verified here). Extensions and anything that can run while the app is suspended write **one small JSONL file per write** (atomic write, unique name, no locking) into `group.com.luworks.one/activity-outbox/`. The app drains the folder on activation and on its background refresh, inserts the rows in one transaction, then deletes the files. App Intents already run in the app process, so they use the normal recorder. To stay on the safe side in the app process: transactions are tiny (milliseconds), and each flush runs inside `beginBackgroundTask`.

Free Apple ID check for this design: App Groups, Background Modes and Data Protection are all available to a free account (Apple capability table, section 5.1), and the project already uses the App Group.

File protection: new files in apps default to "complete until first user authentication" (documented behaviour; I could not re-fetch Apple's page to quote it). Set it explicitly on the database directory and outbox so a write while the phone is locked after first unlock still works.

### 3.4 Pure-Swift testability

Put the pure parts in `ios/One` files that the existing `OneEval` package already compiles (like `LedgerLogic.swift`): event kinds, envelope, retention rules, redaction, rollup rules, export encoders, outbox parsing. The SQLite wrapper (`ActivityStore.swift`, about 300 lines over `import SQLite3`) also compiles for macOS and runs under `swift test` against a temp file, because the system library needs no package. This is why I recommend the system SQLite first: `ios/Package.swift` has zero dependencies today and `One.xcodeproj` has no Swift package references, so adding GRDB means editing the project file and the test package. GRDB (DatabasePool, DatabaseMigrator, ValueObservation) is the named upgrade if the wrapper starts to hurt; the store sits behind a protocol (`ActivityStoring`) so swapping is local. GRDB 7 lists iOS 13+ and Swift 6.1+; I did not check it against the iOS 27 SDK.

### 3.5 Schema sketch

```sql
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA user_version = 1;          -- migrations run in order when this is lower

CREATE TABLE event (
  id           INTEGER PRIMARY KEY,           -- local, monotonic; never used outside this device
  uid          TEXT NOT NULL UNIQUE,          -- UUID: cross references (undo_of) and future CloudKit record name
  device       TEXT NOT NULL,                 -- random id created at first launch
  ts           INTEGER NOT NULL,              -- unix ms, UTC
  tz           INTEGER NOT NULL,              -- minutes east of UTC when written
  day          INTEGER NOT NULL,              -- local yyyymmdd when written
  tier         INTEGER NOT NULL,              -- 1 change, 2 ai, 3 usage, 4 system
  kind         TEXT NOT NULL,                 -- 'change.completed', 'ai.card.resolved', 'ui.screen.open', ...
  actor        TEXT NOT NULL,                 -- you | ai | siri | shortcut | share | agent:<name> | system
  channel      TEXT,                          -- app | ask | automatic | intent | share | notification | sync | widget
  session      TEXT,                          -- one id per app launch
  thread       TEXT,                          -- ChatThread.id (a reference, never a copy of the text)
  subject_kind TEXT,                          -- task | event | alarm | grant
  subject_ref  TEXT,                          -- reminder PersistentIdentifier JSON, as LedgerEntry.itemRef today
  approval     TEXT,                          -- asked | auto | user | observed
  undo_of      TEXT,                          -- uid of the event this one undoes
  title        TEXT,                          -- personal content (tier 1; NULL when content is switched off)
  before_txt   TEXT,
  after_txt    TEXT,
  before_ts    INTEGER,
  after_ts     INTEGER,
  props        TEXT NOT NULL DEFAULT '{}',    -- JSON, no free text; shape depends on (kind, v)
  v            INTEGER NOT NULL DEFAULT 1,    -- version of the props shape for this kind
  sync         INTEGER NOT NULL DEFAULT 0     -- 0 = local only; reserved for the CloudKit phase
);
CREATE INDEX event_ts        ON event(ts DESC);
CREATE INDEX event_tier_ts   ON event(tier, ts DESC);
CREATE INDEX event_actor_ts  ON event(actor, ts DESC);
CREATE INDEX event_subject   ON event(subject_ref, ts DESC) WHERE subject_ref IS NOT NULL;
CREATE INDEX event_kind_day  ON event(kind, day);

CREATE TABLE snapshot (            -- deleted reminders, for Undo; pruned after 30 days
  event_uid TEXT PRIMARY KEY,
  data      BLOB NOT NULL
);

CREATE TABLE content (             -- text that must be redactable on its own (edited-card diffs, optional chat excerpts)
  event_uid TEXT NOT NULL,
  field     TEXT NOT NULL,         -- 'title' | 'when' | 'list' ...
  before_txt TEXT,
  after_txt  TEXT,
  PRIMARY KEY (event_uid, field)
) WITHOUT ROWID;

CREATE TABLE rollup_daily (        -- what survives after raw rows expire
  day    INTEGER NOT NULL,
  kind   TEXT NOT NULL,
  actor  TEXT NOT NULL,
  n      INTEGER NOT NULL,
  sum_ms INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, kind, actor)
) WITHOUT ROWID;

CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);   -- device id, settings snapshot, ledger_migrated flag, sync state later
```

Why these choices:
- **Immutable rows, Undo as a new row** (`undo_of`), exactly as the ledger works today. No update conflicts when two devices write.
- `uid` + `device` + `day` stored at write time make union merge and per-day grouping stable across time zones and devices.
- `props` JSON holds tier-specific data so adding a field to one kind never needs a table change; promote a field to a column only when a query needs an index on it (SQLite generated columns can do this later without rewriting rows).
- `title/before/after` are columns, not JSON, so "content off", redaction and export can null or drop them in one statement.
- Cursor pagination, not `OFFSET`: `WHERE ts < :lastTs ORDER BY ts DESC LIMIT 150` (the offset form also measured fast, 0.2 ms at 1M, but a cursor stays stable while new rows arrive).

### 3.6 Migration path from `LedgerEntry`

| Step | Change | Risk |
|---|---|---|
| 0 | Add `ActivityStore` and `ActivityRecorder`; nothing reads it yet | None |
| 1 (Phase 2) | **Dual write**: `Ledger.record` keeps writing `LedgerEntry` (Undo and `protectedRefs` still read it) and also appends a tier-1 event. Write the event at `Ledger.flush`, after `itemRef` is resolved, not at `record` | Small: two writes; flag to switch off |
| 2 | One-time copy of the existing `LedgerEntry` rows into `event` (batches of 500, one transaction each, `meta.ledger_migrated=1`). Field map: `id→uid`, `date→ts` (and `day`, `tz`), `actor`, `channel`, `action→kind 'change.'+action`, `itemKind→subject_kind`, `itemRef→subject_ref`, `title`, `before→before_txt`, `after→after_txt`, `approval`, `beforeDate/afterDate→before_ts/after_ts`, `snapshot→snapshot`, `undoOf→undo_of` | Medium: idempotent copy keyed on `uid`; verify counts |
| 3 | Cut over reads: Activity screen, `Ledger.undo`, `Ledger.protectedRefs` (becomes two indexed SQL queries on `(actor, ts)` and `(subject_ref)`) read the new store. Keep `Ledger`'s public API so the 30 call sites do not change | Medium: this is the behaviour the policy depends on, so the existing `AutonomyPolicy` tests must stay green |
| 4 | Stop writing `LedgerEntry`; keep the model in the schema, unused, exactly like `Habit`, so installs migrate; delete its rows at the next prune | Low |

Also: `-uiTesting` must open the store at `:memory:` or a temp file (same flag handling as `OneStore`), and Settings → Delete All Data needs one extra line that asks whether to clear activity history too. `ActivityView` keeps its look; only its data source changes, and the filter chips become `tier`/`actor` predicates.

---

## 4. Is CSV a good first step? (owner's idea, evaluated)

Short answer: CSV works for a tiny prototype and is good as an **export**; it is the wrong store.

What breaks with CSV as the live file:
1. **Quoting of free text.** Chat text, titles and `before → after` strings contain commas, quotes and newlines (and Chinese full-width punctuation). Every writer and reader must implement RFC 4180 quoting exactly; one bad row can shift every later column. JSON Lines escapes everything per line and is one-record-per-line by construction.
2. **Schema evolution.** CSV columns are positional. Adding `route` or `dwell_ms` to tier 2 means a new header, rewriting old files, or readers that guess. JSON ignores unknown keys; SQLite adds a column or a `props` key.
3. **No nesting.** `ranked_ids`, `edited_fields`, `props` need an encoded string inside a cell (JSON in CSV), which brings back the quoting problem.
4. **No indexes, no pagination.** "Newest 150 for actor = ai", "count by day", "this reminder's history" each become a full-file scan. Measured scale for comparison: SQLite answers the paged query in 0.02 to 0.2 ms at 1M rows; a file scan of 1M lines is O(N) every time (not benchmarked; expect seconds on a phone).
5. **Concurrent writers.** The app, a Share extension, an App Intent running in the background and a future widget would append to one file. Two simultaneous appends can interleave a partial row. The robust pattern (one file per writer or per write, merged later) is exactly the outbox design above.
6. **Retention and clearing.** Pruning to 90 days or deleting one person's rows means rewriting the whole file; SQLite does it in one `DELETE` (14 ms at 100k).
7. **Undo and policy lookups** (`protectedRefs`, `Ledger.undo`) need keyed access.

What is true in CSV's favour: zero dependencies, opens in Numbers and Excel, easy for a human or a script to inspect. So:
- **Store**: SQLite (`activity.sqlite`). It is also one file, needs no server, and the wrapper costs about the same effort as a correct CSV writer.
- **Interchange and outbox**: JSONL (one event per line, gzip optional with the `Compression` framework). The same line format later becomes the CloudKit record payload.
- **Export for humans**: CSV, flattened (envelope columns plus `props` as one JSON cell), produced from the store on demand through the share sheet or the Files exporter. The system Files exporter does not need an iCloud entitlement, so the user can save the export into their own iCloud Drive today (standard behaviour, not tested here).

If the owner still wants the lightest possible first step: JSONL outbox files only, with the reader being a script on the Mac. That records data immediately but does nothing for the Activity screen, so it is a stopgap, not a design.

---

## 5. iCloud and CloudKit

### 5.1 What a free Apple ID can and cannot do (from Apple's capability table)

I parsed Apple's "Supported capabilities (iOS)" page (https://developer.apple.com/help/account/reference/supported-capabilities-ios/). Columns are Developer Program, Enterprise Program, and "Apple Developer" (the free Apple Account).

| Capability | Free account |
|---|---|
| iCloud: CloudKit | **No** |
| iCloud: iCloud documents | **No** |
| iCloud: key-value storage | **No** |
| Push notifications | **No** (CloudKit sync relies on silent pushes) |
| "Siri" capability | No. This row is the SiriKit entitlement; App Intents / App Shortcuts (which the app already ships under free signing) are not affected (general knowledge: they need no entitlement) |
| WeatherKit, Sign in with Apple, Time Sensitive Notifications | No |
| App Groups | **Yes** |
| Background Modes | **Yes** |
| Data Protection | **Yes** |
| HealthKit | **Yes** |
| Keychain sharing | Yes |

Free Personal Team limits (https://developer.apple.com/support/compare-memberships/): up to 10 App IDs and 3 devices, each expiring after 7 days; up to 3 apps per device; profiles expire 7 days after issue, so the app must be rebuilt and reinstalled.

Corrections to `docs/research/ai-native-vision.md`: it says CloudKit needs a paid account "per Apple's table, not verified": now **verified**. It also lists HealthKit as unverified on a free account: the table shows it **is** available (the project already declares it).

Practical consequences for the activity data on a free account:
- Reinstalling over the expired build with the same bundle id from Xcode keeps the app container; deleting the app deletes the database. I did not verify this here, but it is why Phase 1 ships **Export** (JSONL) early and why the device backup (included by default for Application Support) is the only other safety net.
- Adding another extension target uses App IDs from the weekly budget of 10; the design needs no new target.

### 5.2 What CloudKit sync needs (paid account)

From Apple's SwiftData syncing article (https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices):
- iCloud capability with CloudKit and a container, plus Background Modes → Remote notifications. "The iCloud capability requires an active Apple Developer account with admin permissions."
- SwiftData cannot use unique constraints, requires relationships to be optional, and does not support the deny delete rule. CloudKit schemas are additive only after promotion to production: no deleting or changing existing attributes.
- Development schema must be deployed to production in the CloudKit Console before an App Store/TestFlight build can sync (https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema).
- (From general knowledge, not on the fetched page) CloudKit-backed models also need default values or optionals for every attribute. The current `LedgerEntry` has non-optional properties without defaults and would need a model change to sync, another reason not to use SwiftData sync for the ledger. `ChatThread` already has defaults.

Recommended mechanism for this app: **`CKSyncEngine`** (iOS 17+, from WWDC 2023; I could not fetch Apple's page text, so the API details here are from memory) over the SQLite store. The app keeps its local store as the truth and implements the delegate: upload batches of tier 1 and 2 rows where `sync = 0`, apply fetched rows idempotently by `uid`, persist the engine state in `meta`. Reasons: works with any local store; syncs only what we choose; append-only rows make conflicts a non-issue (union by `uid`); a user "clear" propagates as a tombstone event.

Record design (kept in mind from day one): record type `Event`, record name = `uid`, zone `Activity`, one record per event, fields = the columns above, `props` as a string. Encrypted fields (`CKRecord.encryptedValues`) for `title`, `before_txt`, `after_txt`, `props`, `content`: Apple says encrypt only **new** fields, never ones already in the schema, and encrypted fields cannot be indexed or used in predicates (https://developer.apple.com/documentation/cloudkit/ckrecord/encryptedvalues). That is fine here because all querying happens in the local SQLite. Since a new record type can use encryption from the first version, plan it now.

### 5.3 Quotas, encryption, deletion

- **Quota**: data in a user's private database counts against that user's own iCloud storage, not the developer's (Apple technote TN2241, https://developer.apple.com/library/archive/technotes/tn2241/_index.html; the public database scales with the app's user count and is not used here). 15k to 50k synced rows a year at 300 bytes is well under 20 MB. I did not find a current Apple page giving request-rate limits; `CKSyncEngine` batches and retries on its own.
- **Encryption**: Apple's iCloud security article (https://support.apple.com/en-us/102651, Jan 2026) says third-party app data is "always encrypted in transit and on server", and that with Advanced Data Protection "CloudKit encrypted fields and assets are end-to-end encrypted". Apple's CloudKit article says encrypted fields use key material in the user's iCloud Keychain. Whether encrypted fields are already end-to-end without ADP is not stated clearly in what I read (the two statements are in tension): **not verified**. Say in the product only what is guaranteed: "encrypted; end-to-end with Advanced Data Protection". The SwiftData option `@Attribute(.allowsCloudEncryption)` (iOS 17+, iCloud only) exists but is not needed with `CKSyncEngine`.
- **Delete All Data**: today it never touches Apple Calendar/Reminders. For the activity store: local delete is one `DELETE` + `VACUUM`. With CloudKit on, deleting local rows is not enough; the app must also delete the `Activity` zone (or send tombstones) so other devices and iCloud are cleared, and must say so in the confirmation. If the user loses their iCloud Keychain, encrypted data can become undecryptable and Apple's article describes recreating the zones and re-uploading from the local copy: another reason the local SQLite stays the source of truth.

### 5.4 Phased plan

| Phase | Account | Storage | iCloud |
|---|---|---|---|
| Now | Free | `activity.sqlite` in the app container, outbox in the App Group, JSONL/CSV export | None. Schema already has `uid`, `device`, immutable rows, `sync` column |
| Paid account bought | Paid | Same | Add iCloud (CloudKit) + Push + Background Modes; `CKSyncEngine` for tiers 1 and 2 into private zone `Activity`; encrypted text fields; Delete All Data clears the zone |
| Later | Paid | Same | Optional: a Mac companion reads the same private zone; still no readable-by-us data |

---

## 6. How the recorded data improves the product

### 6.1 The loops (each with the minimum fields)

All loops run on the device or on an export the owner inspects; none needs a server.

| Loop | What it improves | Minimum fields | Where it runs |
|---|---|---|---|
| Suggestion-chip ranking | `AskSuggestions` / `AskSuggestionRanker`: show chips people tap, hide ones they ignore | `ai.chips.shown` (`ranked_ids`, source rules/model, hour bucket, screen) and `ai.chip.tapped` (id, rank) | On device: per-id tap rate with decay feeds the rule ranking |
| Parser failure mining | `CaptureParser` and the Apple Foundation Models path | `ai.card.resolved` with `edited_fields`, plus the `content` rows (field, before, after) and the input length/lang; the input text only if the user opts in | Export or an in-app "Save as eval case" button → `capture-cases.json` train split |
| Auto-plan acceptance | Whether "Plan reminders into free time" is trusted | `change.planned` with `approval` (asked/auto), `undo_of` within 24 h, time between plan and undo | SQL over tier 1: acceptance = applied minus undone in 24 h |
| Overdue-tidy timing | When to offer "Tidy overdue" | `ai.card.shown` kind `tidy`, hour, count overdue, outcome, dwell | Hour-of-day histogram from `rollup_daily` |
| Usual reminder prediction | `ReminderSuggest` / Quick add time grid | `ui.quickadd.commit` (chosen slot, list, ms), created reminder time-of-day | On device; uses tier 1 `created` plus tier 3 slot |
| Foundation Models vs rules | Which route does better, latency | `ai.turn` (`route`, `latency_ms`, `model`, `prompt`, `items_proposed`) joined to `ai.card.resolved` (applied vs edited vs cancelled) | Eval: edit rate per route and prompt version |
| Time-to-complete on core journeys (J1 to J7) | The tap-budget ratchet in `goal-and-rubric.md` | `ui.quickadd.start/commit` with `ms`, `taps` | Real-use counterpart to the UI tests |
| Duration calibration | Planned vs actual time (vision doc idea 7) | `change.completed` with `ts`, planned start/duration at the time | Tier 1 plus item fields |

The cheapest and highest-value loop now: the owner is also the only user, so "export JSONL → agent mines the edited-card diffs → new cases in `ios/Eval/Tests/OneLogicTests/capture-cases.json`" works with no new infrastructure.

---

## 7. Privacy and trust (kept short, by decision)

### 7.1 What the product does
- **Say it plainly.** In Settings, a "Your activity" page: what is recorded (the four tiers in one sentence each), that it is stored on this iPhone (and later in your own iCloud), what is never recorded (no passwords; chat text and search text are not copied into analytics rows), and how to turn it off. The Activity screen is the visible part of the same data.
- **Cheap basics**: a master pause, a toggle per tier, "Clear activity history" (with an Undo-free confirmation that names the row count), and "Export" (JSONL for the machine, CSV for a spreadsheet). Defaults: tiers 1, 2 and 4 on, tier 3 on with metadata only (see decision 1).
- **Principle**: tier 3 and 4 events never contain titles or chat text, so analysing them never needs redaction.

### 7.2 The two uses of the data
- (A) The user's own history: on their devices (and later their iCloud). Fully theirs, visible in Activity.
- (B) Improving the product: this is a separate use. Today it happens only through things the owner inspects: local evaluation sets and a manual export.

### 7.3 Later: redacted upload to the product team (not decided)
The owner's intent: most data stays with the user; redacted data may later be uploaded to improve the product. Honest scope of that:
- **Data in the user's private CloudKit database is not readable by us.** A private database belongs to the user's iCloud account and is reached only with that account (the CloudKit documentation describes it as per-user data; that the developer console cannot browse users' private records is standard behaviour I did not re-verify), and encrypted fields are additionally encrypted to the user's keys. So CloudKit sync gives the user a backup and multi-device history, nothing for product analytics.
- Any product-improvement upload is therefore a **separate pipeline**, and none of it exists today. It would need:
  1. **Our own backend** (for example a small Cloudflare Worker with R2 or D1; the project already deploys a Worker) that accepts only a fixed, versioned payload.
  2. **A redaction pipeline on the device**: drop `title`, `before_txt`, `after_txt`, `content`, `thread`, `subject_ref`; replace ids with a salted per-install hash; coarsen time to the hour; keep counts, rates, routes, model/prompt versions, durations. Show the user the exact payload before sending.
  3. **Explicit consent text** and a switch that defaults to off, an in-app "what would be sent" preview, and a way to delete the install's uploaded data.
  4. **Product principle change**: `CLAUDE.md` says "data stays local". Remote analytics requires rewording it (for example "personal content stays local; anonymous counters may be shared if you opt in"), an App Store privacy label update, and a privacy policy.
  5. Aggregate-only analysis (no raw rows) and a retention limit on the server.
- Comparison: manual export (today) is the lowest-risk choice and fits the principle unchanged; Apple's own opt-in diagnostics (Xcode Organizer crash and hang data, MetricKit on device) need distribution through TestFlight or the App Store, so they also wait for the paid account (standard Apple behaviour, not re-verified here); a server pipeline gives data for all users but changes the product's promise.
- **This is a decision for the owner, listed under decisions below. I recommend not building it until the local loops (section 6.1) have shown whether they are enough.**

---

## 8. Phased implementation plan

Sizes: S = about 1 to 2 days, M = 3 to 5 days, L = 1 to 2 weeks or more.

| Phase | Content | Size | Account | Done when |
|---|---|---|---|---|
| **1. Store and first recordings (one agent, one day)** | `ActivityStore` (system SQLite wrapper behind `ActivityStoring`, WAL, `user_version` migration 1, schema 3.5), `ActivityRecorder` (in-memory buffer, flush every 1 to 2 s and on background, inside a background task), pure `ActivityEvent` kinds/envelope/retention/export in an `OneEval` file, tier 2 events (`ai.turn`, card shown/resolved with edited fields, chips shown/tapped, undo), `-uiTesting` in-memory store, JSONL export (a debug/Settings button), tests under `swift test`. The ledger and the Activity screen do not change | S | Free | New `swift test` cases pass; a JSONL export opens and has the expected rows |
| **1b. Basics and checks** | Settings → "Your activity" page (pause, per-tier toggles, Clear, CSV export), tier 4 events (sync conflict, intent run, share import, error), re-run the insert benchmark on a real iPhone and check `fts5` / `PRAGMA compile_options` on the iOS runtime, log row counts per day for a week to replace the estimates in 2.3 | S | Free | Page works with pause/clear; device numbers recorded in this document |
| 2. Ledger into the store | Dual write, one-time copy, cut over Activity screen, `Ledger.undo` and `protectedRefs` to SQL (section 3.6); cursor paging; Activity gets tier 2 rows ("Card edited before Add", "Suggestion ignored") and search by `LIKE` | M | Free | `AutonomyPolicy` tests green; Activity identical for tier 1 data |
| 3. Usage tier, rollups, outbox | Tier 3 events with coalescing, `rollup_daily` + retention job (launch and background refresh), App Group outbox drained on activation (widget refresh results, Share, background intents) | M | Free | Store size stays flat in a two-week soak |
| 4. Local learning loops | Chip ranking from tap history, "Save as eval case" for edited cards, acceptance-rate and route-comparison views (debug/Settings), capture-case export for `Eval` | M | Free | One measured improvement on the held-out capture set or chip tap rate |
| 5. Redacted diagnostics export | User-initiated "Share diagnostics" file with a preview; same redaction function a later upload would use | S | Free | File reviewed by the owner |
| 6. iCloud sync | `CKSyncEngine` for tiers 1 and 2, encrypted fields, zone delete on Delete All Data, conflict/tombstone tests, schema promotion to production | L | **Paid** | Two devices show one history |
| 7. Product-improvement upload (only if decided) | Backend, redaction pipeline, consent UI, principle rewrite (7.3) | L | Any | Owner sign-off |

Why Phase 1 is a day for one agent: the wrapper is small and compiled by the existing test package; recording starts at call sites that already exist (Ask card Add/Cancel, chip tap, `Ledger.recordUndo` in AI paths) with no UI change except one Settings page.

### Open decisions for the owner (maximum 5)

1. **Tier 3 usage events on by default?** Recommend yes, metadata only, local, with the in-app disclosure and a master pause. It is the data that powers the tap-budget and quick-add loops.
2. **Ledger retention: 90 days today.** Recommend 1 year (about 5 MB), with Undo snapshots dropped after 30 days, user-selectable (90 days / 1 year / forever).
3. **Store text or only references?** Recommend: chat text stays only in `ChatThread` (events keep `thread` id and lengths); the only copied text is tier 1 titles and edited-card diffs. This keeps tiers 2 to 4 free of personal content.
4. **When to buy the paid account** (CloudKit sync, TestFlight, Apple's opt-in diagnostics, WeatherKit). Recommend: when a second iPhone/iPad or the Mac companion needs the same history, or when TestFlight distribution is needed; nothing in Phases 1 to 5 waits for it, and the schema is already CloudKit-ready.
5. **Product-improvement upload of redacted data.** Later decision; recommend deferring until the local loops and manual export have been used for a few weeks, because they may cover the need without changing the "data stays local" principle.

---

## 9. What I verified and what I could not

Verified with a source I read or a test I ran:
- Free Apple account capability matrix (iCloud/CloudKit, iCloud documents, Push: no; App Groups, Background Modes, Data Protection, HealthKit: yes) from Apple's capabilities page; Personal Team limits from Apple's compare-memberships page.
- SwiftData CloudKit requirements (iCloud capability needs a developer account; no unique constraints; optional relationships; additive schema) from Apple's SwiftData article JSON; CloudKit encrypted fields rules (new fields only, no indexes, keys from iCloud Keychain) from Apple's CloudKit articles; ADP statement from Apple's iCloud article (Jan 2026).
- GRDB's sharing guide (quote in 3.3) and NetNewsWire's fix.
- Benchmarks and the Chinese-text FTS5 results in 3.2 (my own run on a Mac).
- The existing ledger code, entitlements (App Group only for the three targets; HealthKit on the app) and that `ios/Package.swift` has no dependencies.

Not verified:
- Any number measured on an iPhone (insert speed, battery, FTS5 availability in the iOS runtime). Phase 1 includes the check.
- `CKSyncEngine` API details and iOS 17 availability (Apple's page did not load as text; written from memory), CloudKit request-rate limits, whether encrypted fields are end-to-end without ADP, and a current number for private-database quota (TN2241 states the principle only).
- Default file-protection class wording, backup inclusion of Application Support, that reinstalling over an expired free-signed build keeps the container, and that the system Files exporter works without an iCloud entitlement (all standard behaviour, not tested here).
- GRDB compatibility with the iOS 27 SDK, `NSBatchInsertRequest` speed, and Apple's `0xDEAD10CC` page text (found only through forum and GRDB quotes).
- Event volumes in 2.3 are estimates for a heavy day; real counts come from Phase 1.

## Sources
- Apple, Supported capabilities (iOS): https://developer.apple.com/help/account/reference/supported-capabilities-ios/
- Apple, Compare memberships: https://developer.apple.com/support/compare-memberships/
- Apple, Syncing model data across a person's devices (SwiftData): https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices
- Apple, Encrypting user data (CloudKit): https://developer.apple.com/documentation/cloudkit/encrypting-user-data
- Apple, CKRecord.encryptedValues: https://developer.apple.com/documentation/cloudkit/ckrecord/encryptedvalues
- Apple, Deploying an iCloud container's schema: https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema
- Apple, iCloud data security overview: https://support.apple.com/en-us/102651
- Apple, Migrating to CloudKit (TN2241): https://developer.apple.com/library/archive/technotes/tn2241/_index.html
- Apple, Schema.Attribute.Option.allowsCloudEncryption: https://developer.apple.com/documentation/swiftdata/schema/attribute/option
- GRDB, Sharing a Database: https://github.com/groue/GRDB.swift/blob/master/GRDB/Documentation.docc/DatabaseSharing.md
- Brent Simmons, how NetNewsWire fixed 0xdead10cc: https://inessential.com/2020/02/13/how_we_fixed_the_dreaded_0xdead10cc_cras
