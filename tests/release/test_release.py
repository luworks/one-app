"""Behavior checks use synthetic files and strict command mocks; no real archive runs."""
import contextlib
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from fixtures import Fixture, plist

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/release/release.py'
spec = importlib.util.spec_from_file_location('release', SCRIPT)
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.f = Fixture(Path(self.temp.name), r)
        self.mock = patch.object(r, 'run', side_effect=self.f.run)
        self.mock.start()
        self.addCleanup(self.mock.stop)

    def blocked(self, code, fn):
        with self.assertRaisesRegex(r.Blocked, '^' + code + '$'):
            fn()

    def validate(self):
        r.validate_archive(self.f.root, self.f.args)

    def test_synthetic_success_only_with_mocked_signatures_and_uuids(self):
        self.validate()
        self.assertEqual(r.preflight(self.f.root, self.f.args, self.f.env).data['status'], 'ready')
        self.assertTrue(all('-allowProvisioningUpdates' not in a and 'archive' not in a for a in self.f.calls))

    def test_distribution_default_refuses_and_token_is_release_bound(self):
        for env in ({}, {'TODAY_RELEASE_ENVIRONMENT': 'production'},
                    {'TODAY_RELEASE_ENVIRONMENT': 'testflight', 'TODAY_DISTRIBUTION_AUTHORIZATION': 'wrong'}):
            self.blocked('distribution_authorization_required', lambda: r.authorize(self.f.args, env, 'distribution'))
        env = {'TODAY_RELEASE_ENVIRONMENT': 'testflight', 'TODAY_DISTRIBUTION_AUTHORIZATION':
               'upload-testflight:' + self.f.args.commit + ':1.2.3:42'}
        r.authorize(self.f.args, env, 'distribution')
        self.f.args.build = '43'
        self.blocked('distribution_authorization_required', lambda: r.authorize(self.f.args, env, 'distribution'))
        self.assertEqual(self.f.calls, [])

    def test_archive_requires_its_own_authorization(self):
        self.blocked('archive_authorization_required', lambda: r.authorize(self.f.args, {}, 'archive'))
        r.authorize(self.f.args, {'TODAY_ARCHIVE_AUTHORIZATION': 'archive:' + self.f.args.commit}, 'archive')

    def test_dirty_or_wrong_commit_blocks(self):
        original = self.f.run
        def changed(argv, root):
            return b' M private-secret-path\n' if argv[1:2] == ['status'] else original(argv, root)
        r.run.side_effect = changed
        self.blocked('worktree_dirty', lambda: r.check_git(self.f.root, self.f.args.commit))
        self.blocked('commit_mismatch', lambda: r.check_git(self.f.root, 'b' * 40))

    def test_missing_generated_project_and_signing_are_blocked_not_success(self):
        (self.f.root / 'ios/Today.xcodeproj/project.pbxproj').unlink()
        with patch.object(r, 'check_signing', side_effect=r.Blocked('distribution_identity_missing')):
            result = r.preflight(self.f.root, self.f.args, {}).data
        self.assertEqual(result['status'], 'blocked')
        self.assertEqual(result['checks']['generated_project']['code'], 'generated_project_missing')
        self.assertEqual(result['checks']['signing_environment']['status'], 'blocked')
        self.assertEqual(result['offline_scanner'], 'unavailable')

    def test_tool_drift_and_missing_installed_gems_block(self):
        original = self.f.run
        for command, code in [(('ruby', '-e', 'print RUBY_VERSION'), 'ruby_lock_mismatch'),
                              (('bundle', 'check'), 'command_failed'),
                              (('xcodebuild', '-version'), 'xcode_lock_mismatch')]:
            def changed(argv, root, command=command):
                if tuple(argv) == command:
                    if command == ('bundle', 'check'):
                        raise r.Blocked('command_failed')
                    return b'wrong'
                return original(argv, root)
            r.run.side_effect = changed
            self.blocked(code, lambda: r.check_tools(self.f.root))

    def test_profiles_expired_development_wrong_team_group_or_certificate_block(self):
        key = self.f.env['TODAY_APP_PROFILE']
        original = copy.deepcopy(self.f.profiles[key])
        mutations = [({'ExpirationDate': __import__('datetime').datetime(2000, 1, 1)}, 'provisioning_profile_expired'),
                     ({'ProvisionedDevices': ['synthetic']}, 'app_store_profile_required'),
                     ({'TeamIdentifier': ['WRONGTEAM0']}, 'profile_identity_mismatch'),
                     ({'DeveloperCertificates': [b'other']}, 'matching_private_signing_identity_missing')]
        for mutation, code in mutations:
            self.f.profiles[key] = dict(original, **mutation)
            self.blocked(code, lambda: r.check_signing(self.f.root, self.f.args.team, self.f.env))
        self.f.profiles[key] = copy.deepcopy(original)
        self.f.profiles[key]['Entitlements']['com.apple.security.application-groups'] = ['wrong']
        self.blocked('profile_app_group_mismatch', lambda: r.check_signing(self.f.root, self.f.args.team, self.f.env))

    def test_automatic_signing_settings_are_not_ready(self):
        original = self.f.run
        def changed(argv, root):
            data = original(argv, root)
            if '-showBuildSettings' in argv:
                rows = json.loads(data)
                rows[0]['buildSettings']['CODE_SIGN_STYLE'] = 'Automatic'
                return json.dumps(rows).encode()
            return data
        r.run.side_effect = changed
        self.blocked('release_signing_settings_mismatch', lambda: r.check_signing(self.f.root, self.f.args.team, self.f.env))

    def test_content_or_receipt_tampering_blocks(self):
        binary = self.f.args.archive / 'Products/Applications/One.app/One'
        binary.write_bytes(b'tampered')
        self.blocked('archive_content_changed', self.validate)
        self.f.reseal()
        self.f.args.commit = 'b' * 40
        self.blocked('archive_provenance_mismatch', self.validate)

    def test_wrong_bundle_version_embeds_and_entitlements_block(self):
        app = self.f.args.archive / 'Products/Applications/One.app'
        for key, value in [('CFBundleIdentifier', 'com.other.app'), ('CFBundleVersion', '43'),
                           ('CFBundleExecutable', 'Today'), ('CFBundleSupportedPlatforms', ['iPhoneSimulator'])]:
            info = plistlib.loads((app / 'Info.plist').read_bytes())
            original = dict(info)
            info[key] = value
            plist(app / 'Info.plist', info)
            self.f.reseal()
            with self.assertRaises(r.Blocked):
                self.validate()
            plist(app / 'Info.plist', original)
        extra = app / 'PlugIns/Unexpected.appex'
        extra.mkdir()
        self.f.reseal()
        self.blocked('extension_embeds_mismatch', self.validate)
        extra.rmdir()
        self.f.reseal()
        self.f.entitlements[str(app)]['get-task-allow'] = True
        self.blocked('signed_entitlements_mismatch', self.validate)

    def test_missing_mismatched_and_orphan_dsym_block(self):
        binary = str(self.f.args.archive / 'Products/Applications/One.app/One')
        self.f.uuid[binary] = '99999999-1111-2222-3333-444444444444'
        self.blocked('executable_dsym_uuid_mismatch', self.validate)
        self.f.uuid[binary] = None
        self.blocked('macho_uuid_missing_or_duplicate', self.validate)

    def test_signature_certificate_must_match_embedded_profile(self):
        original = self.f.run
        def changed(argv, root):
            result = original(argv, root)
            if argv[:3] == ['codesign', '-d', '--extract-certificates']:
                Path(argv[3] + '0').write_bytes(b'OTHER-SYNTHETIC-CERTIFICATE')
            return result
        r.run.side_effect = changed
        self.blocked('archive_certificate_not_in_profile', self.validate)

    def test_unsigned_fake_archive_cannot_pass_real_validation(self):
        original = self.f.run
        def unsigned(argv, root):
            if argv[0] == 'codesign':
                raise r.Blocked('command_failed')
            return original(argv, root)
        r.run.side_effect = unsigned
        self.blocked('command_failed', self.validate)

    def test_profile_wildcard_only_allows_the_products_own_keychain_group(self):
        app = self.f.args.archive / 'Products/Applications/One.app'
        key = 'keychain-access-groups'
        self.f.entitlements[str(app)][key] = [self.f.args.team + '.com.luworks.one']
        self.f.profiles[str(app / 'embedded.mobileprovision')]['Entitlements'][key] = [self.f.args.team + '.*']
        self.validate()
        self.f.entitlements[str(app)][key] = [self.f.args.team + '.com.other.app']
        self.blocked('signed_keychain_group_not_in_profile', self.validate)

    def test_missing_archive_and_symlink_refused(self):
        self.blocked('archive_required', lambda: r.inventory(None))
        (self.f.args.archive / 'link').symlink_to(self.f.root / 'Gemfile')
        self.blocked('archive_symlink_refused', self.validate)

    def test_valid_export_and_changed_resources_or_unexpected_files(self):
        app = self.f.args.archive / 'Products/Applications/One.app'
        (app / 'resource.txt').write_text('synthetic resource')
        self.f.reseal()
        def pack(extra=False, changed=False):
            with zipfile.ZipFile(self.f.args.ipa, 'w') as z:
                for path in app.rglob('*'):
                    if path.is_file():
                        data = b'changed resource' if changed and path.name == 'resource.txt' else path.read_bytes()
                        z.writestr('Payload/One.app/' + str(path.relative_to(app)), data)
                if extra:
                    z.writestr('Payload/One.app/extra.txt', 'unexpected')
        pack()
        r.validate_export(self.f.root, self.f.args)
        pack(extra=True)
        self.blocked('export_file_set_changed', lambda: r.validate_export(self.f.root, self.f.args))
        pack(changed=True)
        self.blocked('macho_uuid_missing_or_duplicate', lambda: r.validate_export(self.f.root, self.f.args))

    def test_orphan_dsym_is_rejected(self):
        dwarf = self.f.args.archive / 'dSYMs/Orphan.dSYM/Contents/Resources/DWARF/Orphan'
        dwarf.parent.mkdir(parents=True)
        dwarf.write_bytes(b'SYNTHETIC-NOT-DWARF')
        self.f.uuid[str(dwarf)] = '99999999-1111-2222-3333-444444444444'
        self.f.reseal()
        self.blocked('orphan_dsym_uuid', self.validate)

    def test_ipa_traversal_rejected_before_extract(self):
        with zipfile.ZipFile(self.f.args.ipa, 'w') as z:
            z.writestr('../escape', 'private-content')
        self.blocked('unsafe_ipa_entry', lambda: r.validate_export(self.f.root, self.f.args))
        self.assertFalse((self.f.root / 'escape').exists())

    def test_json_never_relays_command_output_exception_or_environment(self):
        with patch.object(r, 'ROOT', self.f.root), patch.object(r, 'check_tools', side_effect=ValueError('secret')), \
             patch.dict(os.environ, {'SECRET': 'private-content'}), contextlib.redirect_stdout(io.StringIO()) as output:
            code = r.main(['preflight', '--commit', self.f.args.commit, '--version', '1.2.3', '--build', '42', '--team', self.f.args.team])
        self.assertEqual(code, 2)
        data = output.getvalue()
        self.assertNotIn('secret', data)
        self.assertNotIn('private-content', data)
        self.assertEqual(json.loads(data)['checks']['locked_tools']['code'], 'invalid_or_missing_input')


class FastfileGuardTests(unittest.TestCase):
    def test_every_mutating_lane_defaults_to_refusal_before_build_or_upload(self):
        # Fake DSL only: actual Fastlane, Xcode and Apple services never run.
        fastfile = r.ROOT / 'fastlane/Fastfile'
        for lane in ('archive', 'beta', 'distribute'):
            driver = '''
module UI
  def self.message(_); end
  def self.user_error!(_); raise 'blocked'; end
end
$lanes = {}
def default_platform(*); end
def platform(*); yield; end
def desc(*); end
def lane(name, &block); $lanes[name] = block; end
def build_app(*); abort 'BUILD_OR_EXPORT_CALLED'; end
def upload_to_testflight(*); abort 'UPLOAD_CALLED'; end
load ARGV[0]
begin
  $lanes[ARGV[1].to_sym].call(commit: 'a' * 40, version: '1.2.3', build: '42', team: 'ABCDEFGHIJ')
rescue => e
  exit(e.message == 'blocked' ? 0 : 3)
end
exit 4
'''
            env = {k: v for k, v in os.environ.items() if not k.startswith('TODAY_')}
            p = subprocess.run(['ruby', '-e', driver, str(fastfile), lane], env=env, capture_output=True)
            self.assertEqual(p.returncode, 0, p.stderr.decode())


if __name__ == '__main__':
    unittest.main()
