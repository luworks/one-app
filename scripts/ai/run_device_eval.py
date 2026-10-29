#!/usr/bin/env python3
"""Capture the frozen synthetic UI eval through an already-open agent-device session.

No pass is inferred here. A reviewer scores screenshots, receipts and isolated-store
snapshots against the unchanged fixture. Never points at a physical device.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sqlite3
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--agent', required=True)
    parser.add_argument('--store', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--case', action='append', default=[], help='Frozen case ID; repeat to select a retest batch')
    args = parser.parse_args()
    fixture = Path('tests/fixtures/ai-chat-capability-eval.json')
    cases = json.loads(fixture.read_text())['cases']
    if args.case:
        unknown = set(args.case) - {case['id'] for case in cases}
        if unknown:
            raise SystemExit('Unknown fixture cases: '+str(sorted(unknown)))
        cases = [case for case in cases if case['id'] in args.case]
    args.out.mkdir(parents=True, exist_ok=True)
    if (args.out / 'observations.jsonl').exists():
        raise SystemExit('Existing observation run; refusing to repeat submitted actions')
    (args.out / 'fixture.sha256').write_text(hashlib.sha256(fixture.read_bytes()).hexdigest()+'\n')
    log = (args.out / 'commands.jsonl').open('a')

    def command(*parts):
        start = time.time()
        result = subprocess.run([args.agent, *parts], text=True, capture_output=True, timeout=60)
        log.write(json.dumps({'at': start, 'args': parts, 'returncode': result.returncode,
                              'seconds': time.time()-start, 'stdout': result.stdout,
                              'stderr': result.stderr}, ensure_ascii=False)+'\n')
        log.flush()
        if result.returncode:
            raise RuntimeError(result.stdout+'\n'+result.stderr)
        return result.stdout

    def store_snapshot():
        with sqlite3.connect('file:'+str(args.store)+'?mode=ro', uri=True) as db:
            db.row_factory = sqlite3.Row
            return {table: [dict(r) for r in db.execute('SELECT * FROM '+table)]
                    for table in ['ZONETASK', 'ZONEEVENT', 'ZONEALARM']}

    for case in cases:
        # Established screenshots show Close at 360,92 and the home Chat field at 132,813.
        command('press', '360', '92')
        command('press', '132', '813')
        for number, turn in enumerate(case['turns'], 1):
            ident = case['id']+'-'+str(number)
            before = store_snapshot()
            command('fill', 'label="Ask AI or add anything" editable=true', turn['input'])
            submitted = time.time()
            command('keyboard', 'enter')
            # Bounded observation wait, not a model retry. Covers current route deadlines.
            time.sleep(13)
            shot = args.out/(ident+'.png')
            command('screenshot', str(shot))
            snapshot = command('snapshot', '-i', '--json')
            (args.out/(ident+'.json')).write_text(snapshot)
            observation = {'id': case['id'], 'turn': number, 'input': turn['input'],
                           'expected': turn['expect'], 'submitted_at': submitted,
                           'observed_at': time.time(), 'screenshot': str(shot),
                           'before': before, 'after': store_snapshot()}
            with (args.out/'observations.jsonl').open('a') as stream:
                stream.write(json.dumps(observation, ensure_ascii=False, default=str)+'\n')
            print('Observed', ident, flush=True)
    log.close()


if __name__ == '__main__':
    main()
