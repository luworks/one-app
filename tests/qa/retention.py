"""Conservative retention: retired compiler caches and archived closed QA copies only."""
from contextlib import ExitStack, contextmanager
import fcntl
import fnmatch
from functools import lru_cache
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import stat
import subprocess
import tempfile
import time
import uuid

from scripts.devtools.core import (atomic_json, canonical_root,
                                   inspect_lock, probe, worktree_id)
from journal import Journal, digest

CACHE_PARTS = ('Build/Intermediates.noindex/Today.build',
               'Build/Intermediates.noindex/TodayModules.build',
               'Build/Intermediates.noindex/ExplicitPrecompiledModules',
               'Build/Intermediates.noindex/SwiftExplicitPrecompiledModules', 'CompilationCache.noindex', 'Index.noindex',
               'ModuleCache.noindex', 'SDKExplicitPrecompiledModules', 'SDKStatCaches.noindex')
CLOSED = ('passed', 'failed', 'interrupted')


def contained(base, path):
    """Reject symlink components, traversal, and even an aliased results root."""
    base, path = Path(base).absolute(), Path(path).absolute()
    if '..' in path.parts or path == base or base not in path.parents:
        raise ValueError('Path is outside the allowlisted root: ' + str(path))
    for parent in (base, *reversed(path.relative_to(base).parents), path.relative_to(base)):
        item = parent if parent.is_absolute() else base / parent
        if item.is_symlink():
            raise ValueError('Symlink is protected: ' + str(item))
    if base.resolve() != base or path.resolve() != path:
        raise ValueError('Noncanonical storage path: ' + str(path))
    return path


def tree(path, hashes=False):
    """No symlinks, special files or databases may enter a deletion manifest."""
    files = []
    for base, dirs, names in os.walk(path, followlinks=False):
        for name in sorted(dirs + names):
            item = Path(base) / name
            st = item.lstat()
            if stat.S_ISDIR(st.st_mode):
                continue
            if not stat.S_ISREG(st.st_mode) or name.endswith(('.sqlite', '.sqlite-wal', '.sqlite-shm', '.db')):
                raise ValueError('Non-regular file or database is protected: ' + str(item))
            entry = {'path': str(item.relative_to(path)), 'bytes': st.st_size,
                     'allocated': st.st_blocks * 512, 'mtime_ns': st.st_mtime_ns,
                     'device': st.st_dev, 'inode': st.st_ino}
            if hashes:
                entry['sha256'] = digest(item)
                if item.stat().st_mtime_ns != st.st_mtime_ns:
                    raise ValueError('File changed while hashing: ' + str(item))
            files.append(entry)
    return sorted(files, key=lambda x: x['path'])


def policy(root):
    value = json.loads((Path(root) / 'tests/qa/retention.json').read_text())
    if value.get('schema') != 1 or not isinstance(value.get('pins'), list):
        raise ValueError('Missing retention policy/pins')
    for key in ('passed_days', 'failed_days', 'cache_days'):
        if type(value[key]) is not int or value[key] < 1:
            raise ValueError('Retention days must be positive integers')
    return value


def references(root):
    """Current tracked text plus all open Issue/PR bodies/comments; failure closes apply."""
    documents = []
    names = probe(['git', 'ls-files', '--', '*.md', '*.json'], cwd=root).splitlines()
    for name in names:
        path = Path(root) / name
        if path.is_file() and not path.is_symlink():
            documents.append(path.read_text(errors='replace'))
    for kind in ('issues', 'pulls'):
        data = json.loads(probe(['gh', 'api', '--paginate', '--slurp',
                                 f'repos/luworks/one-app/{kind}?state=open&per_page=100'], cwd=root, timeout=30))
        for page in data:
            for item in page:
                documents.append(item.get('body') or '')
                number = item['number']
                comments = probe(['gh', 'api', '--paginate', '--slurp',
                                  f'repos/luworks/one-app/issues/{number}/comments?per_page=100'],
                                 cwd=root, timeout=30)
                documents.append(comments)
                if kind == 'pulls':
                    documents.append(probe(['gh', 'api', '--paginate', '--slurp',
                                            f'repos/luworks/one-app/pulls/{number}/comments?per_page=100'],
                                           cwd=root, timeout=30))
                    documents.append(probe(['gh', 'api', '--paginate', '--slurp',
                                            f'repos/luworks/one-app/pulls/{number}/reviews?per_page=100'],
                                           cwd=root, timeout=30))
    return '\n'.join(documents)


@lru_cache(maxsize=2)
def reference_index(refs):
    # Index reference tokens once; avoid searching megabytes of Issue text for
    # every file in a compiler cache. Ancestors retain any cited descendant.
    tokens = set(re.findall(r'[A-Za-z0-9_.~/-]+', refs))
    prefixes = set(tokens)
    for token in tokens:
        if '/' in token:
            prefixes.update(str(p) for p in Path(token).parents)
    return tokens, prefixes


def protected(results, path, config, refs):
    rel = str(path.relative_to(results))
    names = [rel] + [str(p.relative_to(results)) for p in path.rglob('*')]
    if any(fnmatch.fnmatch(name, pin) or fnmatch.fnmatch(name + '/', pin)
           for name in names for pin in config['pins']):
        return 'pinned'
    tokens, prefixes = reference_index(refs)
    if rel.startswith('devtools/derived-data/'):
        identity = path.relative_to(results).parts[2]
        # Root-only references protect all children. A Products-only reference
        # protects that sibling tree without making compiler caches evidence.
        if any(t.rstrip('/').split('/')[-1] == identity for t in tokens):
            return 'referenced'
    elif path.name in tokens:
        return 'referenced'
    return 'referenced' if str(path) in prefixes or rel in prefixes else None


def retired(root, results, identity, owned=False):
    lock = results / 'devtools/locks' / (identity + '.lock')
    contained(results, lock)
    status = inspect_lock(lock)
    metadata = status['metadata']
    if (status['held'] and not owned) or not metadata or not isinstance(metadata.get('owner'), str):
        return False
    owner = Path(metadata['owner'])
    if not owner.is_absolute() or worktree_id(owner) != identity or owner.exists():
        return False
    registered = probe(['git', 'worktree', 'list', '--porcelain'], cwd=root)
    if 'worktree ' + str(owner) + '\n' in registered + '\n':
        return False
    # A recycled PID can only cause conservative retention, never deletion.
    pid = metadata.get('pid')
    if type(pid) is not int or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return True
    except PermissionError:
        return False
    return False


def archived_copy(db, source, files, results):
    """Only byte-identical, coherent journal archives can replace raw source files."""
    rows = db.execute('''SELECT c.after_txt, s.data FROM event e
        JOIN content c ON c.event_uid=e.uid JOIN snapshot s ON s.event_uid=e.uid
        WHERE e.kind='qa.archive' ''')
    for destination, payload in rows:
        retained = Path(destination)
        try:
            contained(results / 'archives', retained)
            manifest = json.loads(payload)
            if {f['path'] for f in files} != {f['path'] for f in manifest}:
                continue
            expected = {f['path']: f for f in manifest}
            for file in files:
                entry = expected[file['path']]
                target = contained(retained, retained / file['path'])
                if (target.stat().st_size != file['bytes'] or entry['bytes'] != file['bytes']
                        or digest(source / file['path']) != entry['sha256']
                        or digest(target) != entry['sha256']):
                    break
            else:
                return str(retained)
        except (OSError, ValueError, KeyError, TypeError):
            continue
    return None


def candidates(root, config, refs='', now=None, owned_identity=None):
    now = time.time() if now is None else now
    results = canonical_root(root) / 'tests/results'
    if results.resolve() != results or results.is_symlink():
        raise ValueError('Results root must be canonical and not a symlink')
    items = []
    controls_safe(results)
    cache = results / 'devtools/derived-data'
    if cache.exists():
        contained(results, cache)
        for directory in sorted(cache.iterdir()):
            if not re.fullmatch('[0-9a-f]{20}', directory.name):
                continue
            try:
                contained(results, directory)
                if not retired(root, results, directory.name, owned=directory.name == owned_identity):
                    continue
                for part in CACHE_PARTS:
                    path = contained(results, directory / part)
                    if path.is_dir():
                        try:
                            files = tree(path)
                        except (OSError, ValueError):
                            continue
                        if not files:
                            continue
                        reason = protected(results, path, config, refs)
                        if files and max(f['mtime_ns'] / 1e9 for f in files) > now - config['cache_days'] * 86400:
                            reason = reason or 'young'
                        items.append({'path': str(path), 'kind': 'cache', 'identity': directory.name,
                                      'reason': reason, 'files': files})
            except (OSError, ValueError):
                continue
    # Raw evidence is never deleted without complete metadata and a verified archive.
    summaries = []
    for summary in (results / 'runs').glob('*/summary-retained.json'):
        try:
            contained(results, summary)
            data = json.loads(summary.read_text())
            if (data.get('status') not in CLOSED or not data.get('run_id') or not data.get('selection')
                    or data.get('journal_errors') or data.get('shutdown_error')):
                continue
            summaries.append((summary, data))
        except (OSError, ValueError):
            continue
    latest = {}
    for summary, data in summaries:
        lane = json.dumps(sorted(data['selection']))
        latest[lane] = max(latest.get(lane, (0, '')), (summary.stat().st_mtime_ns, str(summary.parent)))
    if summaries:
        controls_safe(results)
        with sqlite3.connect('file:' + str(results / 'activity.sqlite') + '?mode=ro', uri=True) as db:
            for summary, data in summaries:
                path = summary.parent
                lane = json.dumps(sorted(data['selection']))
                reason = protected(results, path, config, refs)
                if str(path) == latest[lane][1]:
                    reason = reason or 'latest-lane'
                try:
                    files = tree(path)
                    days = config['passed_days'] if data['status'] == 'passed' else config['failed_days']
                    if max([f['mtime_ns'] / 1e9 for f in files] + [summary.stat().st_mtime]) > now - days * 86400:
                        reason = reason or 'young'
                    closed = db.execute("SELECT props FROM event WHERE session=? AND kind IN ('qa.run','qa.run.result','qa.run.checkpoint') ORDER BY id DESC LIMIT 1",
                                        (data['run_id'],)).fetchone()
                    if not closed or json.loads(closed[0]).get('status') != data['status']:
                        reason = reason or 'missing-journal-closure'
                    archive = archived_copy(db, path, files, results) if not reason else None
                    if not archive:
                        reason = reason or 'no-complete-archive'
                    items.append({'path': str(path), 'kind': 'raw', 'identity': data.get('derived_data'),
                                  'simulator_name': data.get('simulator_name'),
                                  'archive': archive, 'reason': reason, 'files': files})
                except (OSError, ValueError):
                    continue
    return items


def erase(path, manifest, results):
    """Delete only inventoried regular files through no-follow directory descriptors."""
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    with ExitStack() as stack:
        descriptors = {}
        def directory(relative):
            if relative in descriptors:
                return descriptors[relative]
            if relative == '.':
                fd = os.open(path, flags)
            else:
                parent = str(Path(relative).parent)
                fd = os.open(Path(relative).name, flags, dir_fd=directory(parent))
            stack.callback(os.close, fd)
            descriptors[relative] = fd
            return fd
        anchored = stack.enter_context(directory_fd(path))
        descriptors['.'] = anchored
        directory('.')
        root_identity = os.fstat(anchored)
        for entry in manifest:
            with directory_fd(path) as current_root:
                check = os.fstat(current_root)
                if (check.st_dev, check.st_ino) != (root_identity.st_dev, root_identity.st_ino):
                    raise ValueError('Deletion root was replaced')
            parent = directory(str(Path(entry['path']).parent))
            name = Path(entry['path']).name
            fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=parent)
            try:
                st = os.fstat(fd)
                if (st.st_ino, st.st_dev, st.st_mtime_ns, st.st_size) != (
                        entry['inode'], entry['device'], entry['mtime_ns'], entry['bytes']):
                    raise ValueError('Changed file; deletion stopped: ' + name)
                # Confirm the directory still names the opened inode.
                if os.stat(name, dir_fd=parent, follow_symlinks=False).st_ino != st.st_ino:
                    raise ValueError('Replaced file; deletion stopped: ' + name)
                os.unlink(name, dir_fd=parent)
            finally:
                os.close(fd)
        # Empty directories only; unexpected new entries stop cleanup.
        for relative in sorted(descriptors, key=lambda x: len(Path(x).parts), reverse=True):
            if relative != '.':
                os.rmdir(Path(relative).name, dir_fd=directory(str(Path(relative).parent)))
    # Empty unvisited directories are left in place, never recursively swept.


def run(root, apply=False, now=None):
    root = Path(root).resolve()
    config = policy(root)
    items = candidates(root, config, now=now)
    # No remote work needed when age/ownership metadata already protects everything.
    if any(not item['reason'] for item in items):
        refs = references(root)
        items = candidates(root, config, refs, now=now)
    else:
        refs = ''
    result = {'schema': 1, 'apply': apply, 'eligible': [], 'protected': [], 'freed_bytes': 0, 'freed_allocated': 0}
    for item in items:
        compact = {k: v for k, v in item.items() if k != 'files'}
        compact.update(bytes=sum(f['bytes'] for f in item['files']), files=len(item['files']))
        result['protected' if item['reason'] else 'eligible'].append(compact)
    if not apply or not result['eligible']:
        return result
    results = canonical_root(root) / 'tests/results'
    session = 'storage-retention-' + uuid.uuid4().hex
    audit = contained(results, results / 'retention' / session)
    controls_safe(results)
    with safe_lock(results / 'devtools/locks/host-heavy.lock'), safe_lock(results / 'devtools/locks/retention.lock'), ExitStack() as stack:
        stack.enter_context(directory_fd(results))
        controls_safe(results)
        journal = Journal(results / 'activity.sqlite')
        stack.callback(journal.close)
        controls_safe(results)
        with directory_fd(audit, create=True):
            pass
        for item in items:
            if item['reason']:
                continue
            with ExitStack() as owned:
                apply_item(root, results, item, config, refs, session, audit, journal, result, owned)
        atomic_json(audit / 'result.json', result)
        journal.artifact(session, audit / 'result.json')
    result['audit'] = str(audit)
    return result


@contextmanager
def directory_fd(path, create=False):
    """Anchor every ancestor with no-follow opens, starting at the filesystem root."""
    path = Path(path).absolute()
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    with ExitStack() as stack:
        fd = os.open('/', flags)
        stack.callback(os.close, fd)
        for part in path.parts[1:]:
            if part in ('.', '..'):
                raise ValueError('Traversal is protected')
            if create:
                try:
                    os.mkdir(part, dir_fd=fd)
                except FileExistsError:
                    pass
            fd = os.open(part, flags, dir_fd=fd)
            stack.callback(os.close, fd)
        yield fd


@contextmanager
def safe_lock(path):
    """Preserve lock metadata and use its stable no-follow inode for mutual exclusion."""
    path = Path(path)
    with directory_fd(path.parent, create=True) as parent:
        fd = os.open(path.name, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600, dir_fd=parent)
        try:
            st = os.fstat(fd)
            if not stat.S_ISREG(st.st_mode) or st.st_nlink != 1:
                raise ValueError('Aliased/nonregular lock is protected')
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            named = os.stat(path.name, dir_fd=parent, follow_symlinks=False)
            if (named.st_dev, named.st_ino) != (st.st_dev, st.st_ino):
                raise ValueError('Lock inode was replaced')
            yield
        finally:
            os.close(fd)


def controls_safe(results):
    """Never pass a linked database or sidecar to SQLite's path-based API."""
    for name in ('activity.sqlite', 'activity.sqlite-wal', 'activity.sqlite-shm', 'activity.sqlite-journal'):
        path = contained(results, results / name)
        if path.exists():
            st = path.lstat()
            if not stat.S_ISREG(st.st_mode) or st.st_nlink != 1:
                raise ValueError('Aliased/nonregular QA database is protected')
    with directory_fd(results):
        pass


def apply_item(root, results, item, config, refs, session, audit, journal, result, stack):
    path = contained(results, Path(item['path']))
    identity = item['identity']
    if item['kind'] == 'cache':
        if not retired(root, results, identity):
            raise ValueError('Cache ownership changed')
        stack.enter_context(safe_lock(results / 'devtools/locks' / (identity + '.lock')))
        cache = results / 'devtools/derived-data' / identity
    else:
        if not identity or not item['simulator_name']:
            raise ValueError('Missing raw-run ownership')
        cache = Path(identity)
        stack.enter_context(safe_lock(Path(tempfile.gettempdir()).resolve() / ('today-qa-lock-' + hashlib.sha256(
            ('name:' + item['simulator_name']).encode()).hexdigest())))
    key = 'cache:' + str(cache)
    stack.enter_context(safe_lock(Path(tempfile.gettempdir()).resolve() / ('today-qa-lock-' + hashlib.sha256(key.encode()).hexdigest())))
    # Re-read policy, current remote references and complete candidate eligibility under locks.
    fresh_refs = references(root)
    fresh = candidates(root, policy(root), fresh_refs, owned_identity=identity if item['kind'] == 'cache' else None)
    match = next((x for x in fresh if x['path'] == str(path) and not x['reason']), None)
    if not match or match['files'] != item['files']:
        raise ValueError('Artifact eligibility changed under locks')
    controls_safe(results)
    if item['kind'] == 'raw':
        with sqlite3.connect('file:' + str(results / 'activity.sqlite') + '?mode=ro', uri=True) as db:
            if archived_copy(db, path, item['files'], results) != item['archive']:
                raise ValueError('Archive changed since plan')
    current = tree(path)
    if current != item['files']:
        raise ValueError('Artifact changed since plan')
    # lsof errors other than its documented no-match exit fail closed.
    opened = subprocess.run(['lsof', '-nP', '+D', str(path)], capture_output=True, text=True, timeout=30)
    if opened.returncode != 1 or opened.stdout or opened.stderr:
        raise ValueError('Open files or uncertain lsof result: ' + str(path))
    hashed = tree(path, hashes=True)
    if [{k: v for k, v in x.items() if k != 'sha256'} for x in hashed] != current:
        raise ValueError('Artifact changed during manifest')
    manifest = audit / (uuid.uuid4().hex + '.json')
    atomic_json(manifest, {**{k: v for k, v in item.items() if k != 'files'}, 'files': hashed})
    journal.artifact(session, manifest)
    journal.record(session, 'qa.retention.planned', str(path), snapshot={'manifest': str(manifest),
                   'sha256': digest(manifest), 'bytes': sum(f['bytes'] for f in hashed)})
    # Every destructive operation is preceded by a committed tombstone.
    try:
        if tree(path) != current:
            raise ValueError('Artifact changed immediately before deletion')
        erase(path, hashed, results)
    except BaseException:
        journal.record(session, 'qa.retention.partial', str(path), status='failed')
        raise
    result['freed_bytes'] += sum(f['bytes'] for f in hashed)
    result['freed_allocated'] += sum(f['allocated'] for f in hashed)
    journal.record(session, 'qa.retention.deleted', str(path), status='completed',
                   props={'bytes': sum(f['bytes'] for f in hashed)}, snapshot={'manifest': str(manifest)})

def after_run(root):
    """Best effort after final indexing; never changes the QA run's outcome."""
    try:
        if policy(root).get('automatic'):
            result = run(root, apply=True)
            print(json.dumps({'retention': {
                'eligible': len(result['eligible']), 'protected': len(result['protected']),
                'freed_bytes': result['freed_bytes'], 'audit': result.get('audit')}}), flush=True)
    except Exception as error:
        print('QA retention skipped: ' + str(error), flush=True)
