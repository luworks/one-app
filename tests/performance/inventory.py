#!/usr/bin/env python3
"""Read-only bundle inventory. ZIP is a local compression proxy, never App Store size."""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import zipfile


def inventory(root):
    root = Path(root).resolve()
    files, categories, hashes = [], collections.Counter(), collections.defaultdict(list)
    for p in sorted(root.rglob('*')):
        if not p.is_file() or p.is_symlink():
            continue
        data = p.read_bytes()
        rel = str(p.relative_to(root))
        kind = ('Mach-O' if data[:4] in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe')
                else p.suffix.lower() or 'other')
        categories[kind] += len(data)
        digest = hashlib.sha256(data).hexdigest()
        hashes[digest].append(rel)
        files.append(dict(path=rel, bytes=len(data), category=kind, sha256=digest))
    # Temporary compressed bytes are internal scratch; all measured inputs and results are durable.
    with tempfile.TemporaryFile() as stream:
        with zipfile.ZipFile(stream, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for f in files:
                archive.write(root / f['path'], 'Payload/' + root.name + '/' + f['path'])
        compressed = stream.tell()
    binaries = {}
    for f in files:
        if f['category'] == 'Mach-O':
            binaries[f['path']] = {tool: subprocess.run(args + [str(root / f['path'])],
                text=True, capture_output=True).stdout for tool, args in
                [('file', ['file']), ('segments', ['size', '-m']), ('libraries', ['otool', '-L'])]}
    return dict(root=str(root), logical_bytes=sum(f['bytes'] for f in files),
                local_zip_deflate9_bytes=compressed, categories=dict(categories),
                largest=sorted(files, key=lambda f: f['bytes'], reverse=True)[:25],
                identical_files=[v for v in hashes.values() if len(v) > 1], files=files, binaries=binaries)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if not args.bundle.is_dir():
        parser.error('bundle must be an existing directory')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(inventory(args.bundle), indent=2) + '\n')
