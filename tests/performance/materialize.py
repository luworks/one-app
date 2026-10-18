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


def tracked_files(revision):
    files = []
    for record in git('ls-tree', '-r', '-z', revision).split(b'\0'):
        if not record:
            continue
        metadata, name = record.split(b'\t', 1)
        mode, kind, _ = metadata.split()
        if kind != b'blob' or mode not in (b'100644', b'100755'):
            raise ValueError('unsupported tracked source member: ' + name.decode())
        files.append(name.decode())
    return files


def source_target(source, name):
    relative = Path(name)
    if relative.is_absolute() or '..' in relative.parts or not relative.parts:
        raise ValueError('invalid source path: ' + name)
    target = source / relative
    # Never follow a source symlink into an untracked tree or build cache.
    for part in (target, *target.parents):
        if part.is_symlink():
            raise ValueError('source symlink is unsupported: ' + str(part))
        if part == source:
            break
    if target.exists() and not target.is_file():
        raise ValueError('source member is not a regular file: ' + str(target))
    return target


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
    if args.source.is_symlink() or (args.update and not args.source.is_dir()):
        parser.error('mutable source must be a regular directory, not a symlink')
    # Sidecar provenance lives outside the build source; no cache/untracked traversal.
    state_path = args.source.parent / ('.' + args.source.name + '.materialize.json')
    previous = None
    if state_path.exists():
        previous = json.loads(state_path.read_text())
        if previous['source'] != str(args.source.resolve()):
            parser.error('materialization state belongs to another source')
        if previous['base'] != git('rev-parse', args.base).decode().strip():
            parser.error('changing baseline requires a new materialization')
    base = git('rev-parse', args.base).decode().strip()
    revision = git('rev-parse', args.revision).decode().strip()
    manifest = dict(base=base, revision=revision, update=args.update, source=str(args.source.resolve()), files=[])
    if not args.update:
        if state_path.exists():
            parser.error('new source has existing materialization state')
        if not args.instrumentation:
            parser.error('initial baseline requires explicit instrumentation-owned paths')
        args.evidence.mkdir(parents=True)
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
        patch = git('diff', '--binary', base, revision, '--', *paths)
        (args.evidence / 'instrumentation.patch').write_bytes(patch)
    else:
        if args.instrumentation:
            paths = args.instrumentation
        else:
            # Audit the complete target tree, not base..revision: an earlier candidate
            # may have changed a file that this revision restores to baseline bytes.
            paths = tracked_files(revision)
            required = set(tracked_files(base))
            if previous:
                required.update(previous['managed_paths'])
            removed = required - set(paths)
            if removed:
                parser.error('source deletions require a new materialization: ' + ', '.join(sorted(removed)))
    # Read and validate every requested file before mutating any existing source.
    # Missing selected blobs, deletions and symlink collisions must fail atomically
    # with respect to source writes (I/O failures during writes are still possible).
    prepared = [(name, source_target(args.source, name), git('show', f'{revision}:{name}')) for name in paths]
    args.evidence.mkdir(parents=True, exist_ok=True)
    for name, target, data in prepared:
        changed = not target.exists() or target.read_bytes() != data
        if changed:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        manifest['files'].append(dict(path=name, sha256=hashlib.sha256(data).hexdigest(), changed=changed))
    managed = set(previous['managed_paths']) if previous else set()
    managed.update(paths)
    state = dict(source=manifest['source'], base=base, revision=revision, managed_paths=sorted(managed))
    state_path.write_text(json.dumps(state, indent=2) + '\n')
    (args.evidence / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
