import contextlib
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import materialize


class MaterializeTests(unittest.TestCase):
    def test_frozen_reference_copies_only_explicit_instrumentation(self):
        archive = io.BytesIO()
        with tarfile.open(fileobj=archive, mode='w') as tar:
            for name, data in [('app.swift', b'original production'), ('fixture.json', b'versioned fixture')]:
                member = tarfile.TarInfo(name)
                member.size = len(data)
                tar.addfile(member, io.BytesIO(data))

        def fake_git(*args):
            if args[0] == 'rev-parse':
                return (args[1] + '\n').encode()
            if args[0] == 'archive':
                return archive.getvalue()
            if args[0] == 'diff':
                return b'instrumentation-only diff'
            if args[0] == 'show' and args[1] == 'candidate:trace.swift':
                return b'identical measurement code'
            self.fail('Unexpected git read: ' + str(args))

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, evidence = root / 'source', root / 'evidence'
            argv = ['materialize.py', '--base', 'base', '--revision', 'candidate', '--source', str(source),
                    '--evidence', str(evidence), '--instrumentation', 'trace.swift']
            with patch('sys.argv', argv), patch.object(materialize, 'git', side_effect=fake_git), contextlib.redirect_stdout(io.StringIO()):
                materialize.main()
            self.assertEqual((source / 'app.swift').read_bytes(), b'original production')
            self.assertEqual((source / 'fixture.json').read_bytes(), b'versioned fixture')
            self.assertEqual((source / 'trace.swift').read_bytes(), b'identical measurement code')
            manifest = json.loads((evidence / 'manifest.json').read_text())
            self.assertEqual([f['path'] for f in manifest['files']], ['trace.swift'])
            self.assertTrue((evidence / 'baseline-source.tar').exists())


if __name__ == '__main__':
    unittest.main()
