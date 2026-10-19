"""No app, Xcode, simulator or downloads: fake native pixels/callbacks only."""
import http.client
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import threading
import unittest
from unittest.mock import patch, Mock
import zlib

from scripts.gallery import CaptureIdentity, Gallery, GalleryServer, Manifest, NativeCommands
from scripts.gallery.adapter import sha, validate_png


def png(red=0):
    # A versioned inline synthetic test input; never used by the production adapter.
    def chunk(kind, body):
        return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body) & 0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(bytes([0, red, 0, 0]))) + chunk(b'IEND', b''))


class Journal:
    def __init__(self):
        self.files, self.events = [], []

    def artifact(self, session, path):
        self.files.append((Path(path), sha(Path(path).read_bytes())))

    def record(self, *args, **kwargs):
        self.events.append((args, kwargs))

    def close(self):
        pass


class GalleryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        subprocess.run(['git', '-C', str(self.root), '-c', 'user.email=test@example.invalid',
                        '-c', 'user.name=Test', 'commit', '--allow-empty', '-qm', 'Test base'], check=True)
        (self.root / 'view.swift').write_text('original')
        (self.root / 'other.swift').write_text('other')
        (self.root / 'Package.resolved').write_text('lock')
        self.data = {'schema': 1, 'locks': ['Package.resolved'], 'scenes': [
            {'id': 'today', 'scenarios': ['normal', 'empty'], 'sources': ['view.swift']}]}
        self.manifest = Manifest.parse(self.data, self.root)
        self.journal, self.calls, self.opens = Journal(), [], []
        self.pixel, self.failure = 0, None

        def capture(scene, state, output):
            self.calls.append((scene, state, output))
            if self.failure:
                raise self.failure
            output.write_bytes(png(self.pixel))
            return CaptureIdentity('Owned Test Device', 'Test OS 1')
        self.gallery = Gallery(self.root, self.manifest, capture=capture,
                               open_scene=lambda *args: self.opens.append(args), journal=self.journal)
        self.addCleanup(self.gallery.close)

    def test_failed_capture_retains_last_good_and_never_uses_hash_as_success(self):
        first = self.gallery.capture('today', 'normal')
        self.assertEqual(first['status'], 'fresh')
        same = self.gallery.capture('today', 'normal')
        self.assertEqual(same['status'], 'fresh')
        self.assertFalse(same['last_good']['image_changed'])
        self.assertNotEqual(first['last_good']['path'], same['last_good']['path'])
        self.failure = RuntimeError('capture failed')
        failed = self.gallery.capture('today', 'normal')
        self.assertEqual(failed['status'], 'stale')
        self.assertEqual(failed['last_good'], same['last_good'])
        self.assertIn('capture failed', failed['error'])
        self.assertEqual(self.gallery.capture('today', 'empty')['status'], 'failed')
        def changed_but_failed(scene, scenario, output):
            output.write_bytes(png(255))
            raise RuntimeError('native failed after writing new pixels')
        self.gallery.capture_callback = changed_but_failed
        image_count = len(self.gallery.images)
        result = self.gallery.capture('today', 'normal')
        self.assertEqual(result['status'], 'stale')
        self.assertEqual(result['last_good'], same['last_good'])
        self.assertEqual(len(self.gallery.images), image_count)

    def test_real_image_byte_change_is_reported_with_provenance(self):
        first = self.gallery.capture('today', 'normal')['last_good']
        self.pixel = 255
        second = self.gallery.capture('today', 'normal')['last_good']
        self.assertTrue(second['image_changed'])
        self.assertEqual(second['previous_sha256'], first['sha256'])
        self.assertNotEqual(first['sha256'], second['sha256'])
        self.assertEqual(second['device'], 'Owned Test Device')
        self.assertTrue(second['commit'])
        self.assertTrue(all(path.is_file() and sha(path.read_bytes()) == digest
                            for path, digest in self.journal.files))

    def test_dependency_watch_coalesces_and_ignores_unrelated_edit(self):
        self.gallery.capture('today', 'normal')
        (self.root / 'other.swift').write_text('unrelated change')
        self.gallery.tick(1)
        self.gallery.tick(2)
        self.assertEqual(len(self.calls), 1)
        (self.root / 'view.swift').write_text('one')
        self.assertEqual(self.gallery.state()['entries'][0]['status'], 'stale')
        self.gallery.tick(3)
        (self.root / 'view.swift').write_text('two')
        self.gallery.tick(3.2)
        self.gallery.tick(3.4)
        self.assertEqual(len(self.calls), 1)
        self.gallery.tick(3.6)
        self.assertEqual(len(self.calls), 2)
        (self.root / 'Package.resolved').write_text('new lock')
        self.gallery.tick(4)
        self.gallery.tick(4.4)
        self.assertEqual(len(self.calls), 3)

    def test_mtime_only_and_same_mtime_content_changes_are_watched(self):
        self.gallery.capture('today', 'normal')
        path = self.root / 'view.swift'
        before = path.stat()
        os.utime(path, ns=(before.st_atime_ns, before.st_mtime_ns + 1000000))
        self.gallery.tick(1)
        self.gallery.tick(1.4)
        self.assertEqual(len(self.calls), 2)
        stamp = path.stat()
        path.write_text('different content')
        os.utime(path, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
        self.gallery.tick(2)
        self.gallery.tick(2.4)
        self.assertEqual(len(self.calls), 3)

    def test_missing_dependency_invalid_image_and_during_capture_edit(self):
        self.gallery.capture('today', 'normal')
        (self.root / 'view.swift').unlink()
        self.assertEqual(self.gallery.capture('today', 'normal')['status'], 'stale')
        self.assertEqual(len(self.calls), 1)
        (self.root / 'view.swift').symlink_to(self.root / 'other.swift')
        self.gallery.tick(1)
        self.assertEqual(self.gallery.capture('today', 'normal')['status'], 'stale')
        self.assertEqual(len(self.calls), 1)
        (self.root / 'view.swift').unlink()
        (self.root / 'view.swift').write_text('restored')
        def partial(scene, scenario, output):
            output.write_bytes(png()[:-1])
            return CaptureIdentity('Device', 'OS')
        self.gallery.capture_callback = partial
        self.assertEqual(self.gallery.capture('today', 'normal')['status'], 'stale')
        def edited(scene, scenario, output):
            output.write_bytes(png())
            (self.root / 'view.swift').write_text('changed while capturing')
            return CaptureIdentity('Device', 'OS')
        self.gallery.capture_callback = edited
        self.assertEqual(self.gallery.capture('today', 'normal')['status'], 'stale')

    def test_manifest_rejects_untyped_fields_traversal_symlinks_and_commands(self):
        for source in ['../view.swift', '/tmp/file', 'a/../b', 'a\\b', 'a//b', './view.swift']:
            data = json.loads(json.dumps(self.data))
            data['scenes'][0]['sources'] = [source]
            with self.subTest(source=source), self.assertRaises(ValueError):
                Manifest.parse(data, self.root)
        (self.root / 'linked').symlink_to(self.root / 'view.swift')
        self.data['scenes'][0]['sources'] = ['linked']
        with self.assertRaises(ValueError):
            Manifest.parse(self.data, self.root)
        for scene in ['../today', '--help', 'today;touch x', ['today'], None]:
            with self.subTest(scene=scene), self.assertRaises(ValueError):
                self.gallery.capture(scene, 'normal')
        with self.assertRaises(ValueError):
            Manifest.parse({'schema': 1, 'scenes': [], 'locks': [], 'command': 'sh'}, self.root)
        with self.assertRaises(ValueError):
            Gallery(self.root, self.manifest, journal=self.journal, session='../escape')

    def test_fixed_native_argv_timeout_cancel_and_closed_receipt(self):
        native = NativeCommands(self.root, self.manifest, 'test', timeout=7)
        output = self.gallery.directory / 'new.png'
        def run(argv, **kwargs):
            output.write_bytes(png())
            output.with_suffix('.json').write_text(json.dumps({'device': 'D', 'os': 'OS'}))
            self.assertEqual(kwargs['timeout'], 7)
            self.assertIs(kwargs['cancel'], native.cancel)
            return Mock(returncode=0, reason='exited')
        with patch('scripts.gallery.adapter.Evidence') as evidence, patch('scripts.gallery.adapter.run_process', side_effect=run) as process:
            self.assertEqual(native.capture('today', 'normal', output), CaptureIdentity('D', 'OS'))
            self.assertEqual(process.call_args.args[0], ['./dev', 'ui', 'capture', '--scene', 'today',
                                                       '--scenario', 'normal', '--output', str(output)])
            with self.assertRaisesRegex(ValueError, 'must be new'):
                native.capture('today', 'normal', output)
            native.open('today', 'empty')
            self.assertEqual(process.call_args.args[0], ['./dev', 'ui', 'open', '--scene', 'today', '--scenario', 'empty'])
            self.assertEqual(evidence.return_value.close.call_count, 2)
            process.return_value = Mock(returncode=124, reason='timeout', log='closed.log')
            process.side_effect = None
            with self.assertRaisesRegex(RuntimeError, 'timeout'):
                native.open('today', 'normal')
            process.return_value = Mock(returncode=130, reason='cancelled', log='closed.log')
            with self.assertRaisesRegex(RuntimeError, 'cancelled'):
                native.open('today', 'normal')
            self.assertTrue(native.cancel.is_set())

    def start_server(self):
        server = GalleryServer(self.gallery, watch=False)
        thread = threading.Thread(target=server.serve_forever, kwargs={'poll_interval': .01})
        thread.start()
        self.addCleanup(lambda: (server.shutdown(), thread.join(), server.server_close()))
        return server

    def request(self, server, method, path, body=None, *, headers=None):
        connection = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=3)
        base = {'Authorization': 'Bearer ' + server.token, 'Origin': server.origin,
                'Content-Type': 'application/json'}
        base.update(headers or {})
        connection.request(method, path, body, base)
        response = connection.getresponse()
        result = response.status, dict(response.getheaders()), response.read()
        connection.close()
        return result

    def test_safe_routes_auth_and_native_open(self):
        server = self.start_server()
        body = json.dumps({'scene': 'today', 'scenario': 'normal'})
        status, headers, _ = self.request(server, 'POST', '/api/open', body)
        self.assertEqual(status, 200)
        self.assertEqual(self.opens, [('today', 'normal')])
        self.assertNotIn('Access-Control-Allow-Origin', headers)
        self.assertEqual(self.request(server, 'GET', '/api/open')[0], 404)
        self.assertEqual(len(self.opens), 1)
        self.assertEqual(self.request(server, 'POST', '/api/capture', body)[0], 200)
        image = self.gallery.state()['entries'][0]['last_good']['image']
        self.assertEqual(self.request(server, 'GET', image)[2], png())
        Path(self.gallery.state()['entries'][0]['last_good']['path']).write_bytes(png(255))
        self.assertEqual(self.gallery.state()['entries'][0]['status'], 'stale')
        self.assertEqual(self.request(server, 'GET', image)[0], 409)
        self.assertEqual(self.request(server, 'GET', '/api/state', headers={'Authorization': ''})[0], 401)
        self.assertEqual(self.request(server, 'GET', image, headers={'Authorization': ''})[0], 401)

    def test_lan_cors_csrf_and_path_injection_rejected(self):
        server = self.start_server()
        body = json.dumps({'scene': 'today', 'scenario': 'normal'})
        for headers in [{'Host': 'localhost:' + str(server.server_port)}, {'Host': '192.168.1.1'},
                        {'Host': 'evil.invalid'}, {'Origin': 'null'}, {'Origin': 'https://evil.invalid'},
                        {'Origin': ''}, {'Sec-Fetch-Site': 'cross-site'}, {'Authorization': 'Bearer wrong'}]:
            with self.subTest(headers=headers):
                self.assertIn(self.request(server, 'POST', '/api/open', body, headers=headers)[0], (401, 403))
        for path in ['/api/open?scene=today', '/api/%6fpen', '/api/open/../open', '/images/../../dev']:
            with self.subTest(path=path):
                self.assertEqual(self.request(server, 'POST', path, body)[0], 404)
        for payload in [{'scene': '../today', 'scenario': 'normal'}, {'scene': 'today', 'scenario': 'no'},
                        {'scene': 'today', 'scenario': 'normal', 'output': '/tmp/escape'},
                        {'scene': 'today', 'scenario': 'normal', 'command': 'sh'}]:
            self.assertEqual(self.request(server, 'POST', '/api/open', json.dumps(payload))[0], 400)
        self.assertEqual(self.request(server, 'OPTIONS', '/api/open')[0], 403)
        self.assertEqual(self.opens, [])
        with self.assertRaises(ValueError):
            GalleryServer(self.gallery, host='0.0.0.0')

    def test_duplicate_json_keys_and_missing_origin_are_rejected(self):
        server = self.start_server()
        self.assertEqual(self.request(server, 'POST', '/api/open',
                         '{"scene":"today","scene":"today","scenario":"normal"}')[0], 400)
        connection = http.client.HTTPConnection('127.0.0.1', server.server_port)
        connection.request('POST', '/api/open', json.dumps({'scene': 'today', 'scenario': 'normal'}),
                           {'Authorization': 'Bearer ' + server.token, 'Content-Type': 'application/json'})
        response = connection.getresponse()
        self.assertEqual(response.status, 403)
        response.read()
        connection.close()


if __name__ == '__main__':
    unittest.main()
