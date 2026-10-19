"""Real local adapters. The UI/preview/test contracts retain orchestration ownership."""
import json
import os
from pathlib import Path
import shutil
import sys
import time

from .bootstrap import bootstrap as bootstrap_tools, BootstrapError
from .core import (atomic_json, dd_lock, derived_data, fingerprint, host_lock,
                   provenance, record_build, state_root)
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


def generate(root, timeout=600):
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
    current = fingerprint(root, configuration=configuration)
    operation = 'build-for-testing' if testing else 'build'
    command = ['xcodebuild', operation, '-project', 'ios/Today.xcodeproj', '-scheme', scheme,
               '-configuration', configuration, '-destination', 'generic/platform=iOS Simulator',
               '-derivedDataPath', str(derived_data(root)), '-jobs', '2', 'ARCHS=arm64']
    with host_lock(root), dd_lock(root):
        result = execute(root, command, timeout=timeout)
        if result.returncode:
            return result.returncode
        product = 'TodayMock' if scheme == 'TodayMock' else 'One'
        executable = derived_data(root) / f'Build/Products/{configuration}-iphonesimulator/{product}.app/{product}'
        if not executable.is_file() or fingerprint(root, configuration=configuration) != current:
            raise ValueError('Missing executable or source changed during build; provenance rejected')
        record_build(root, current, [executable], returncode=result.returncode)
    return 0


def testing_contract(root):
    sys.path.insert(0, str(root / 'scripts/testing'))
    import contract
    return contract


def test(root, group, *, only=(), timeout=600, full=False):
    contract = testing_contract(root)
    if group == 'unit':
        plan = contract.plan(['unit'])
        expected = plan['selectors']['logic']
        command = ['swift', 'test', '--package-path', 'ios', '--jobs', '2']
        if only:
            expected = contract.expand(only, contract.inventory(), 'logic')
            command += ['--filter', '|'.join('/'.join(x.split('/')[1:]) for x in expected)]
        result = execute(root, command, timeout=timeout, heavy=True)
        raw = result.log.read_text()
        report = contract.report(expected, contract.log_attempts(raw, 'logic'), result.returncode,
                                 raw_log=raw, allowed_skips=['benchmark'],
                                 skip_rules=contract.load_manifest()['skip_rules'])
        path = result.log.with_suffix('.report.json')
        atomic_json(path, report)
        print(json.dumps({'report': str(path), 'status': report['status'],
                          'executed': report['executed_count'], 'missing': len(report['missing'])}))
        return result.returncode or (0 if report['status'] == 'passed' else 1)
    command = [sys.executable, 'ios/Eval/run-e2e.py', '--full'] if full else [
        sys.executable, 'ios/Eval/run-e2e.py', '--group', group]
    if only:
        command = [sys.executable, 'ios/Eval/run-e2e.py']
        for value in only:
            command += ['--only', value]
    command += ['--simulator-name', 'Today-Dev-' + derived_data(root).name[:8],
                '--derived-data', str(derived_data(root))]
    return execute(root, command, timeout=timeout, heavy=True).returncode


def format_sources(root, *, check=False, timeout=600):
    paths = [str(p.relative_to(root)) for folder in ['ios/Sources', 'ios/One', 'ios/Development',
             'ios/TodayWidgets', 'ios/ShareExtension', 'ios/OneUITests', 'ios/Eval/Tests']
             if (root / folder).is_dir() for p in sorted((root / folder).rglob('*.swift'))]
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
    if action == 'preflight' or action == 'validate':
        return execute(root, [sys.executable, 'scripts/release/release.py', action, *options], timeout=timeout).returncode
    if action != 'archive':
        raise ValueError('Distribution requires separate explicit authorization and is not a default dev action')
    from .runtimes import command, environment
    return execute(root, command(root, ['bundle', '_4.0.16_', 'exec', 'fastlane', 'archive', *options]), env=environment(root), timeout=timeout, heavy=True).returncode
