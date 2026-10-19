"""Read-only discovery, cross-process ownership, and build provenance."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import subprocess
import time
import uuid


def probe(argv, cwd=None):
    """Run only explicit read probes; never invoke a shell or xcrun."""
    env = dict(os.environ, GIT_OPTIONAL_LOCKS='0')
    return subprocess.check_output(argv, cwd=cwd, env=env, stderr=subprocess.PIPE,
                                   timeout=5).decode().strip()


def canonical_root(root):
    root = Path(root).resolve()
    dotgit = root / '.git'
    if dotgit.is_file():
        gitdir = (root / dotgit.read_text().split(':', 1)[1].strip()).resolve()
        common = gitdir / 'commondir'
        gitdir = (gitdir / common.read_text().strip()).resolve() if common.exists() else gitdir
        return gitdir.parent if gitdir.name == '.git' else root
    return root


def worktree_id(root):
    return hashlib.sha256(os.fsencode(Path(root).resolve())).hexdigest()[:20]


def state_root(root):
    return canonical_root(root) / 'tests/results/devtools'


def derived_data(root):
    return state_root(root) / 'derived-data' / worktree_id(root)


def read_json(path):
    try:
        data = json.loads(Path(path).read_text())
        return data if isinstance(data, dict) else None
    except (OSError, ValueError):
        return None


def atomic_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    try:
        with temporary.open('x') as stream:
            json.dump(data, stream, sort_keys=True, indent=2)
            stream.flush()
            os.fsync(stream.fileno())
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def inspect_lock(path):
    """Kernel lock is authoritative; old PID metadata never authorizes a kill."""
    path = Path(path)
    try:
        with path.open('r') as stream:
            try:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                held = True
            else:
                held = False
                fcntl.flock(stream, fcntl.LOCK_UN)
            try:
                metadata = json.load(stream)
            except ValueError:
                metadata = None
            return {'held': held, 'metadata': metadata}
    except FileNotFoundError:
        return {'held': False, 'metadata': None}


class ResourceBusy(RuntimeError):
    pass


class ResourceLock:
    """Persistent inode, nonblocking flock; never unlink a shared lock file."""
    def __init__(self, path, owner):
        self.path, self.owner, self.stream = Path(path), owner, None

    def __enter__(self):
        if self.stream is not None:
            raise RuntimeError('Lock instance is already acquired')
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.stream = self.path.open('a+')
        try:
            fcntl.flock(self.stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            self.stream.close()
            self.stream = None
            raise ResourceBusy(f'Resource locked: {self.path}') from None
        try:
            self.stream.seek(0)
            self.stream.truncate()
            json.dump({'pid': os.getpid(), 'host': platform.node(), 'owner': self.owner,
                       'token': uuid.uuid4().hex, 'acquired': time.time()}, self.stream)
            self.stream.flush()
            os.fsync(self.stream.fileno())
        except BaseException:
            self.__exit__(None, None, None)
            raise
        return self

    def __exit__(self, *exc):
        if self.stream:
            fcntl.flock(self.stream, fcntl.LOCK_UN)
            self.stream.close()
            self.stream = None


def host_lock(root):
    # One conservative host-heavy slot shared by every worktree of this project.
    return ResourceLock(state_root(root) / 'locks/host-heavy.lock', str(Path(root).resolve()))


def dd_lock(root):
    return ResourceLock(state_root(root) / 'locks' / (worktree_id(root) + '.lock'),
                        str(Path(root).resolve()))


def toolchain():
    developer = os.environ.get('DEVELOPER_DIR')
    if not developer:
        try:
            developer = probe(['/usr/bin/xcode-select', '-p'])
        except (OSError, subprocess.SubprocessError):
            developer = ''
    developer = Path(developer).resolve() if developer else None
    version = None
    if developer:
        try:
            with (developer.parent / 'version.plist').open('rb') as stream:
                version = plistlib.load(stream)
        except (OSError, ValueError, plistlib.InvalidFileException):
            pass
    sdks = []
    if developer:
        for path in sorted({p.resolve() for p in developer.glob('Platforms/*.platform/Developer/SDKs/*.sdk')}):
            settings = path / 'SDKSettings.plist'
            sdks.append({'path': str(path.resolve()), 'settings_sha256':
                         hashlib.sha256(settings.read_bytes()).hexdigest() if settings.is_file() else None})
    return {'developer_dir': str(developer) if developer else None, 'xcode': version, 'sdks': sdks}


def fingerprint(root, *, sdk='iphonesimulator', architecture=None, configuration='Debug', tools=None):
    """Hash current source bytes (including dirty/untracked inputs), not just HEAD."""
    root = Path(root).resolve()
    names = probe(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], root).split('\0')
    files = {}
    for name in sorted(set(names)):
        if not name or not (name.startswith(('ios/', 'scripts/', 'tests/fixtures/', '.github/')) or name == 'dev'
                            or Path(name).name in ('Package.resolved', 'package-lock.json', 'yarn.lock',
                                                   'pnpm-lock.yaml', 'uv.lock', 'requirements.txt', 'Gemfile.lock', 'Gemfile', 'mise.lock', '.mise.toml', '.swift-format', '.swiftlint.yml', 'ruff.toml', 'tool-pins.json')):
            continue
        if any(part in ('.build', '__pycache__', 'DerivedData') for part in Path(name).parts):
            continue
        path = root / name
        if path.is_symlink():
            # Include linked content as well as link identity in cache invalidation.
            files[name] = {'link': os.readlink(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
        elif path.is_file():
            files[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        else:
            files[name] = None  # Tracked deletion invalidates provenance as well.
    data = {'schema': 1, 'worktree': str(root), 'source_and_locks': files,
            'toolchain': toolchain() if tools is None else tools, 'sdk': sdk,
            'architecture': architecture or platform.machine(), 'configuration': configuration}
    return {'sha256': hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest(), 'inputs': data}


def record_build(root, current, products, *, returncode):
    """Call only after a real adapter's successful build, while holding dd_lock."""
    if returncode != 0 or not products:
        raise ValueError('Successful build and explicit products required')
    artifacts = {}
    for product in products:
        path = Path(product).resolve()
        if derived_data(root).resolve() not in path.parents:
            raise ValueError('Build products must belong to this worktree derived-data directory')
        artifacts[str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
    atomic_json(derived_data(root) / 'dev-provenance.json',
                {'worktree': str(Path(root).resolve()), 'fingerprint': current, 'products': artifacts})


def provenance(root, current):
    stored = read_json(derived_data(root) / 'dev-provenance.json')
    if not stored:
        return {'valid': False, 'reason': 'missing provenance'}
    if stored.get('worktree') != str(Path(root).resolve()) or stored.get('fingerprint') != current:
        return {'valid': False, 'reason': 'stale source, toolchain, options or worktree'}
    products = stored.get('products', {})
    if not isinstance(products, dict) or not products:
        return {'valid': False, 'reason': 'missing products'}
    for name, digest in products.items():
        path = Path(name)
        if (derived_data(root).resolve() not in path.resolve().parents or not path.is_file()
                or hashlib.sha256(path.read_bytes()).hexdigest() != digest):
            return {'valid': False, 'reason': 'missing or modified product'}
    return {'valid': True, 'reason': 'fingerprint and products match'}
