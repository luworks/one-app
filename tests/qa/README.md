# QA Activity journal

`journal.py` uses Python's standard library and the app's exact v1 SQLite migration,
checked against `ios/One/ActivityStore.swift` by a host test. This is a separate QA
file, never the app's database or real user data. WAL, foreign keys, transactions,
a 10-second busy timeout and `user_version` follow ActivityStore. A newer schema
is rejected. The SQL fixture must be updated deliberately with the source contract.

Default storage resolves `.git` and `commondir` without subprocesses to the primary
checkout: `tests/results/activity.sqlite`. Raw evidence and the DB are locally
persistent and Git-ignored; fixtures, code, schema, docs and selected readable
summaries belong in Git. Do not clean `tests/results` as disposable build output.
Back up the database through SQLite's backup API (or after closing writers), not
by copying a live SQLite file without its WAL.

```sh
python3 tests/qa/journal.py record dev-20261018 qa.development 'Read ActivityStore migrations'
python3 tests/qa/journal.py record dev-20261018 qa.command.started 'python3 -m unittest discover -s tests/qa'
python3 tests/qa/journal.py record dev-20261018 qa.ui.operation 'Tap Today tab'
python3 tests/qa/journal.py record dev-20261018 qa.link 'https://github.com/owner/repo/pull/123'
python3 tests/qa/journal.py import /tmp/today-overnight-20261018 --session overnight-20261018
# Only after the owner has confirmed the process stopped and its actual exit result:
python3 tests/qa/journal.py import /tmp/today-overnight-20261018 --session overnight-20261018 --status failed --archive
python3 tests/qa/journal.py query --session overnight-20261018
python3 tests/qa/journal.py export --session overnight-20261018 > tests/qa/evidence/overnight-events.jsonl
```

The archive command above is an example, not a declaration that the run failed.
Completion status is always explicit; neither success markers nor a partial
`summary.json` decide the run result. A checkpoint is `running`, only imports
newline-terminated test/UI records and command metadata, and never reads/copies
an active xcresult. Repeated identical lines at different byte offsets remain
separate attempts; the same source/offset/bytes import is idempotent. Changed bytes
produce another immutable record. Reusing a manual UID with different data fails.

Final `--archive` copies every regular file (including files inside xcresult,
screenshots, raw logs and reports), checks SHA-256, indexes its path/hash/size,
and keeps prior revisions under `tests/results/runs/<session>/archive/<hash>/...`.
It never moves or deletes the live source. The caller must stop writers before
archiving. Symlinks are excluded. Large bytes stay outside SQLite; artifact metadata
is in `snapshot` and the file path is in `content`. Existing retained files are
hash-checked, never silently overwritten with changed bytes.

Events use `actor=agent:Codex`, `channel=qa`, a session and subject reference,
UTC milliseconds, local offset/day, immutable UID, tier 4 (the app maps unknown
`qa.*` kinds to system). Commands/actions/links/result detail live in `content`;
`props` contains only structured statuses, exit codes, byte counts and hashes.
`qa.run`, `qa.command.*`, `qa.test`, `qa.ui.operation`, `qa.artifact`,
`qa.development` and `qa.link` distinguish actions without another event schema.
Manual `record` accepts event text, status and optional idempotency UID; it does
not execute the command. Only explicitly supplied issue/PR links are recorded.

The runner writes live command starts/completions, test starts/results and XCTest
UI-operation lines. Its `finally` records shutdown/result and indexes finished
files; journal failures print separately and populate `summary.json.journal_errors`
without replacing a valid test failure exit code. An explicit runner `--output`
can be elsewhere, but its journal remains canonical. `--help`, `--inventory`, and
`--dry-run` open no DB, create no evidence and launch no subprocess.

Useful SQL (read with Python sqlite3 or `sqlite3 tests/results/activity.sqlite`):

```sql
PRAGMA integrity_check;
PRAGMA user_version;
SELECT session, kind, count(*) FROM event GROUP BY session,kind;
SELECT e.id,e.kind,e.subject_ref,json_extract(e.props,'$.status'),c.after_txt
FROM event e JOIN content c ON c.event_uid=e.uid
WHERE e.session='overnight-20261018' ORDER BY e.ts,e.id;
SELECT e.uid,s.data FROM event e JOIN snapshot s ON s.event_uid=e.uid
WHERE e.kind='qa.artifact';
```

Focused host checks (no Swift, Xcode or devices):

```sh
python3 -m unittest discover -s tests/qa -p 'test_*.py'
python3 -m unittest discover -s ios/Eval -p test_e2e_runner.py
```
