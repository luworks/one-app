"""Typed allowlists, dependency freshness and retained native capture evidence."""
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import struct
import threading
import time
import uuid
import zlib

from scripts.devtools.core import atomic_json, canonical_root, probe, worktree_id
from scripts.devtools.process import Evidence, Redactor, run_process


def sha(data):
    return hashlib.sha256(data).hexdigest()


def identifier(value):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,79}', value):
        raise ValueError('Invalid scene/scenario identifier')
    return value


def source_path(root, name):
    if (not isinstance(name, str) or not name or '\\' in name or
            any(p in ('', '.', '..') for p in name.split('/')) or PurePosixPath(name).is_absolute()):
        raise ValueError('Source must be a repository-relative file')
    path = root / name
    if not path.resolve().is_relative_to(root) or path.is_symlink() or path.is_dir():
        raise ValueError('Source escapes repository or is not a file')
    return path


@dataclass(frozen=True)
class Scene:
    id: str
    scenarios: tuple[str, ...]
    sources: tuple[str, ...]


@dataclass(frozen=True)
class Manifest:
    scenes: tuple[Scene, ...]
    locks: tuple[str, ...]

    @classmethod
    def parse(cls, data, root):
        root = Path(root).resolve()
        if (not isinstance(data, dict) or set(data) != {'schema', 'scenes', 'locks'} or
                type(data['schema']) is not int or data['schema'] != 1):
            raise ValueError('Expected TodayScenes manifest schema 1')
        def names(values, validate):
            if not isinstance(values, list) or not values:
                raise ValueError('Expected nonempty explicit allowlist')
            for value in values:
                validate(value)
            if len(set(values)) != len(values):
                raise ValueError('Duplicate allowlist member')
            return tuple(values)
        if not isinstance(data['locks'], list):
            raise ValueError('Expected lock file list')
        locks = names(data['locks'], lambda p: source_path(root, p)) if data['locks'] else ()
        if not isinstance(data['scenes'], list) or not data['scenes']:
            raise ValueError('Expected scenes')
        scenes = []
        for entry in data['scenes']:
            if not isinstance(entry, dict) or set(entry) != {'id', 'scenarios', 'sources'}:
                raise ValueError('Unexpected scene fields')
            scenes.append(Scene(identifier(entry['id']), names(entry['scenarios'], identifier),
                                names(entry['sources'], lambda p: source_path(root, p))))
        if len({s.id for s in scenes}) != len(scenes):
            raise ValueError('Duplicate scene')
        return cls(tuple(scenes), locks)

    def scene(self, scene, scenario):
        identifier(scene)
        identifier(scenario)
        for item in self.scenes:
            if item.id == scene and scenario in item.scenarios:
                return item
        raise ValueError('Scene/scenario is not allowlisted')


@dataclass(frozen=True)
class CaptureIdentity:
    device: str
    os: str


class NativeCommands:
    """Only these fixed argv cross the native adapter boundary."""
    def __init__(self, root, manifest, session, timeout=120, cancel=None):
        self.root, self.manifest, self.session = Path(root).resolve(), manifest, session
        self.timeout, self.cancel = timeout, cancel or threading.Event()

    def _run(self, argv):
        evidence = Evidence(self.root, self.session, Redactor())
        try:
            result = run_process(argv, cwd=self.root, evidence=evidence,
                                 timeout=self.timeout, cancel=self.cancel)
            if result.reason == 'cancelled':
                self.cancel.set()
            if result.returncode:
                raise RuntimeError(f'Native command {result.reason}; exit={result.returncode}; log={result.log}')
        finally:
            evidence.close()

    def capture(self, scene, scenario, output):
        self.manifest.scene(scene, scenario)
        output = Path(output)
        if (output.exists() or output.is_symlink() or output.with_suffix('.json').exists() or
                output.with_suffix('.json').is_symlink()):
            raise ValueError('Native output and receipt must be new')
        self._run(['./dev', 'ui', 'capture', '--scene', scene, '--scenario', scenario,
                   '--output', str(output)])
        # Written and closed by the native owner after the screenshot command exits.
        receipt_path = output.with_suffix('.json')
        if receipt_path.is_symlink():
            raise ValueError('Native receipt must be a regular file')
        receipt = json.loads(receipt_path.read_text())
        if (not isinstance(receipt, dict) or set(receipt) != {'device', 'os'} or
                not all(isinstance(v, str) and v for v in receipt.values())):
            raise ValueError('Native capture must supply device/os receipt')
        return CaptureIdentity(**receipt)

    def open(self, scene, scenario):
        self.manifest.scene(scene, scenario)
        self._run(['./dev', 'ui', 'open', '--scene', scene, '--scenario', scenario])


def validate_png(data):
    """Check closed PNG structure/CRCs; native capture remains the source of pixels."""
    if not data.startswith(b'\x89PNG\r\n\x1a\n'):
        raise ValueError('Capture is not PNG')
    offset, chunks = 8, []
    while offset + 12 <= len(data):
        size = struct.unpack('>I', data[offset:offset + 4])[0]
        end = offset + 12 + size
        if end > len(data):
            raise ValueError('Truncated PNG')
        kind, body = data[offset + 4:offset + 8], data[offset + 8:end - 4]
        if zlib.crc32(kind + body) & 0xffffffff != struct.unpack('>I', data[end - 4:end])[0]:
            raise ValueError('Invalid PNG CRC')
        chunks.append(kind)
        if kind == b'IHDR' and (size != 13 or not all(struct.unpack('>II', body[:8]))):
            raise ValueError('Invalid PNG dimensions')
        offset = end
        if kind == b'IEND':
            break
    if not chunks or chunks[0] != b'IHDR' or b'IDAT' not in chunks or chunks[-1] != b'IEND' or offset != len(data):
        raise ValueError('Incomplete PNG')


class Gallery:
    def __init__(self, root, manifest, *, capture=None, open_scene=None, journal=None,
                 session=None, debounce=0.3):
        self.root, self.manifest = Path(root).resolve(), manifest
        self.session = identifier(session or 'gallery-' + uuid.uuid4().hex)
        self.directory = (canonical_root(self.root) / 'tests/results/gallery' /
                          worktree_id(self.root) / self.session)
        self.directory.mkdir(parents=True, exist_ok=False)
        self.native = NativeCommands(self.root, manifest, self.session)
        self.capture_callback = capture or self.native.capture
        self.open_callback = open_scene or self.native.open
        if journal is None:
            evidence = Evidence(self.root, self.session, Redactor())
            journal = evidence.journal
        self.journal = journal
        self.entries, self.images = {}, {}
        self.selected, self.observed, self.pending = None, None, None
        self.debounce = debounce

    def fingerprint(self, scene):
        files = {}
        stamps = {}
        for name in sorted(set(scene.sources + self.manifest.locks)):
            try:
                path = source_path(self.root, name)
                files[name] = sha(path.read_bytes())
                stat = path.stat()
                stamps[name] = [stat.st_mtime_ns, stat.st_size]
            except (OSError, ValueError):
                files[name], stamps[name] = None, None
        data = {'scene': scene.id, 'scenarios': scene.scenarios, 'files': files}
        return {'sha256': sha(json.dumps(data, sort_keys=True).encode()),
                'inputs': files, 'stamps': stamps}

    def capture(self, scene, scenario):
        item = self.manifest.scene(scene, scenario)
        key = (scene, scenario)
        before = self.fingerprint(item)
        self.selected, self.observed, self.pending = key, before, None
        previous = self.entries.get(key, {}).get('last_good')
        attempt = {'scene': scene, 'scenario': scenario, 'started_at': time.time(),
                   'commit': probe(['git', 'rev-parse', 'HEAD'], self.root), 'fingerprint': before}
        output = self.directory / (uuid.uuid4().hex + '.png')
        try:
            if any(value is None for value in before['inputs'].values()):
                raise ValueError('Declared source/lock dependency is missing')
            identity = self.capture_callback(scene, scenario, output)
            if not isinstance(identity, CaptureIdentity) or not identity.device or not identity.os:
                raise ValueError('Capture identity required')
            if output.is_symlink() or not output.is_file():
                raise ValueError('Capture output must be a new regular PNG')
            data = output.read_bytes()
            validate_png(data)
            digest = sha(data)
            image_id = output.stem
            self.images[image_id] = (output, digest)
            self.journal.artifact(self.session, output)
            receipt = output.with_suffix('.json')
            if receipt.is_file() and not receipt.is_symlink():
                self.journal.artifact(self.session, receipt)
            good = {**attempt, 'captured_at': time.time(), 'device': identity.device, 'os': identity.os,
                    'path': str(output), 'sha256': digest, 'image': '/images/' + image_id,
                    'previous_sha256': previous['sha256'] if previous else None,
                    'image_changed': previous['sha256'] != digest if previous else None}
            status = 'fresh' if before == self.fingerprint(item) else 'stale'
            entry = {'status': status, 'last_good': good, 'attempt': attempt, 'error': None}
        except Exception as error:
            entry = {'status': 'stale' if previous else 'failed', 'last_good': previous,
                     'attempt': attempt, 'error': Redactor()(f'{type(error).__name__}: {error}')}
            # Closed failed output is evidence, never an image served as a success.
            if output.is_file() and not output.is_symlink():
                self.journal.artifact(self.session, output)
        entry['attempt']['finished_at'] = time.time()
        self.entries[key] = entry
        record = self.directory / (uuid.uuid4().hex + '.json')
        atomic_json(record, entry)
        self.journal.artifact(self.session, record)
        self.journal.record(self.session, 'qa.gallery.capture', str(record),
                            status='failed' if entry['error'] else 'passed')
        return entry

    def open(self, scene, scenario):
        self.manifest.scene(scene, scenario)
        self.open_callback(scene, scenario)
        self.journal.record(self.session, 'qa.gallery.open', f'{scene}/{scenario}', status='passed')

    def state(self):
        entries = []
        for scene in self.manifest.scenes:
            current = self.fingerprint(scene)
            for scenario in scene.scenarios:
                entry = dict(self.entries.get((scene.id, scenario),
                             {'status': 'failed', 'last_good': None, 'error': 'Not captured'}))
                good = entry['last_good']
                if good:
                    path = Path(good['path'])
                    try:
                        intact = not path.is_symlink() and sha(path.read_bytes()) == good['sha256']
                    except OSError:
                        intact = False
                    if good['fingerprint'] != current or not intact:
                        entry['status'] = 'stale'
                entries.append({'scene': scene.id, 'scenario': scenario, **entry})
        return {'entries': entries, 'selected': self.selected}

    def tick(self, now=None):
        """Poll only selected declared dependencies; coalesce edits until quiet."""
        if self.selected is None:
            return
        now = time.monotonic() if now is None else now
        current = self.fingerprint(self.manifest.scene(*self.selected))
        if current != self.observed:
            self.observed, self.pending = current, now
        if self.pending is not None and now - self.pending >= self.debounce:
            self.capture(*self.selected)

    def close(self):
        self.native.cancel.set()
        self.journal.close()
