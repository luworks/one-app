#!/usr/bin/env python3
"""Generate synthetic baseline artifacts and verify copies with an independently selected reader."""
import argparse
import csv
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
BASE = '395376bb126fd7415ac6b44eee91b796eb8ca60c'
SOURCES = ['One/' + n + '.swift' for n in (
    'ActivityEvent', 'ActivityStore', 'ActivityExport', 'ActivityLedger', 'LedgerLogic', 'Logic', 'Preferences')]
SOURCES += ['Shared/' + n + '.swift' for n in ('WidgetSnapshot', 'TravelTime', 'ShareInbox', 'ActivityOutbox')]
SESSION = 'today-migration-395376b'
spec = importlib.util.spec_from_file_location('qa_journal', ROOT / 'tests/qa/journal.py')
journal_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(journal_module)


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args])


def sha(data):
    return hashlib.sha256(data).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, help='New, empty output directory; defaults to canonical results')
    parser.add_argument('--reader-ref', default=BASE, help='Git commit to compile as the reader (default: baseline)')
    args = parser.parse_args()
    reader = git('rev-parse', args.reader_ref + '^{commit}').decode().strip()
    assert git('rev-parse', BASE + '^{commit}').decode().strip() == BASE
    output = args.output or journal_module.results_root() / ('migration-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
    output = output.resolve()
    canonical = Path('/Users/yuanlu/code/one-app/tests/results').resolve()
    if canonical not in output.parents:
        parser.error('--output must be a new directory inside canonical tests/results')
    output.mkdir(parents=True, exist_ok=False)  # Never overwrite or delete an earlier database.
    journal = journal_module.Journal('/Users/yuanlu/code/one-app/tests/results/activity.sqlite')
    journal.record(SESSION, 'qa.command.migration', f'{sys.argv!r}; output={output}; writer={BASE}; reader={reader}', status='running')
    log_path = output / 'run.log'
    try:
        with log_path.open('w') as log:
            def run(cmd):
                log.write(repr([str(x) for x in cmd]) + '\n'); log.flush()
                subprocess.run(cmd, check=True, stdout=log, stderr=subprocess.STDOUT,
                               env={**os.environ, 'TZ': 'UTC'})

            def compile_at(ref, name):
                directory = output / name
                directory.mkdir()
                hashes = {}
                for relative in SOURCES:
                    data = git('show', f'{ref}:ios/{relative}')
                    target = directory / Path(relative).name
                    target.write_bytes(data)
                    hashes['ios/' + relative] = sha(data)
                harness = ROOT / 'tests/migration/ContractHarness.swift'
                shutil.copyfile(harness, directory / 'main.swift')
                hashes['tests/migration/ContractHarness.swift'] = sha(harness.read_bytes())
                save(directory / 'sources.json', {'commit': ref, 'sha256': hashes})
                run(['swiftc', '-module-name', 'MigrationDiskContract', *sorted(directory.glob('*.swift')), '-o', directory / 'contract'])
                return directory / 'contract'

            # Source capture is deliberately separate from executed writer contracts.
            paths = git('ls-tree', '-r', '--name-only', BASE, 'ios/One', 'ios/Shared', 'ios/One.xcodeproj').decode().splitlines()
            captured = {}
            for path in paths:
                if path.endswith(('.swift', '.pbxproj', '.entitlements')):
                    data = git('show', f'{BASE}:{path}')
                    target = output / 'baseline-source' / path
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(data)
                    captured[path] = sha(data)
            texts = {p: (output / 'baseline-source' / p).read_text() for p in captured if p.endswith('.swift')}
            save(output / 'source-contract.json', {
                'baseline': BASE, 'source_sha256': captured,
                'model_names': sorted(set(re.findall(r'@Model\s+final class (\w+)', '\n'.join(texts.values())))),
                'key_literals_by_source': {p: sorted(set(re.findall(r'"((?:today\.|one\.|activity\.|timer\.)[^"\n]+)"', t))) for p, t in texts.items() if re.search(r'"(?:today\.|one\.|activity\.|timer\.)', t)},
                'default_keys_type_present': any('enum DefaultKeys' in t or 'struct DefaultKeys' in t for t in texts.values()),
                'warning': 'Source inspection only; not a SwiftData schema or a UserDefaults runtime snapshot.'})
            writer = compile_at(BASE, 'writer')
            fixtures = output / 'fixtures'
            fixtures.mkdir()
            run([writer, 'write', fixtures])
            # Writer has exited: WAL closure/checkpoint is complete before hashing/copying.
            manifest = {p.relative_to(fixtures).as_posix(): sha(p.read_bytes()) for p in sorted(fixtures.rglob('*')) if p.is_file()}
            save(output / 'fixture-manifest.json', {'writer_commit': BASE, 'sha256': manifest})
            with sqlite3.connect(f'file:{fixtures / "activity.sqlite"}?mode=ro&immutable=1', uri=True) as db:
                assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
                assert db.execute('PRAGMA foreign_key_check').fetchall() == []
            copied = output / 'reader-copy'
            shutil.copytree(fixtures, copied)
            reader_binary = writer if reader == BASE else compile_at(reader, 'reader')
            run([reader_binary, 'verify', copied])
            with (fixtures / 'activity.csv').open(newline='') as stream:
                csv_rows = list(csv.DictReader(stream))
                assert len(csv_rows) == 2
                assert csv_rows[0]['before_txt'] == 'Before, "quoted"\nsecond line'
                assert csv_rows[1]['undo_of'] == csv_rows[0]['uid']
            with sqlite3.connect(f'file:{copied / "activity.sqlite"}?mode=ro', uri=True) as db:
                assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
                assert db.execute('PRAGMA foreign_key_check').fetchall() == []
                save(output / 'sqlite-contract.json', {
                    'user_version': db.execute('PRAGMA user_version').fetchone()[0],
                    'schema': db.execute("SELECT type,name,sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY type,name").fetchall(),
                    'event_rows': db.execute('SELECT id,uid,ts,tz,day,subject_ref,undo_of FROM event ORDER BY id').fetchall(),
                    'snapshots': db.execute('SELECT event_uid,hex(data) FROM snapshot ORDER BY event_uid').fetchall(),
                    'content': db.execute('SELECT * FROM content ORDER BY event_uid,field').fetchall()})
            assert manifest == {p.relative_to(fixtures).as_posix(): sha(p.read_bytes()) for p in fixtures.rglob('*') if p.is_file()}, 'Writer artifacts changed'
            save(output / 'result.json', {'status': 'passed', 'writer_commit': BASE, 'reader_commit': reader,
                 'executed': 'macOS swiftc disk contracts; separate writer/reader processes',
                 'not_executed': ['SwiftData writer/reader', 'iOS build', 'simulator', 'device', 'cross-process extension contention']})
        journal.record(SESSION, 'qa.command.migration', str(output), status='passed')
    except BaseException:
        journal.record(SESSION, 'qa.command.migration', str(output), status='failed')
        raise
    finally:
        for path in sorted(output.rglob('*')):
            if path.is_file():
                journal.artifact(SESSION, path)
        journal.close()
    print(output)


if __name__ == '__main__':
    main()
