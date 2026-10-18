#!/usr/bin/env python3
"""Freeze an exact production base plus an explicit measurement-only path allowlist."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile


def git(*args):
    return subprocess.check_output(['git', *args])


def freeze(base, revision, paths, output):
    base = git('rev-parse', base).decode().strip()
    revision = git('rev-parse', revision).decode().strip()
    changed = set(git('diff', '--name-only', base, revision, '--', 'ios').decode().splitlines())
    if changed - set(paths):
        raise ValueError('unapproved iOS difference: ' + ', '.join(sorted(changed - set(paths))))
    if any(Path(p).is_absolute() or '..' in Path(p).parts for p in paths):
        raise ValueError('unsafe measurement path')
    archive = git('archive', '--format=tar', base)
    patch = git('diff', '--binary', base, revision, '--', *paths)
    # Validate all members and selected replacement blobs before creating output.
    with tarfile.open(fileobj=io.BytesIO(archive)) as bundle:
        members = bundle.getmembers()
        if any(not (m.isdir() or m.isfile()) or Path(m.name).is_absolute() or '..' in Path(m.name).parts for m in members):
            raise ValueError('unsupported archive member')
        replacements = [(p, git('show', revision + ':' + p)) for p in paths]
        output.mkdir(parents=True, exist_ok=False)
        source = output / 'source'
        source.mkdir()
        bundle.extractall(source)
    for name, data in replacements:
        p = source / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)
    (output / 'base.tar').write_bytes(archive)
    (output / 'measurement.patch').write_bytes(patch)
    manifest = dict(base=base, revision=revision, source=str(source.resolve()),
                    archive_sha256=hashlib.sha256(archive).hexdigest(),
                    patch_sha256=hashlib.sha256(patch).hexdigest(),
                    approved_ios_paths=sorted(changed),
                    measurements=[dict(path=p, sha256=hashlib.sha256(d).hexdigest()) for p, d in replacements])
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return manifest


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--base', required=True)
    p.add_argument('--revision', required=True)
    p.add_argument('--measurement-path', action='append', required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    print(json.dumps(freeze(a.base, a.revision, a.measurement_path, a.output), indent=2))
