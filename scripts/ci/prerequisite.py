#!/usr/bin/env python3
"""Verify exact hosted toolchain; never install Xcode or silently use another version."""
import json
import os
from pathlib import Path
import platform
import subprocess
import sys


def verify(architecture, version, sdks, runtimes):
    errors = []
    if architecture != 'arm64':
        errors.append('requires hosted macOS arm64')
    if version.strip() != 'Xcode 27.1\nBuild version 27A9275':
        errors.append('requires Xcode 27.1 build 27A9275 at /Applications/Xcode_27.1.app')
    if 'iphonesimulator27.1' not in sdks or 'iphoneos27.1' not in sdks:
        errors.append('requires iOS 27.1 device and simulator SDKs')
    if not any(r.get('isAvailable') is True and r.get('version') == '27.0' and
               r.get('identifier', '').startswith('com.apple.CoreSimulator.SimRuntime.iOS-')
               for r in runtimes.get('runtimes', [])):
        errors.append('requires available iOS 27.0 simulator runtime')
    return errors


def main():
    try:
        version = subprocess.check_output(['xcodebuild', '-version'], text=True, stderr=subprocess.STDOUT)
        sdks = subprocess.check_output(['xcodebuild', '-showsdks'], text=True, stderr=subprocess.STDOUT)
        runtimes = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'runtimes', '-j'], text=True, stderr=subprocess.STDOUT))
        errors = verify(platform.machine(), version, sdks, runtimes)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        errors = ['exact hosted toolchain probe failed: ' + str(error)]
    if errors:
        print('::error::Hosted prerequisite unavailable: ' + '; '.join(errors) +
              '. Use a supported GitHub-hosted image containing these exact prerequisites; update the reviewed toolchain contract if requirements change. Do not substitute a personal runner or report skipped tests as passing.')
        return 1
    print('Exact Xcode/SDK/runtime prerequisite verified; no build or simulator boot performed.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
