"""Read-only ./dev commands. Build/test dispatch is intentionally not installed."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

from .core import (derived_data, fingerprint, inspect_lock, probe, provenance,
                   state_root, toolchain, worktree_id)
from .process import Redactor

ROOT = Path(__file__).resolve().parents[2]


def inventory(root):
    tools = toolchain()
    return {'worktree': str(root), 'worktree_id': worktree_id(root),
            'derived_data': str(derived_data(root)), 'toolchain': tools,
            'host_heavy': inspect_lock(state_root(root) / 'locks/host-heavy.lock'),
            'derived_data_lock': inspect_lock(state_root(root) / 'locks' / (worktree_id(root) + '.lock')),
            'existing_entrypoints': {name: str(root / path) for name, path in {
                'ui_runner': 'ios/Eval/run-e2e.py', 'preview': 'scripts/swiftui_preview.py'}.items()
                if (root / path).is_file()}}


def main(argv=None, root=ROOT):
    parser = argparse.ArgumentParser(prog='./dev', description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('help', help='show supported commands')
    sub.add_parser('doctor', help='read-only environment checks; no simulator boot')
    sub.add_parser('inventory', help='read-only worktree, locks and tools')
    plan = sub.add_parser('plan', help='read-only fingerprint and provenance; executes nothing')
    plan.add_argument('--sdk', default='iphonesimulator')
    plan.add_argument('--architecture')
    plan.add_argument('--configuration', choices=['Debug', 'Release'], default='Debug')
    args = parser.parse_args(argv)
    if args.command == 'help':
        parser.print_help()
        return 0
    try:
        root = Path(root).resolve()
        data = inventory(root)
        if args.command == 'doctor':
            checks = {'git': probe(['git', 'rev-parse', '--is-inside-work-tree'], root) == 'true',
                      'xcode': bool(data['toolchain']['xcode']),
                      'simulator_sdk': any('iPhoneSimulator' in s['path'] for s in data['toolchain']['sdks']),
                      'runner': 'ui_runner' in data['existing_entrypoints']}
            data['checks'] = checks
            code = 0 if all(checks.values()) else 1
        elif args.command == 'plan':
            current = fingerprint(root, sdk=args.sdk, architecture=args.architecture,
                                  configuration=args.configuration, tools=data['toolchain'])
            data.update({'fingerprint': current, 'provenance': provenance(root, current),
                         'execution_supported': False,
                         'next': 'Integrate an adapter using existing runner or preview entrypoint.'})
            code = 0
        else:
            code = 0
        print(Redactor()(json.dumps(data, indent=2, sort_keys=True)))
        return code
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print('dev: ' + Redactor()(str(error)), file=sys.stderr)
        return 1
