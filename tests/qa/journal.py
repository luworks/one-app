#!/usr/bin/env python3
"""QA-only Activity journal. Never open the application's database."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
import sqlite3
import uuid

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = Path(__file__).with_name('activity-v1.sql')
CASE = re.compile(r"Test Case '(.*?)' (started|passed|failed|skipped)")
UI = re.compile(r'\bt\s*=\s*\d+.*(?:Tap |Swipe |Find |Wait |Launch |Terminate |Click |Type |Scroll )')
STATUSES = ('running', 'passed', 'failed', 'interrupted')


def canonical_root(root=ROOT):
    """Resolve Git's common directory without launching Git (including dry-run)."""
    root = Path(root).resolve()
    dotgit = root / '.git'
    if dotgit.is_file():
        gitdir = (root / dotgit.read_text().strip().split(':', 1)[1].strip()).resolve()
        common = gitdir / 'commondir'
        gitdir = (gitdir / common.read_text().strip()).resolve() if common.exists() else gitdir
    else:
        gitdir = dotgit
    return gitdir.parent if gitdir.name == '.git' else root


def results_root():
    return canonical_root() / 'tests/results'


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


class Journal:
    def __init__(self, path=None):
        self.path = Path(path) if path else results_root() / 'activity.sqlite'
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(self.path, timeout=10)
        self.db.row_factory = sqlite3.Row
        try:
            version = self.db.execute('PRAGMA user_version').fetchone()[0]
            if version > 1:
                raise ValueError(f'Newer Activity schema: {version}')
            self.db.execute('PRAGMA busy_timeout=10000')
            self.db.execute('PRAGMA foreign_keys=ON')
            self.db.execute('PRAGMA journal_mode=WAL')
            if version == 0:
                self.db.executescript('BEGIN IMMEDIATE;\n' + SCHEMA.read_text() + '\nPRAGMA user_version=1; COMMIT;')
            with self.db:
                self.db.execute("INSERT OR IGNORE INTO meta VALUES ('device', ?)", ('qa-' + str(uuid.uuid4()),))
                self.db.execute("INSERT OR IGNORE INTO meta VALUES ('qa.schema_source', ?)", ('ios/One/ActivityStore.swift:migrations[0]',))
            self.device = self.db.execute("SELECT value FROM meta WHERE key='device'").fetchone()[0]
        except BaseException:
            self.db.close()
            raise

    def close(self):
        self.db.close()

    def record(self, session, kind, text='', *, status=None, uid=None, subject=None, props=None, snapshot=None):
        if status is not None and status not in (*STATUSES, 'started', 'completed', 'skipped'):
            raise ValueError(f'Unknown status: {status}')
        now = datetime.now().astimezone()
        uid = uid or str(uuid.uuid4())
        props = dict(props or {})
        if status:
            props['status'] = status
        # Callers put commands, paths, links and action text in content, never props.
        with self.db:
            inserted = self.db.execute('''INSERT OR IGNORE INTO event
                (uid,device,ts,tz,day,tier,kind,actor,channel,session,subject_kind,subject_ref,props)
                VALUES (?,?,?,?,?,4,?,'agent:Codex','qa',?,'qa',?,?)''',
                (uid, self.device, int(now.timestamp()*1000), int(now.utcoffset().total_seconds()/60),
                 int(now.strftime('%Y%m%d')), kind, session, subject or session, json.dumps(props, sort_keys=True))).rowcount
            if inserted:
                self.db.execute('INSERT INTO content VALUES (?,?,NULL,?)', (uid, 'action', text))
                if snapshot is not None:
                    self.db.execute('INSERT INTO snapshot VALUES (?,?)', (uid, json.dumps(snapshot, sort_keys=True).encode()))
            else:
                old = self.db.execute('SELECT after_txt FROM content WHERE event_uid=? AND field=?', (uid, 'action')).fetchone()
                old_event = self.db.execute('SELECT session,kind,props,subject_ref FROM event WHERE uid=?', (uid,)).fetchone()
                if old is None or old[0] != text or tuple(old_event) != (session, kind, json.dumps(props, sort_keys=True), subject or session):
                    raise ValueError(f'Conflicting immutable event: {uid}')
        return uid

    def query(self, session=None):
        sql = '''SELECT e.*, c.after_txt AS action FROM event e LEFT JOIN content c
                 ON c.event_uid=e.uid AND c.field='action' '''
        if session is not None:
            sql += 'WHERE session=? '
        rows = [dict(r) for r in self.db.execute(sql + 'ORDER BY ts,id', () if session is None else (session,))]
        for row in rows:
            snapshot = self.db.execute('SELECT data FROM snapshot WHERE event_uid=?', (row['uid'],)).fetchone()
            if snapshot:
                row['snapshot'] = json.loads(snapshot[0])
        return rows

    def artifact(self, session, path, source=None):
        path = Path(path).resolve()
        sha = digest(path)
        self.record(session, 'qa.artifact', str(path), uid=f'artifact:{session}:{path}:{sha}',
                    props={'sha256': sha, 'bytes': path.stat().st_size},
                    snapshot={'path': str(path), 'source': str(source or path), 'sha256': sha})
        return sha

    def import_run(self, source, session, *, status='running', archive=False):
        if status not in STATUSES or (archive and status == 'running'):
            raise ValueError('Archive requires an explicit completed result status')
        source = Path(source).resolve()
        if not re.fullmatch(r'[A-Za-z0-9_.-]+', session) or session in ('.', '..'):
            raise ValueError('Import session must be a safe directory name')
        if not source.is_dir():
            raise ValueError(f'Missing source directory: {source}')
        if archive and (source == self.path.parent or source in self.path.parent.parents):
            raise ValueError('Archive source must not contain the journal directory')
        self.record(session, 'qa.run', str(source), status='running', uid=f'import:{session}:{source}')
        for path in sorted(source.rglob('*')):
            if path.is_symlink() or not path.is_file() or any(p.endswith('.xcresult') for p in path.relative_to(source).parts):
                continue
            if path.suffix == '.log':
                # Ignore an incomplete final line; no success inference from markers.
                with path.open('rb') as stream:
                    offset = 0
                    for raw in stream:
                        start = offset
                        offset += len(raw)
                        if not raw.endswith(b'\n'):
                            break
                        line = raw.decode('utf-8', errors='replace').rstrip('\r\n')
                        match = CASE.search(line)
                        if match or UI.search(line):
                            kind = 'qa.test' if match else 'qa.ui.operation'
                            self.record(session, kind, line, status=match[2] if match else None,
                                        subject=match[1] if match else None,
                                        uid=f'line:{session}:{path}:{start}:{hashlib.sha256(raw).hexdigest()}')
            if path.name == 'command.json':
                data = path.read_bytes()
                self.record(session, 'qa.command.imported', data.decode(), status='running',
                            uid=f'command:{session}:{hashlib.sha256(data).hexdigest()}')
        if archive:
            # Every revision has its own content-addressed file; originals stay untouched.
            destination = self.path.parent / 'runs' / session / 'archive'
            for path in sorted(source.rglob('*')):
                if path.is_symlink() or not path.is_file():
                    continue
                sha = digest(path)
                target = destination / sha / path.relative_to(source)
                target.parent.mkdir(parents=True, exist_ok=True)
                if target.exists():
                    if digest(target) != sha:
                        raise ValueError(f'Corrupt retained artifact: {target}')
                else:
                    temporary = target.with_name(target.name + '.' + uuid.uuid4().hex + '.tmp')
                    try:
                        shutil.copyfile(path, temporary)
                        if digest(temporary) != sha:
                            raise ValueError(f'Source changed during archive: {path}')
                        temporary.replace(target)
                    finally:
                        temporary.unlink(missing_ok=True)
                self.artifact(session, target, path)
        self.record(session, 'qa.run.checkpoint' if status == 'running' else 'qa.run.result', str(source),
                    status=status, uid=f'result:{session}:{status}')
        return self.query(session)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--db', type=Path)
    sub = p.add_subparsers(dest='op', required=True)
    record = sub.add_parser('record')
    record.add_argument('session')
    record.add_argument('kind', help='qa.command.*, qa.ui.operation, qa.development, qa.link, etc.')
    record.add_argument('text')
    record.add_argument('--status', choices=STATUSES)
    record.add_argument('--uid')
    imp = sub.add_parser('import')
    imp.add_argument('source', type=Path)
    imp.add_argument('--session', required=True)
    imp.add_argument('--status', choices=STATUSES, default='running')
    imp.add_argument('--archive', action='store_true')
    for name in ('query', 'export'):
        q = sub.add_parser(name)
        q.add_argument('--session')
    args = p.parse_args(argv)
    journal = Journal(args.db)
    try:
        if args.op == 'record':
            print(journal.record(args.session, args.kind, args.text, status=args.status, uid=args.uid))
        elif args.op == 'import':
            print(json.dumps({'events': len(journal.import_run(args.source, args.session, status=args.status, archive=args.archive))}))
        else:
            # stdout is deliberate: caller chooses a new versionable summary path.
            for row in journal.query(args.session):
                print(json.dumps(row, sort_keys=True))
    finally:
        journal.close()


if __name__ == '__main__':
    main()
