"""Manual install preflight: exact current main must have a green Today CI push run.

No installation, signing, receipt artifact or alternate test runner lives here.
"""
import hashlib
import json
from pathlib import Path
import plistlib
import re

from scripts.devtools.core import probe, toolchain

PRODUCTS = {'One': 'com.luworks.one', 'TodayWidgets': 'com.luworks.one.widgets',
            'ShareExtension': 'com.luworks.one.share'}
REQUIRED_JOBS = ('checks', 'today-required')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def tool_identity():
    """Compare tool bytes/version, independent of the host's Xcode path."""
    tools = toolchain()
    result = {'xcode': tools['xcode'], 'sdks': {
        Path(row['path']).name: row['settings_sha256'] for row in tools['sdks']
        if Path(row['path']).name.startswith(('iPhoneOS', 'iPhoneSimulator'))}}
    if not result['xcode'] or not result['sdks'] or any(not v for v in result['sdks'].values()):
        raise ValueError('main_gate_toolchain_unavailable')
    return result


def product_identity(app):
    """Only the three critical executables/Info identities, not a second archive scanner."""
    result = {}
    platform = plistlib.loads((app / 'Info.plist').read_bytes()).get('CFBundleSupportedPlatforms')
    for name, bundle_id in PRODUCTS.items():
        bundle = app if name == 'One' else app / ('PlugIns/' + name + '.appex')
        executable, info = bundle / name, bundle / 'Info.plist'
        if any(p.is_symlink() for p in (app, bundle, executable, info)):
            raise ValueError('main_gate_symlink_product')
        data = plistlib.loads(info.read_bytes())
        if (data.get('CFBundleIdentifier') != bundle_id or data.get('CFBundleExecutable') != name
                or not executable.is_file() or not executable.stat().st_size
                or platform not in (['iPhoneSimulator'], ['iPhoneOS'])
                or data.get('CFBundleSupportedPlatforms') != platform):
            raise ValueError('main_gate_product_identity_mismatch')
        result[name] = {'bundle_id': bundle_id, 'executable_sha256': digest(executable.read_bytes()),
                        'info_sha256': digest(info.read_bytes())}
    return result


def check_install(root, args, run):
    """Read GitHub live on every authorized manual install preflight; offline blocks."""
    sha, run_id = args.commit, getattr(args, 'main_run', '')
    if not re.fullmatch(r'[0-9a-f]{40}', sha) or not re.fullmatch(r'[1-9][0-9]*', str(run_id)):
        raise ValueError('main_gate_exact_commit_and_run_required')
    def api(path):
        return run(['gh', 'api', 'repos/luworks/one-app/' + path], root)
    def require_current():
        if json.loads(api('commits/main'))['sha'] != sha:
            raise ValueError('main_gate_current_main_mismatch')
    require_current()
    info = json.loads(api('actions/runs/' + str(run_id)))
    if (info.get('head_sha') != sha or info.get('head_branch') != 'main' or info.get('event') != 'push'
            or info.get('path') != '.github/workflows/today.yml' or info.get('status') != 'completed'
            or info.get('conclusion') != 'success'):
        raise ValueError('main_gate_completed_main_run_required')
    jobs = json.loads(api('actions/runs/' + str(run_id) + '/attempts/' + str(info['run_attempt'])
                          + '/jobs?per_page=100'))['jobs']
    conclusions = {job.get('name'): job.get('conclusion') for job in jobs}
    if any(conclusions.get(name) != 'success' for name in REQUIRED_JOBS):
        raise ValueError('main_gate_required_jobs_missing')
    tree = probe(['git', 'rev-parse', 'HEAD^{tree}'], root)
    tools = tool_identity()
    path = getattr(args, 'build_receipt', None)
    if path is None or path.is_symlink():
        raise ValueError('main_gate_device_build_receipt_required')
    build = json.loads(path.read_bytes())
    if (build.get('source') != sha or build.get('tree') != tree or build.get('source_after') != sha
            or build.get('dirty_after') != '' or type(build.get('exit')) is not int or build.get('exit') != 0
            or build.get('toolchain') != tools or build.get('signing_changes') is not False
            or build.get('automatic_provisioning_updates') is not False):
        raise ValueError('main_gate_device_build_provenance_mismatch')
    app = Path(build.get('app', ''))
    if not app.is_absolute() or app.name != 'One.app' or app.parent.name != 'Debug-iphoneos':
        raise ValueError('main_gate_device_product_required')
    if plistlib.loads((app / 'Info.plist').read_bytes()).get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
        raise ValueError('main_gate_device_product_required')
    if product_identity(app) != build.get('product_identity'):
        raise ValueError('main_gate_device_product_changed')
    # Reject an obsolete source or rerun that started while evidence was read.
    require_current()
    latest = json.loads(api('actions/runs/' + str(run_id)))
    if latest.get('run_attempt') != info['run_attempt'] or latest.get('status') != 'completed' or latest.get('conclusion') != 'success':
        raise ValueError('main_gate_run_changed')
    if probe(['git', 'rev-parse', 'HEAD'], root) != sha or probe(['git', 'status', '--porcelain'], root):
        raise ValueError('main_gate_source_changed')
    return {'sha': sha, 'run_id': str(run_id), 'jobs': list(REQUIRED_JOBS), 'phone': 'not_installed'}
