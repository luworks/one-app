"""Real local adapters. The UI/preview/test contracts retain orchestration ownership."""
import json
from pathlib import Path
import shutil
import sys
import time
import uuid

from .bootstrap import bootstrap as bootstrap_tools, BootstrapError
from .core import (atomic_json, dd_lock, derived_data, fingerprint, host_lock,
                   record_build)
from .process import Evidence, Redactor, run_process


def execute(root, command, *, timeout=600, heavy=False, env=None):
    evidence = Evidence(root, 'dev-' + time.strftime('%Y%m%d-%H%M%S'), Redactor())
    try:
        if heavy:
            with host_lock(root), dd_lock(root):
                result = run_process(command, cwd=root, evidence=evidence, timeout=timeout, env=env)
        else:
            result = run_process(command, cwd=root, evidence=evidence, timeout=timeout, env=env)
        print(json.dumps({'exit': result.returncode, 'reason': result.reason,
                          'seconds': result.seconds, 'log': str(result.log)}))
        return result
    finally:
        evidence.close()


def bootstrap(root, *, tools=None, timeout=600):
    result = bootstrap_tools(root, tools=tools, timeout=timeout)
    if tools is None:
        from .runtimes import install
        code = install(root, timeout=timeout)
        if code:
            raise BootstrapError('Locked runtime bootstrap failed with exit ' + str(code))
    return result


def tool(root, name):
    planned = bootstrap_tools(root, tools=[name], plan=True)['tools'][0]
    if planned.get('executable'):
        return planned['executable']
    if name == 'swift-format':
        # Read-only selection; bootstrap separately authenticates the exact host build and binary.
        from .core import toolchain
        developer = toolchain()['developer_dir']
        if developer:
            path = Path(developer) / 'Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-format'
            if path.is_file():
                return str(path)
    raise BootstrapError('Missing verified ' + name + '; run ./dev bootstrap')


def generate(root, timeout=600, *, _locked=False):
    if not _locked:
        with host_lock(root), dd_lock(root):
            return generate(root, timeout, _locked=True)
    result = execute(root, [tool(root, 'xcodegen'), 'generate', '--spec', 'ios/project.yml'], timeout=timeout)
    if result.returncode:
        return result.returncode
    lock = root / 'ios/Dependencies/Package.resolved'
    if lock.is_file():
        destination = root / 'ios/Today.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(lock, destination)
    return 0


def build(root, configuration='Debug', *, scheme='Today', timeout=600, testing=False):
    operation = 'build-for-testing' if testing else 'build'
    command = ['xcodebuild', operation, '-project', 'ios/Today.xcodeproj', '-scheme', scheme,
               '-configuration', configuration, '-destination', 'generic/platform=iOS Simulator',
               '-derivedDataPath', str(derived_data(root)), '-jobs', '2', 'ARCHS=arm64']
    with host_lock(root), dd_lock(root):
        code = generate(root, timeout, _locked=True)
        if code:
            return code
        current = fingerprint(root, configuration=configuration, scheme=scheme, architecture='arm64')
        from .resolve import locked_arguments
        command += locked_arguments(root)
        maps = None
        if configuration == 'Release' and scheme == 'Today':
            maps = derived_data(root) / 'ReleaseMaps' / uuid.uuid4().hex
            maps.mkdir(parents=True)
            command += ['LD_GENERATE_MAP_FILE=YES', 'LD_MAP_FILE_PATH=' + str(maps / '$(TARGET_NAME)-$(PRODUCT_NAME).map')]
        result = execute(root, command, timeout=timeout)
        if result.returncode:
            return result.returncode
        product = {'Today': 'One', 'TodayMock': 'TodayMock', 'TodayWorkbench': 'TodayWorkbench'}[scheme]
        executable = derived_data(root) / f'Build/Products/{configuration}-iphonesimulator/{product}.app'
        if not executable.is_dir() or fingerprint(root, configuration=configuration, scheme=scheme, architecture='arm64') != current:
            raise ValueError('Missing executable or source changed during build; provenance rejected')
        products = [executable]
        if maps is not None:
            from scripts.release import release
            release.validate_resources(root, executable)
            release.bind_product_link_maps(root, executable, maps, result.log)
            release.validate_product_link_maps(root, executable, maps, target_names=True)
            products += sorted(path for path in maps.iterdir() if path.is_file())
            print(json.dumps({'release_maps': str(maps), 'exclusion': 'actual_simulator_products', 'signing': 'not_checked'}))
        record_build(root, current, products, returncode=result.returncode)
    return 0


def testing_contract(root):
    import importlib.util
    path = Path(root) / 'scripts/testing/contract.py'
    spec = importlib.util.spec_from_file_location('devtools_testing_contract', path)
    contract = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(contract)
    return contract


def test(root, group, *, only=(), timeout=600, full=False, _locked=False):
    from . import xcode_tests
    if full and (group not in ('ui', 'release') or only):
        raise ValueError('--full requires ui or release without --only')
    if group == 'release':
        if not full:
            raise ValueError('release collection requires explicit --full')
        # One host-heavy owner for the whole frozen final collection. Never retry.
        with host_lock(root), dd_lock(root):
            generated = generate(root, timeout, _locked=True)
            if generated:
                return generated
            first = test(root, 'unit', timeout=timeout, _locked=True)
            code = xcode_tests.run(root, testing_contract(root), ['ios-unit', 'integration', 'snapshot'],
                                   timeout=timeout, locked=True, reuse=True)
            first = first or code
            code = test(root, 'ui', timeout=timeout, full=True, _locked=True)
            return first or code
    contract = testing_contract(root)
    if group in ('ios-unit', 'integration', 'snapshot'):
        if not _locked:
            with host_lock(root), dd_lock(root):
                return test(root, group, only=only, timeout=timeout, _locked=True)
        generated = generate(root, timeout, _locked=True)
        if generated:
            return generated
        return xcode_tests.run(root, contract, [group], only=only, timeout=timeout, locked=True, reuse=True)
    if group == 'unit':
        source = contract.inventory(root)
        plan = contract.plan(['unit'], source)
        expected = plan['selectors']['logic']
        command = ['swift', 'test', '--package-path', 'ios', '--jobs', '2']
        if only:
            expected = contract.expand(only, source, 'logic')
            command += ['--filter', '|'.join('/'.join(x.split('/')[1:]) for x in expected)]
        result = execute(root, command, timeout=timeout, heavy=not _locked)
        raw = result.log.read_text()
        report = contract.report(expected, contract.log_attempts(raw, 'logic'), result.returncode,
                                 raw_log=raw, allowed_skips=['benchmark'],
                                 skip_rules=contract.load_manifest()['skip_rules'])
        path = result.log.with_suffix('.report.json')
        atomic_json(path, report)
        evidence = Evidence(root, 'dev-unit-report-' + path.stem, Redactor())
        try:
            evidence.journal.artifact(evidence.session, path)
        finally:
            evidence.close()
        print(json.dumps({'report': str(path), 'status': report['status'],
                          'executed': report['executed_count'], 'missing': len(report['missing'])}))
        return result.returncode or (0 if report['status'] == 'passed' else 1)
    if group not in ('ui', 'core', 'accessibility'):
        raise ValueError('Unknown test group: ' + group)
    # Validate before launching the existing UI authority; it owns UI parsing/lifecycle.
    source = contract.inventory(root)
    if only:
        selected = contract.expand(only, source, 'ui')
        allowed = contract.plan([group], source)['selectors']['ui']
        if set(selected) - set(allowed):
            raise ValueError('Selection outside requested UI group')
        command = [sys.executable, 'ios/Eval/run-e2e.py']
        for value in selected:
            command += ['--only', value]
    else:
        command = [sys.executable, 'ios/Eval/run-e2e.py', '--full'] if full else [
            sys.executable, 'ios/Eval/run-e2e.py', '--group', group]
    command += ['--simulator-name', xcode_tests.simulator_name(root),
                '--derived-data', str(derived_data(root))]
    return execute(root, command, timeout=timeout, heavy=not _locked).returncode


def format_sources(root, *, check=False, timeout=600):
    from .core import probe
    paths = sorted({name for name in probe(
        ['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], root).split('\0')
        if name.startswith('ios/') and name.endswith('.swift') and (root / name).is_file()})
    command = [tool(root, 'swift-format'), 'lint' if check else 'format', '--recursive']
    command += ['--strict'] if check else ['--in-place']
    return execute(root, [*command, *paths], timeout=timeout).returncode


def lint(root, timeout=600):
    commands = [[tool(root, 'swiftlint'), 'lint', '--strict', '--config', '.swiftlint.yml'],
                [tool(root, 'ruff'), 'check', '--config', 'ruff.toml', 'scripts/devtools',
                 'scripts/ci', 'scripts/testing', 'scripts/release', 'tests/devtools', 'tests/ci', 'tests/testing', 'tests/release']]
    if (root / '.github/workflows').is_dir():
        commands.append([tool(root, 'actionlint'), '-shellcheck=', '-pyflakes='])
    for command in commands:
        result = execute(root, command, timeout=timeout)
        if result.returncode:
            return result.returncode
    return 0


def release(root, action, options=(), timeout=600):
    if action in ('preflight', 'validate', 'preflight-local', 'validate-local'):
        return execute(root, [sys.executable, 'scripts/release/release.py', action, *options], timeout=timeout).returncode
    if action not in ('archive', 'archive-local'):
        raise ValueError('Distribution requires separate explicit authorization and is not a default dev action')
    from .runtimes import command, environment
    return execute(root, command(root, ['bundle', '_4.0.16_', 'exec', 'fastlane', 'ios', 'archive_local' if action == 'archive-local' else 'archive', *options]), env=environment(root), timeout=timeout, heavy=True).returncode
