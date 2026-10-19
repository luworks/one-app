"""Worktree-local, lock-enforced runtime installation through the verified mise binary."""
import json
import os
from pathlib import Path
import subprocess


def environment(root):
    root = Path(root).resolve()
    return dict(os.environ, MISE_DATA_DIR=str(root / '.dev-tools/runtime'),
                MISE_CACHE_DIR=str(root / '.dev-tools/runtime-cache'),
                MISE_TRUSTED_CONFIG_PATHS=str(root),
                BUNDLE_PATH=str(root / '.dev-tools/bundle'), BUNDLE_FROZEN='true',
                BUNDLE_DEPLOYMENT='true', BUNDLE_IGNORE_CONFIG='1')


def command(root, arguments):
    from .commands import tool
    return [tool(root, 'mise'), 'exec', '--', *arguments]


def install(root, timeout=600):
    from .commands import execute, tool
    env = environment(root)
    mise = tool(root, 'mise')
    config = subprocess.run([mise, 'ls', '--current', '--json'], cwd=root, env=env,
                            text=True, capture_output=True, check=True)
    selected = json.loads(config.stdout)
    for name, version in [('ruby', '3.3.12'), ('python', '3.14.8')]:
        entries = selected.get(name, [])
        if len(entries) != 1 or entries[0].get('version') != version:
            raise ValueError('Effective mise runtime override or missing pin: ' + name)
    result = execute(root, [mise, 'install', '--locked', 'ruby', 'python'], env=env, timeout=timeout)
    if result.returncode:
        return result.returncode
    probe = subprocess.run(command(root, ['gem', 'list', '--installed', 'bundler', '--version', '4.0.16']),
                           cwd=root, env=env, capture_output=True, text=True)
    if probe.returncode:
        result = execute(root, command(root, ['gem', 'install', 'bundler', '--version', '4.0.16', '--no-document']),
                         env=env, timeout=timeout)
        if result.returncode:
            return result.returncode
    result = execute(root, command(root, ['bundle', '_4.0.16_', 'check']), env=env, timeout=timeout)
    if result.returncode:
        result = execute(root, command(root, ['bundle', '_4.0.16_', 'install', '--jobs', '2', '--retry', '1']),
                         env=env, timeout=timeout)
        if result.returncode:
            return result.returncode
    for arguments in [['ruby', '--version'], ['python3', '--version'],
                      ['bundle', '_4.0.16_', 'exec', 'fastlane', '--version']]:
        result = execute(root, command(root, arguments), env=env, timeout=timeout)
        if result.returncode:
            return result.returncode
    return 0
