"""Generate native feature modules with byte-owned, reversible edits.

No subprocesses, Git operations, builds, or shared state are touched here.
"""
from __future__ import annotations

from contextlib import contextmanager
from dataclasses import dataclass, field
import hashlib
import json
import os
import tempfile
from pathlib import Path
import re
import stat


class FeatureError(RuntimeError):
    """Invalid project layout, name, or changed ownership."""


def _digest(data):
    return hashlib.sha256(data).hexdigest()


def _safe(root, relative):
    path = root / relative
    for parent in (path, *path.parents):
        if parent == root:
            break
        if parent.is_symlink():
            raise FeatureError(f'Symlink is not owned: {relative}')
    return path


@dataclass(frozen=True)
class Change:
    path: str
    before: bytes | None
    after: bytes
    mode: int = 0o644

    @property
    def before_sha256(self):
        return None if self.before is None else _digest(self.before)

    @property
    def after_sha256(self):
        return _digest(self.after)


@dataclass
class Manifest:
    root: Path
    name: str
    changes: list[Change] = field(default_factory=list)
    directories: list[Path] = field(default_factory=list)
    undone: bool = False
    verification_active: bool = False
    verification_manifest: Manifest | None = field(default=None, repr=False)

    def _check(self, change, expected):
        path = _safe(self.root, change.path)
        if expected is None:
            valid = not path.exists()
        else:
            valid = (path.is_file() and path.read_bytes() == expected
                     and stat.S_IMODE(path.stat().st_mode) == change.mode)
        if not valid:
            raise FeatureError(f'Ownership conflict: {change.path}')
        return path

    def _write(self, change):
        path = self._check(change, change.before)
        missing = []
        parent = path.parent
        while not parent.exists():
            missing.append(parent)
            parent = parent.parent
        for directory in reversed(missing):
            directory.mkdir()
            self.directories.append(directory)
        temporary_path = None
        try:
            with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
                temporary_path = Path(stream.name)
                stream.write(change.after)
                stream.flush()
                os.fsync(stream.fileno())
            temporary_path.chmod(change.mode)
            self._check(change, change.before)
            if change.before is None:
                # Publish exclusively; never overwrite a newly created collision.
                os.link(temporary_path, path)
            else:
                os.replace(temporary_path, path)
            self.changes.append(change)
        finally:
            if temporary_path is not None:
                temporary_path.unlink(missing_ok=True)

    def assert_owned(self):
        if self.undone:
            raise FeatureError('Transaction has already been undone')
        for change in self.changes:
            self._check(change, change.after)

    def undo(self):
        """Preflight every owned file; conflict leaves the entire manifest intact."""
        if self.undone:
            return
        if self.verification_active:
            raise FeatureError('App verification entry still active or has an ownership conflict')
        self.assert_owned()
        for change in reversed(self.changes):
            path = self._check(change, change.after)
            if change.before is None:
                path.unlink()
            else:
                path.write_bytes(change.before)
        for directory in reversed(self.directories):
            try:
                directory.rmdir()
            except OSError:
                # Never recursively delete a directory: new user files survive.
                pass
        self.undone = True

    def as_dict(self):
        return {'root': str(self.root), 'name': self.name, 'undone': self.undone,
                'files': [{'path': c.path, 'before_sha256': c.before_sha256,
                           'after_sha256': c.after_sha256} for c in self.changes]}

    def restore_verification(self):
        """Retry entry restoration after explicitly resolving an ownership conflict."""
        if self.verification_manifest is not None:
            self.verification_manifest.undo()
        self.verification_active = False

    @contextmanager
    def verification(self):
        """Temporarily replace the actual @main App, then restore exact bytes.

        Parent must build inside this context and keep the manifest in memory.
        This restores the entry only; use temporary() to undo generation too.
        """
        self.assert_owned()
        if self.verification_active:
            raise FeatureError('Verification already active')
        app = _safe(self.root, 'ios/App')
        entries = [p for p in app.glob('*.swift')
                   if re.search(r'@main(?:\s+@\w+(?:\([^)]*\))?)*\s+struct\s+\w+\s*:\s*App\b', p.read_text())]
        if len(entries) != 1:
            raise FeatureError('Expected one @main App entry in ios/App')
        entry = entries[0]
        relative = entry.relative_to(self.root).as_posix()
        _safe(self.root, relative)
        original = entry.read_bytes()
        content = (f'import SwiftUI\nimport {self.name}\n\n'
                   '@main\nstruct GeneratedFeatureVerificationApp: App {\n'
                   '    var body: some Scene {\n'
                   f'        WindowGroup {{ {self.name}Screen() }}\n'
                   '    }\n}\n').encode()
        transaction = Manifest(self.root, self.name)
        self.verification_manifest = transaction
        try:
            transaction._write(Change(relative, original, content,
                                      stat.S_IMODE(entry.stat().st_mode)))
            self.verification_active = True
            yield self
        finally:
            self.restore_verification()


def _insert(package, section, line):
    # Match Package's top-level arrays, not a product's nested targets array.
    products = re.search(r'(?m)^([ \t]+)products:[ \t]*\[', package)
    if products is None:
        raise FeatureError('Expected one Package products array')
    indent = products[1]
    marker = re.compile(r'(?m)^(' + re.escape(indent) + section + r': \[)[ \t]*$')
    line = indent + '  ' + line.lstrip()
    matches = list(marker.finditer(package))
    if len(matches) != 1:
        raise FeatureError(f'Expected one Package {section} array')
    at = matches[0].end()
    return package[:at] + '\n' + line + package[at:]


def _screen(name):
    title = name.removeprefix('Feature')
    return f'''import SwiftUI
import TodayCore
import TodayDesignSystem

/// A native starting screen. State stays local until the user acts.
@MainActor
public struct {name}Screen: View {{
    @State private var appearance = Appearance.default

    public init() {{}}

    public var body: some View {{
        NavigationStack {{
            Form {{
                Section("Appearance") {{
                    Picker("Preview appearance", selection: $appearance) {{
                        ForEach(Appearance.displayOrder) {{ choice in
                            Text(choice.title).tag(choice)
                        }}
                    }}
                    Button("Use system appearance") {{ appearance = .system }}
                        .buttonStyle(PressScale())
                }}
            }}
            .navigationTitle("{title}")
            .preferredColorScheme(appearance == .system ? nil :
                                  (appearance == .dark ? .dark : .light))
        }}
    }}
}}
'''.encode()


def create(root, name):
    """Return an owned Manifest; persist generation until manifest.undo().

    Name is an ASCII UpperCamelCase identifier, optionally prefixed Feature.
    All layout and collision checks happen before the first mutation.
    """
    if not isinstance(name, str) or not re.fullmatch(r'[A-Z][A-Za-z0-9]*', name):
        raise FeatureError('Name must be an ASCII UpperCamelCase Swift identifier')
    if name in {'Self', 'Any', 'Type', 'Protocol', 'Feature'}:
        raise FeatureError('Reserved or empty feature name')
    name = name if name.startswith('Feature') else 'Feature' + name
    root = Path(root).resolve(strict=True)
    package_path = _safe(root, 'ios/Package.swift')
    project_path = _safe(root, 'ios/project.yml')
    before_package = package_path.read_bytes()
    before_project = project_path.read_bytes()
    package = before_package.decode()
    if re.search(r'\b' + re.escape(name) + r'\b', package):
        raise FeatureError(f'Package collision: {name}')
    project = json.loads(before_project)
    if project.get('packages', {}).get('TodayModules', {}).get('path') != '.':
        raise FeatureError('Expected local TodayModules package')
    apps = []
    for target in project.get('targets', {}).values():
        if target.get('type') != 'application':
            continue
        if any(isinstance(s, dict) and s.get('path') == 'App' and not s.get('excludes')
               for s in target.get('sources', [])):
            apps.append(target)
    if not apps:
        raise FeatureError('Expected an application target compiling App directory')
    for target in apps:
        dependencies = target.setdefault('dependencies', [])
        if any(d.get('product') == name for d in dependencies):
            raise FeatureError(f'Project collision: {name}')
        dependencies.append({'package': 'TodayModules', 'product': name})
    directory = f'ios/Sources/Features/{name}'
    if _safe(root, directory).exists():
        raise FeatureError(f'Source collision: {directory}')
    link = f'ios/App/{name}LinkCheck.swift'
    if _safe(root, link).exists():
        raise FeatureError(f'Assembly collision: {link}')
    package = _insert(package, 'products',
                      f'        .library(name: "{name}", targets: ["{name}"]),')
    package = _insert(package, 'targets',
                      f'        .target(name: "{name}", dependencies: ["TodayCore", "TodayDesignSystem"], path: "Sources/Features/{name}"),')
    planned = [
        Change('ios/Package.swift', before_package, package.encode(),
               stat.S_IMODE(package_path.stat().st_mode)),
        Change('ios/project.yml', before_project,
               (json.dumps(project, indent=2) + '\n').encode(),
               stat.S_IMODE(project_path.stat().st_mode)),
        Change(f'{directory}/{name}Screen.swift', None, _screen(name)),
        Change(link, None, (f'import SwiftUI\nimport {name}\n\n'
                           '// Compiled by App assembly without adding production navigation.\n'
                           f'@MainActor\nprivate struct {name}LinkCheck: View {{\n'
                           f'    var body: some View {{ {name}Screen() }}\n}}\n').encode()),
    ]
    manifest = Manifest(root, name)
    for change in planned:
        manifest._check(change, change.before)
    try:
        for change in planned:
            manifest._write(change)
    except BaseException:
        manifest.undo()
        raise
    return manifest


@contextmanager
def temporary(root, name):
    """Generate, render from the App WindowGroup, then undo on any exit.

    Includes exceptions, KeyboardInterrupt, and SystemExit. A conflict raises
    FeatureError and retains the conflicting files for explicit recovery.
    """
    manifest = create(root, name)
    try:
        with manifest.verification():
            yield manifest
    finally:
        manifest.undo()
