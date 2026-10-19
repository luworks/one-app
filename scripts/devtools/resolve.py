"""Resolve only the versioned dependency authority; never update that authority."""
import json
from pathlib import Path
import re
import shutil

from .core import dd_lock, derived_data, host_lock

SCHEMES = ('Today', 'TodayMock', 'TodayWorkbench', 'TodayTests', 'TodaySnapshotTests')
FLAGS = ('-disableAutomaticPackageResolution', '-onlyUsePackageVersionsFromResolvedFile', '-skipPackageUpdates')
AUTHORITY = 'ios/Dependencies/Package.resolved'
WORKSPACE = 'ios/Today.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'


def _pins(path):
    data = json.loads(Path(path).read_text())
    if data.get('version') != 3 or not isinstance(data.get('pins'), list) or not data['pins']:
        raise ValueError('Expected nonempty Package.resolved v3: ' + str(path))
    result = {}
    for pin in data['pins']:
        identity, state = pin.get('identity'), pin.get('state', {})
        if (not isinstance(identity, str) or identity in result
                or not re.fullmatch(r'[a-f0-9]{40}', state.get('revision', ''))
                or not isinstance(state.get('version'), str) or not state['version']
                or pin.get('kind') != 'remoteSourceControl' or not pin.get('location')):
            raise ValueError('Invalid, duplicate or unversioned dependency pin: ' + str(path))
        result[identity] = pin
    return result


def _authority(root):
    path = root / AUTHORITY
    if not path.is_file():
        raise ValueError('Missing versioned dependency authority: ' + AUTHORITY + '; restore it before generate/resolve')
    pins = _pins(path)
    manifest = json.loads((root / 'docs/engineering/tool-pins.json').read_text())
    source = json.loads((root / 'ios/project.yml').read_text())
    pin = manifest['tools']['snapshot-testing']
    actual = pins.get('swift-snapshot-testing', {}).get('state', {})
    if (actual.get('version') != pin['version'] or actual.get('revision') != pin['git_revision']
            or source['packages']['SnapshotTesting'].get('exactVersion') != pin['version']):
        raise ValueError('SnapshotTesting source/manifest/dependency authority disagree')
    return pins


def locked_arguments(root):
    """Read-only build/test gate. Call under the caller's host/DD ownership."""
    root = Path(root).resolve()
    expected = _authority(root)
    if (not (root / WORKSPACE).is_file() or _pins(root / WORKSPACE) != expected
            or json.loads((root / WORKSPACE).read_text()) != json.loads((root / AUTHORITY).read_text())):
        raise ValueError('Workspace dependency lock missing or drifted; run ./dev resolve')
    return list(FLAGS)


def run(root, scheme='Today', *, timeout=600):
    """Restore ignored workspace lock, resolve exact pins, verify; no lock update mode.

    Network/cache population is possible during this explicit operation. Doctor
    and locked_arguments never invoke it. Exceptions remain actionable to CLI.
    """
    from . import commands  # Avoid commands -> resolve -> commands import cycles.
    root = Path(root).resolve()
    if scheme not in SCHEMES:
        raise ValueError('Unsupported resolve scheme: ' + scheme)
    expected = _authority(root)  # Fail before generation, evidence or lock writes.
    source = json.loads((root / 'ios/project.yml').read_text())
    if scheme not in source.get('schemes', {}):
        raise ValueError('Scheme absent from versioned project specification: ' + scheme)
    with host_lock(root), dd_lock(root):
        original = (root / AUTHORITY).read_bytes()
        if _authority(root) != expected:
            raise ValueError('Dependency authority changed before ownership acquired')
        if not (root / 'ios/Today.xcodeproj/project.pbxproj').is_file():
            code = commands.generate(root, timeout=timeout)
            if code:
                return code
        workspace = root / WORKSPACE
        if workspace.is_symlink() or any(p.is_symlink() for p in workspace.parents if p != root.parent):
            raise ValueError('Refusing symlink workspace dependency lock')
        workspace.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root / AUTHORITY, workspace)
        try:
            result = commands.execute(root, ['xcodebuild', '-resolvePackageDependencies',
                '-project', 'ios/Today.xcodeproj', '-scheme', scheme,
                '-derivedDataPath', str(derived_data(root)), *FLAGS], timeout=timeout)
            if (root / AUTHORITY).read_bytes() != original:
                raise ValueError('Versioned dependency authority changed during resolve; inspect concurrent edits')
            if result.returncode:
                return result.returncode
            if _pins(workspace) != expected:
                raise ValueError('Resolved dependency identities/revisions/versions drifted from authority')
            return 0
        finally:
            # xcodebuild may reformat or replace the ignored lock even on failure.
            # The versioned authority is never a destination, including failures.
            if workspace.is_symlink():
                workspace.unlink()
            workspace.write_bytes(original)
