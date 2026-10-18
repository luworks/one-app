#!/usr/bin/env python3
"""Read-only executable/dSYM verification; retain every tool output in a new directory."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


def verify(products, output):
    output.mkdir(parents=True, exist_ok=False)
    rows = []

    def run(label, command):
        result = subprocess.run(command, capture_output=True, text=True, timeout=30)
        (output / (label + '.stdout')).write_text(result.stdout)
        (output / (label + '.stderr')).write_text(result.stderr)
        return result

    for name, executable in [
        ('One', 'One.app/One'),
        ('TodayWidgets', 'One.app/PlugIns/TodayWidgets.appex/TodayWidgets'),
        ('ShareExtension', 'One.app/PlugIns/ShareExtension.appex/ShareExtension')
    ]:
        binary = products / executable
        suffix = '.app.dSYM' if name == 'One' else '.appex.dSYM'
        dsym = products / (name + suffix)
        a = run(name + '-binary-uuid', ['xcrun', 'dwarfdump', '--uuid', str(binary)])
        b = run(name + '-dsym-uuid', ['xcrun', 'dwarfdump', '--uuid', str(dsym)])
        pattern = r'UUID:\s+([A-Fa-f0-9-]+)\s+\(([^)]+)\)'
        left, right = set(re.findall(pattern, a.stdout)), set(re.findall(pattern, b.stdout))
        dwarf = run(name + '-verify', ['xcrun', 'dwarfdump', '--verify', str(dsym)])
        symbols = run(name + '-symbols', ['xcrun', 'nm', '-n', str(dsym / 'Contents/Resources/DWARF' / name)])
        address_pattern = r'^([0-9a-fA-F]+) [tT] _\$s' + str(len(name)) + re.escape(name)
        addresses = list(dict.fromkeys(re.findall(address_pattern, symbols.stdout, re.MULTILINE)))[:20]
        lookup = None
        for index, address in enumerate(addresses):
            result = run(name + '-lookup-' + str(index), ['xcrun', 'dwarfdump', '--lookup', '0x' + address, str(dsym)])
            lines = re.findall(r"Line info: file '([^']+)', line (\d+)", result.stdout)
            # A matching UUID alone is not a successful address-to-owned-source lookup.
            roots = ('/ios/' + name + '/', '/ios/Shared/')
            owned = [(path, int(line)) for path, line in lines if any(root in path for root in roots) and int(line) > 0]
            if result.returncode == 0 and owned:
                lookup = dict(address='0x' + address, source=owned)
                break
        row = dict(product=name, executable=str(binary), dsym=str(dsym),
                   sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
                   uuid_match=bool(left and left == right and a.returncode == b.returncode == 0),
                   uuids=sorted(left), dwarf_verify_exit=dwarf.returncode, source_lookup=lookup)
        row['passed'] = row['uuid_match'] and dwarf.returncode == 0 and lookup is not None
        rows.append(row)
    report = dict(scope='generic unsigned Release symbolication only; not runtime/signing/App Store acceptance',
                  products=rows, passed=all(row['passed'] for row in rows))
    (output / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--products', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    result = verify(args.products, args.output)
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result['passed'] else 1)
