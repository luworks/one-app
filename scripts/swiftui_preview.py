#!/usr/bin/env python3
"""Thin, single-simulator orchestration of pinned axe. No app rendering in Python."""
import argparse
import fcntl
import functools
import hashlib
import http.server
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import threading
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tests/qa'))
from journal import Journal, canonical_root

VERSION = 'v0.0.14'
AXE_SHA = 'b12c0b3224b87ba9d51df89c86e2454d81afc371f99a5a434af519d17a03c753'
IDB_SHA = 'f81e5ff131c8c91fb6927cb445a7267a4e80c543e51e4b26ebcaa00eff4e3c1f'
SCREENS = {'reminders': 'RemindersView.swift', 'world': 'WorldClockView.swift', 'health': 'HealthMetricDetail.swift'}
LANE = hashlib.sha256(str(ROOT / 'ios/One.xcodeproj').encode()).hexdigest()[:16]
TOOLS = ROOT / '.preview-tools'
DD = Path.home() / 'Library/Caches/axe' / ('preview-' + LANE) / 'build'
PROCESSES = []
STOP = threading.Event()


def download(url, path, sha):
    if path.exists() and hashlib.sha256(path.read_bytes()).hexdigest() == sha:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix('.download')
    urllib.request.urlretrieve(url, tmp)
    if hashlib.sha256(tmp.read_bytes()).hexdigest() != sha:
        raise RuntimeError('Checksum mismatch: ' + url)
    tmp.replace(path)


def install():
    if os.uname().machine != 'arm64':
        raise RuntimeError('This POC pins Apple Silicon binaries only.')
    download(f'https://github.com/k-kohey/axe/releases/download/{VERSION}/axe-darwin-arm64', TOOLS / 'axe', AXE_SHA)
    (TOOLS / 'axe').chmod(0o755)
    archive = TOOLS / 'idb-companion-1.7.6.tar.gz'
    download('https://github.com/facebook/idb/releases/download/v1.7.6/idb-companion.macos-arm64.tar.gz', archive, IDB_SHA)
    companion = TOOLS / 'idb/idb_companion'
    if not companion.exists():
        # Official checksummed archive; preserve sibling Resources and libraries.
        (TOOLS / 'idb').mkdir(exist_ok=True)
        subprocess.run(['tar', '-xzf', str(archive), '-C', str(TOOLS / 'idb')], check=True)
    bin_dir = TOOLS / 'bin'
    bin_dir.mkdir(exist_ok=True)
    wrapper = bin_dir / 'xcodebuild'
    if not wrapper.exists():
        wrapper.symlink_to(ROOT / 'scripts/preview_xcodebuild.py')
    os.environ['PATH'] = str(bin_dir) + os.pathsep + str(TOOLS / 'idb') + os.pathsep + os.environ['PATH']


def main():
    def interrupted(signum, frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupted)
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--watch', choices=SCREENS, default='reminders')
    p.add_argument('--port', type=int, default=0, help='Loopback port; 0 chooses a free port')
    p.add_argument('--budget', type=int, default=600, help='Hard lifetime including installation/build; seconds')
    p.add_argument('--once', action='store_true', help='Capture gallery and shut down without watch/server')
    p.add_argument('--plan', action='store_true', help='Print ownership and commands; no installation or simulator operation')
    args = p.parse_args()
    sim_name = 'Today-Preview-POC-' + LANE[:8]
    common = ['--project', str(ROOT / 'ios/One.xcodeproj'), '--scheme', 'One', '--configuration', 'Debug', '--device', '<owned UDID>']
    report = [str(TOOLS / 'axe'), 'preview', 'report', *[str(ROOT / 'ios/One' / f) for f in SCREENS.values()], '--format', 'html', '--concurrency', '1', '--wait', '2s', '-o', '<run>/gallery', *common]
    watch = [str(TOOLS / 'axe'), 'preview', 'watch', str(ROOT / 'ios/One' / SCREENS[args.watch]), '--reuse-build', '--headless', *common]
    if args.plan:
        print(json.dumps({'source': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(), 'simulator': sim_name, 'derivedData': str(DD), 'report': report, 'watch': watch, 'budget': args.budget}, indent=2))
        return
    if args.budget < 1:
        p.error('--budget must be positive')
    base = canonical_root(ROOT) / 'tests/results/swiftui-preview' / LANE
    base.mkdir(parents=True, exist_ok=True)
    lock = (base / 'lane.lock').open('w')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    session = 'preview-' + LANE[:8] + '-' + time.strftime('%Y%m%d-%H%M%S')
    out = base / session
    out.mkdir()
    gallery = out / 'gallery'
    journal = Journal()
    start = time.monotonic()
    udid = None
    server = None
    timer = threading.Timer(args.budget, lambda: os.kill(os.getpid(), signal.SIGINT))
    timer.daemon = True
    timer.start()

    def event(kind, **data):
        row = dict(seconds=round(time.monotonic() - start, 3), time=time.time(), event=kind, **data)
        with (out / 'timings.jsonl').open('a') as f:
            f.write(json.dumps(row) + '\n')
        print(json.dumps(row), flush=True)

    def run(command, name):
        event(name + '.start', command=command)
        journal.record(session, 'qa.command.start', json.dumps(command))
        with (out / (name + '.log')).open('w') as log:
            process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            PROCESSES.append(process)
            code = process.wait()
        event(name + '.end', code=code)
        journal.record(session, 'qa.command.end', name, status='passed' if code == 0 else 'failed')
        if code:
            raise RuntimeError(f'{name} failed ({code}); see {out / (name + ".log")}')

    try:
        os.environ['TODAY_PREVIEW_BUILD_LOGS'] = str(out / 'xcodebuild')
        event('installation.start')
        install()
        event('installation.end')
        devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))
        matches = [d for ds in devices['devices'].values() for d in ds if d['name'] == sim_name]
        if len(matches) > 1:
            raise RuntimeError('Duplicate named simulator; resolve ownership before continuing')
        udid = matches[0]['udid'] if matches else subprocess.check_output(['xcrun', 'simctl', 'create', sim_name, 'com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro-Max', 'com.apple.CoreSimulator.SimRuntime.iOS-27-0'], text=True).strip()
        (base / 'device.json').write_text(json.dumps({'name': sim_name, 'udid': udid}))
        for command in (report, watch):
            command[command.index('<owned UDID>')] = udid
        report[report.index('<run>/gallery')] = str(gallery)
        sources = {str(f.relative_to(ROOT)): hashlib.sha256(f.read_bytes()).hexdigest() for f in (ROOT / 'ios/One').glob('*.swift')}
        (out / 'ownership.json').write_text(json.dumps({'pid': os.getpid(), 'worktree': str(ROOT), 'simulator': sim_name, 'udid': udid, 'derivedData': str(DD), 'sourceHashes': sources}, indent=2))
        event('simulator.ready', udid=udid)
        run(report, 'report')
        assets = sorted((gallery / 'axe_swiftui_preview_report_assets').glob('*.png'))
        if len(assets) < 3:
            raise RuntimeError('Gallery must contain all three real captures')
        live = gallery / 'live.png'
        html = '''<!doctype html><meta charset="utf-8"><title>Today SwiftUI previews</title>
<style>body{font:16px system-ui;background:#eee;color:#222;margin:24px}main{display:flex;gap:20px;flex-wrap:wrap}figure{margin:0;width:300px}img{width:100%;border-radius:24px}figcaption{padding:12px}a{color:#1465b0}</style>
<h1>Today · SwiftUI previews</h1><p>Real simulator captures · static gallery plus one watched screen · <a href="axe_swiftui_preview_report.html">axe report</a></p><main>'''
        for asset in assets:
            html += f'<figure><figcaption>{asset.name}</figcaption><img src="{asset.relative_to(gallery)}"></figure>'
        html += f'</main><h2>Watching {SCREENS[args.watch]}</h2><p>Body edits use axe injection when supported; structural edits rebuild. Last saved frame remains visible on errors; inspect watch.log.</p><img id="live" style="width:300px" alt="Waiting for watch"><script>setInterval(()=>{{document.querySelector("#live").src="live.png?t="+Date.now()}},1000)</script>'
        (gallery / 'index.html').write_text(html)
        event('gallery.ready', captures=len(assets))
        if args.once:
            return
        handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(gallery))
        server = http.server.ThreadingHTTPServer(('127.0.0.1', args.port), handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        url = f'http://127.0.0.1:{server.server_port}/'
        (out / 'url.txt').write_text(url)
        print('GALLERY ' + url + '\nEVIDENCE ' + str(out), flush=True)
        event('watch.start', command=watch)
        proc = subprocess.Popen(watch, cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, start_new_session=True)
        PROCESSES.append(proc)
        with (out / 'watch.log').open('w') as log:
            for line in proc.stdout:
                log.write(f'{time.monotonic()-start:.3f} {line}')
                log.flush()
                if 'Watching ' in line or 'Preview hot-reloaded.' in line or 'Preview incrementally reloaded.' in line:
                    event('watch.rendered', message=line.strip())
                    time.sleep(0.5)
                    temp = gallery / 'live.pending.png'
                    subprocess.run(['xcrun', 'simctl', 'io', udid, 'screenshot', str(temp)], check=True, capture_output=True)
                    temp.replace(live)
                    event('watch.captured', sha256=hashlib.sha256(live.read_bytes()).hexdigest())
            if proc.wait():
                raise RuntimeError('axe watch exited; see watch.log')
    except KeyboardInterrupt:
        event('stop.requested')
    finally:
        timer.cancel()
        for proc in reversed(PROCESSES):
            if proc.poll() is None:
                os.killpg(proc.pid, signal.SIGINT)
                try:
                    proc.wait(timeout=12)
                except subprocess.TimeoutExpired:
                    os.killpg(proc.pid, signal.SIGKILL)
                    proc.wait()
        if server:
            server.shutdown()
        if udid:
            subprocess.run(['xcrun', 'simctl', 'shutdown', udid], capture_output=True)
        event('cleanup.complete')
        for path in sorted(out.rglob('*')):
            if path.is_file():
                journal.artifact(session, path)
        journal.record(session, 'qa.development', 'Preview session stopped; owned simulator shut down. Evidence retained.')
        journal.close()


if __name__ == '__main__':
    main()
