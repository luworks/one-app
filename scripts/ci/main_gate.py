"""Exact-main usability receipt, consumed by the existing release preflight.

No installation, signing, cached test result, or alternate test runner lives here.
"""
import hashlib
import io
import json
import os
from pathlib import Path
import plistlib
import re
import zipfile

from scripts.ci.policy import MAIN_PROFILE, MAIN_UI, MAIN_INTEGRATION, validate_report
from scripts.devtools.core import atomic_json, probe, toolchain
from scripts.testing import contract

PRODUCTS = {'One': 'com.luworks.one', 'TodayWidgets': 'com.luworks.one.widgets',
            'ShareExtension': 'com.luworks.one.share'}


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


def strict_tests(report, expected, *, optional_logic=False):
    """Reconcile actual leaves again; zero, retries with failure and skips cannot pass."""
    if (not expected or type(report.get('exit_code')) is not int
            or type(report.get('expected_count')) is not int
            or report.get('expected_count') != len(expected)
            or set(report.get('expected', expected)) != set(expected)):
        raise ValueError('main_gate_selection_mismatch')
    attempts = report.get('attempts', [])
    checked = contract.report(expected, attempts, exit_code=report.get('exit_code', 1),
                              allowed_skips=['benchmark', 'export'] if optional_logic else [],
                              skip_rules=contract.load_manifest()['skip_rules'])
    if (report.get('status') != 'passed' or report.get('errors') or checked['status'] != 'passed'
            or checked['missing'] or checked['unexpected_skips'] or checked.get('unexpected')
            or not attempts or any(a.get('status') not in ('passed', 'skipped') for a in attempts)
            or (not optional_logic and any(a.get('status') != 'passed' or a.get('source') != 'xcresult' for a in attempts))
            or report.get('executed_count') != checked['executed_count']
            or set(a['test'] for a in attempts) != set(expected)):
        raise ValueError('main_gate_incomplete_test_leaves')
    return {'expected': expected, 'attempts': attempts, 'expected_count': len(expected),
            'executed_count': checked['executed_count'], 'exit_code': 0, 'status': 'passed',
            'allowed_skips': checked['allowed_skips']}


def seal_acceptance(root, temporary, lanes):
    """Called only after all selected main lanes have actually completed."""
    env = os.environ
    if (env.get('GITHUB_EVENT_NAME') != 'push' or env.get('GITHUB_REF') != 'refs/heads/main'
            or not re.fullmatch(r'[0-9a-f]{40}', env.get('GITHUB_SHA', ''))):
        raise ValueError('main_gate_requires_main_push')
    sha = env['GITHUB_SHA']
    if probe(['git', 'rev-parse', 'HEAD'], root) != sha or probe(['git', 'status', '--porcelain'], root):
        raise ValueError('main_gate_source_changed')
    required = ['format', 'lint', 'business', 'build', 'integration', 'core-ui']
    if lanes != required:
        raise ValueError('main_gate_required_checks_missing')
    records = {}
    for lane in lanes:
        folder = temporary / ('today-artifacts-' + lane)
        report = json.loads((folder / 'report.json').read_bytes())
        validate_report(report, sha, lane)
        selected = json.loads((folder / 'accepted-selection.json').read_bytes())
        if selected.get('profile') != MAIN_PROFILE:
            raise ValueError('main_gate_profile_mismatch')
        records[lane] = {'report_sha256': digest((folder / 'report.json').read_bytes()),
                         'source_sha256': report['source_sha256'], 'executed': report['executed']}
        if lane in ('business', 'integration', 'core-ui'):
            expected = selected['execution']['selected']
            source = contract.inventory(root)
            if lane in ('integration', 'core-ui'):
                fixed = contract.expand(MAIN_UI if lane == 'core-ui' else MAIN_INTEGRATION,
                                        source, 'ui' if lane == 'core-ui' else 'integration')
                if expected != fixed:
                    raise ValueError('main_gate_fixed_selection_mismatch')
            test = json.loads((folder / 'test-report.json').read_bytes())
            records[lane]['tests'] = strict_tests(test, expected, optional_logic=lane == 'business')
            records[lane]['test_report_sha256'] = digest((folder / 'test-report.json').read_bytes())
    # Simulator proof and later signed device products are deliberately separate.
    from scripts.devtools.core import derived_data
    receipt = {'schema': 1, 'profile': MAIN_PROFILE, 'status': 'passed', 'sha': sha,
               'tree': probe(['git', 'rev-parse', 'HEAD^{tree}'], root),
               'event': 'push', 'ref': 'refs/heads/main', 'run_id': env['GITHUB_RUN_ID'],
               'run_attempt': env['GITHUB_RUN_ATTEMPT'], 'toolchain': tool_identity(),
               'simulator_products': product_identity(derived_data(root) / 'Build/Products/Debug-iphonesimulator/One.app'),
               'lanes': records, 'physical_device': 'not_tested', 'distribution': 'not_authorized'}
    destination = temporary / 'today-artifacts-main-acceptance'
    destination.mkdir(exist_ok=False)
    atomic_json(destination / 'main-acceptance.json', receipt)
    print(json.dumps({'main_acceptance': sha, 'profile': MAIN_PROFILE, 'status': 'passed'}))


def verify_receipt(receipt, *, sha, tree, run_id, attempt, tools, source):
    if (receipt.get('schema') != 1 or receipt.get('profile') != MAIN_PROFILE
            or receipt.get('status') != 'passed' or receipt.get('sha') != sha or receipt.get('tree') != tree
            or receipt.get('event') != 'push' or receipt.get('ref') != 'refs/heads/main'
            or str(receipt.get('run_id')) != str(run_id) or str(receipt.get('run_attempt')) != str(attempt)
            or receipt.get('toolchain') != tools):
        raise ValueError('main_gate_receipt_provenance_mismatch')
    lanes = receipt.get('lanes', {})
    if set(lanes) != {'format', 'lint', 'business', 'build', 'integration', 'core-ui'}:
        raise ValueError('main_gate_required_checks_missing')
    for lane, record in lanes.items():
        if type(record.get('executed')) is not int or record['executed'] <= 0:
            raise ValueError('main_gate_zero_results')
        for key in ('source_sha256', 'report_sha256'):
            if not re.fullmatch(r'[0-9a-f]{64}', record.get(key, '')):
                raise ValueError('main_gate_missing_result_provenance')
        if lane in ('business', 'integration', 'core-ui'):
            test = record['tests']
            expected = test['expected']
            if lane in ('integration', 'core-ui'):
                expected = contract.expand(MAIN_UI if lane == 'core-ui' else MAIN_INTEGRATION,
                                           source, 'ui' if lane == 'core-ui' else 'integration')
            strict_tests(test, expected, optional_logic=lane == 'business')
    products = receipt.get('simulator_products', {})
    if (set(products) != set(PRODUCTS)
            or any(products[n].get('bundle_id') != b for n, b in PRODUCTS.items())
            or any(not re.fullmatch(r'[0-9a-f]{64}', products[n].get(k, ''))
                   for n in PRODUCTS for k in ('executable_sha256', 'info_sha256'))):
        raise ValueError('main_gate_product_identity_mismatch')


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
    name = 'today-main-acceptance-' + sha + '-' + str(info['run_attempt'])
    artifacts = json.loads(api('actions/runs/' + str(run_id) + '/artifacts?per_page=100'))['artifacts']
    matching = [a for a in artifacts if a.get('name') == name and not a.get('expired')]
    if len(matching) != 1 or matching[0].get('size_in_bytes', 0) > 2 * 1024 * 1024:
        raise ValueError('main_gate_acceptance_artifact_missing')
    # Read only the compact receipt published by the existing job. Never extract a
    # remote archive or repeat complete xcresult/product hashing before install.
    data = api('actions/artifacts/' + str(matching[0]['id']) + '/zip')
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        paths = [p for p in archive.infolist() if p.filename.endswith('/main-acceptance.json')
                 or p.filename == 'main-acceptance.json']
        if len(paths) != 1 or paths[0].file_size > 1024 * 1024:
            raise ValueError('main_gate_acceptance_receipt_missing')
        receipt = json.loads(archive.read(paths[0]))
    tree = probe(['git', 'rev-parse', 'HEAD^{tree}'], root)
    tools = tool_identity()
    verify_receipt(receipt, sha=sha, tree=tree, run_id=run_id, attempt=info['run_attempt'],
                   tools=tools, source=contract.inventory(root))
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
    return {'sha': sha, 'run_id': str(run_id), 'profile': MAIN_PROFILE, 'phone': 'not_installed'}
