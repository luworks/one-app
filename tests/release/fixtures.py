"""Synthetic release fixtures. Never real signed archives or signing material."""
import argparse
import copy
import datetime as dt
import json
from pathlib import Path
import plistlib
import shutil


def plist(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(plistlib.dumps(data))


class Fixture:
    def __init__(self, root, release):
        self.root = root
        self.release = release
        self.args = argparse.Namespace(commit='a' * 40, version='1.2.3', build='42',
                                       team='ABCDEFGHIJ', archive=root / 'Synthetic.xcarchive')
        self.args.ipa = root / 'Synthetic.ipa'
        self.entitlements = {}
        self.profiles = {}
        self.uuid = {}
        self.env = {}
        self.calls = []
        for file in ('Gemfile', 'Gemfile.lock', 'scripts/release/tool-lock.json'):
            target = root / file
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(release.ROOT / file, target)
        project = root / 'ios/Today.xcodeproj'
        (project / 'xcshareddata/xcschemes').mkdir(parents=True)
        (project / 'project.pbxproj').write_text('// Synthetic project; never build')
        (project / 'xcshareddata/xcschemes/Today.xcscheme').write_text('<Scheme/>')
        archive = self.args.archive
        app = archive / 'Products/Applications/One.app'
        for index, (name, bundle_id) in enumerate(release.PRODUCTS.items(), 1):
            source = {'com.apple.security.application-groups': [release.GROUP]}
            if name == 'One':
                source['com.apple.developer.healthkit'] = True
            plist(root / f'ios/{name}.entitlements', source)
            ent = dict(source, **{'application-identifier': self.args.team + '.' + bundle_id,
                                 'com.apple.developer.team-identifier': self.args.team,
                                 'get-task-allow': False})
            bundle = app if name == 'One' else app / f'PlugIns/{name}.appex'
            info = {'CFBundleIdentifier': bundle_id, 'CFBundleExecutable': name,
                    'CFBundleShortVersionString': '1.2.3', 'CFBundleVersion': '42',
                    'CFBundlePackageType': 'APPL' if name == 'One' else 'XPC!',
                    'CFBundleSupportedPlatforms': ['iPhoneOS']}
            if name != 'One':
                info['NSExtension'] = {'NSExtensionPointIdentifier': 'com.apple.widgetkit-extension'
                                      if name == 'TodayWidgets' else 'com.apple.share-services'}
            plist(bundle / 'Info.plist', info)
            (bundle / name).write_bytes(b'SYNTHETIC-NOT-MACHO')
            (bundle / 'embedded.mobileprovision').write_bytes(b'SYNTHETIC-NOT-PROVISION')
            self.entitlements[str(bundle)] = ent
            data = {'ExpirationDate': dt.datetime(2099, 1, 1), 'TeamIdentifier': [self.args.team],
                    'Entitlements': copy.deepcopy(ent), 'DeveloperCertificates': [b'SYNTHETIC-NOT-CERTIFICATE'],
                    'Name': name, 'UUID': f'profile-{name}'}
            self.profiles[str(bundle / 'embedded.mobileprovision')] = data
            selected = root / f'selected-{name}.mobileprovision'
            selected.write_bytes(b'SYNTHETIC-NOT-PROVISION')
            self.profiles[str(selected)] = data
            self.env[release.PROFILES[name]] = str(selected)
            dwarf = archive / f'dSYMs/{name}.app.dSYM/Contents/Resources/DWARF/{name}'
            dwarf.parent.mkdir(parents=True)
            dwarf.write_bytes(b'SYNTHETIC-NOT-DWARF')
            uid = f'{index:08X}-1111-2222-3333-444444444444'
            self.uuid[str(bundle / name)] = uid
            self.uuid[str(dwarf)] = uid
        plist(archive / 'Info.plist', {'ApplicationProperties': {
            'ApplicationPath': 'Applications/One.app', 'CFBundleIdentifier': 'com.luworks.one',
            'CFBundleShortVersionString': '1.2.3', 'CFBundleVersion': '42'}})
        self.reseal()

    def reseal(self):
        r = self.release
        receipt = {'schema': 1, 'commit': self.args.commit, 'version': self.args.version,
                   'build': self.args.build, 'tool_locks': r.lock_hashes(self.root),
                   'files': r.inventory(self.args.archive)}
        (self.args.archive / 'release-provenance.json').write_text(json.dumps(receipt))

    def run(self, argv, root=None):
        """Strict mock: an unexpected external command fails the test."""
        self.calls.append(argv)
        argv = list(argv)
        if 'Payload' in Path(argv[-1]).parts:
            parts = Path(argv[-1]).parts
            argv[-1] = str(self.args.archive / 'Products/Applications' / Path(*parts[parts.index('Payload') + 1:]))
        if argv[:2] == ['security', 'cms']:
            return plistlib.dumps(self.profiles[argv[-1]])
        if argv[:2] == ['security', 'find-identity']:
            import hashlib
            digest = hashlib.sha1(b'SYNTHETIC-NOT-CERTIFICATE').hexdigest().upper()
            return f'1) {digest} "Apple Distribution: Synthetic"'.encode()
        if argv[:2] == ['codesign', '--verify']:
            return b''
        if argv[:3] == ['codesign', '-d', '--extract-certificates']:
            Path(argv[3] + '0').write_bytes(b'SYNTHETIC-NOT-CERTIFICATE')
            return b''
        if argv[:2] == ['codesign', '-d']:
            return plistlib.dumps(self.entitlements[argv[-1]])
        if argv[:3] == ['xcrun', 'dwarfdump', '--uuid']:
            uid = self.uuid.get(argv[-1])
            return f'UUID: {uid} (arm64) ignored-path'.encode() if uid else b''
        if argv[0] == 'git':
            return (self.args.commit + '\n').encode() if argv[1:3] == ['rev-parse', 'HEAD'] else b''
        lock = json.loads((self.root / 'scripts/release/tool-lock.json').read_text())
        tools = {('ruby', '-e', 'print RUBY_VERSION'): lock['ruby'].encode(),
                 ('bundle', '--version'): lock['bundler'].encode(), ('bundle', 'check'): b'',
                 ('bundle', 'exec', 'ruby', '-e', 'require "fastlane/version"; print Fastlane::VERSION'): lock['fastlane'].encode(),
                 ('xcodebuild', '-version'): lock['xcode'].encode(),
                 ('xcrun', '--sdk', 'iphoneos', '--show-sdk-path'): b'/Synthetic/SDK'}
        if tuple(argv) in tools:
            return tools[tuple(argv)]
        if argv[0] == 'xcodebuild' and '-showBuildSettings' in argv:
            rows = []
            for name, bundle_id in self.release.PRODUCTS.items():
                rows.append({'buildSettings': {'PRODUCT_NAME': name, 'PRODUCT_BUNDLE_IDENTIFIER': bundle_id,
                             'PRODUCT_MODULE_NAME': name,
                             'DEVELOPMENT_TEAM': self.args.team, 'CODE_SIGN_STYLE': 'Manual',
                             'CODE_SIGNING_ALLOWED': 'YES', 'PROVISIONING_PROFILE_SPECIFIER': name,
                             'CODE_SIGN_IDENTITY': 'Apple Distribution', 'MARKETING_VERSION': '1.2.3',
                             'CURRENT_PROJECT_VERSION': '42'}})
            return json.dumps(rows).encode()
        raise AssertionError(f'Unexpected command: {argv}')
