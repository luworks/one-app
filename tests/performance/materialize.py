#!/usr/bin/env python3
"""Create a frozen baseline plus identical instrumentation, then update a mutable build cache.

Archives/patches/manifests are retained outside the mutable source directory.
No branch checkout, clean, deletion or signing operation is performed.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile


def git(*args):
    return subprocess.check_output(['git', *args])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', default='fc683a7')
    parser.add_argument('--revision', required=True)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--evidence', required=True, type=Path)
    parser.add_argument('--instrumentation', action='append', default=[])
    parser.add_argument('--update', action='store_true')
    args = parser.parse_args()
    if args.evidence.exists():
        parser.error('select a new evidence directory')
    if args.update != args.source.exists():
        parser.error('initial source must be new; --update requires the existing mutable source')
    args.evidence.mkdir(parents=True)
    base = git('rev-parse', args.base).decode().strip()
    revision = git('rev-parse', args.revision).decode().strip()
    manifest = dict(base=base, revision=revision, update=args.update, source=str(args.source.resolve()), files=[])
    if not args.update:
        archive = git('archive', '--format=tar', base)
        (args.evidence / 'baseline-source.tar').write_bytes(archive)
        args.source.mkdir(parents=True)
        # Git-controlled paths only; reject links and path traversal before extraction.
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            for member in tar.getmembers():
                if member.issym() or member.islnk() or member.name.startswith('/') or '..' in Path(member.name).parts:
                    raise ValueError('unsupported archive member: ' + member.name)
            tar.extractall(args.source)
        paths = args.instrumentation
        if not paths:
            parser.error('initial baseline requires explicit instrumentation-owned paths')
        patch = git('diff', '--binary', base, revision, '--', *paths)
        (args.evidence / 'instrumentation.patch').write_bytes(patch)
    else:
        if not args.instrumentation and git('diff', '--name-only', '--diff-filter=D', base, revision).strip():
            parser.error('source deletions require a new materialization; this tool never deletes files')
        paths = args.instrumentation or git('diff', '--name-only', '--diff-filter=ACMR', base, revision).decode().splitlines()
    for name in paths:
        relative = Path(name)
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('invalid source path')
        data = git('show', f'{revision}:{name}')
        target = args.source / relative
        changed = not target.exists() or target.read_bytes() != data
        if changed:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        manifest['files'].append(dict(path=name, sha256=hashlib.sha256(data).hexdigest(), changed=changed))
    (args.evidence / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
