#!/usr/bin/env python3
"""Run a frozen serial schedule; each child releases its own resource locks."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tests.qa.journal import Journal, results_root
from collect import collect


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('schedule', type=Path)
    parser.add_argument('--device-config', type=Path, required=True)
    args = parser.parse_args()
    schedule = json.loads(args.schedule.read_text())
    base = Path(schedule['output_directory']).resolve()
    if not base.is_relative_to(results_root().resolve()):
        raise SystemExit('Schedule output must stay in primary results')
    journal = Journal()
    session = 'intelligence-selection-20261029'
    journal.artifact(session, args.schedule)
    journal.record(session, 'qa.schedule', 'Started frozen schedule ' + str(args.schedule), status='started')
    try:
        for job in schedule['jobs']:
            if (base / schedule['stop_file']).exists():
                journal.record(session, 'qa.schedule', 'Stopped at released batch boundary', status='interrupted')
                print('Stopped at batch boundary; no heavy lock retained', flush=True)
                return
            for name, expected in schedule['source_hashes'].items():
                if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != expected:
                    raise ValueError('Frozen schedule source changed: ' + name)
            stem = base / job['stem']
            if stem.parent != base or job['split'] not in ('development', 'holdout'):
                raise ValueError('Invalid job destination or split')
            log = stem.with_suffix('.log')
            report = stem.with_suffix('.evidence.json')
            if report.exists():
                evidence = collect(log.read_text())
                if not evidence['valid'] or len(evidence['runs']) != 1:
                    raise ValueError('Cannot resume past invalid evidence')
                run = evidence['runs'][0]
                if run['model'] != job['model'] or run['split'] != job['split'] or len(run['rows']) != job['expected']:
                    raise ValueError('Existing job identity mismatch')
                print('Verified completed job: ' + job['stem'], flush=True)
            else:
                print('Starting bounded job: ' + job['stem'], flush=True)
                subprocess.run([
                    sys.executable, str(Path(__file__).with_name('run_owned.py')),
                    '--device-config', str(args.device_config), '--model', job['model'],
                    '--button', job['button'], '--expected', str(job['expected']),
                    '--output-stem', str(stem), '--max-seconds', str(job['max_seconds']),
                ], check=True, cwd=ROOT)
            # Closed evidence only; never grade or archive a live stream.
            fields = base / (job['stem'] + '-fields.json')
            breakdown = base / (job['stem'] + '-breakdown.json')
            for script, source, output in [('score.py', report, fields), ('summarize.py', fields, breakdown)]:
                if not output.exists():
                    subprocess.run([sys.executable, str(Path(__file__).with_name(script)),
                                    str(source), '--output', str(output)], check=True, cwd=ROOT)
                journal.artifact(session, output)
        journal.record(session, 'qa.schedule', 'All frozen scheduled batches completed', status='completed')
        print('Schedule complete; no resource locks retained', flush=True)
    except BaseException:
        journal.record(session, 'qa.schedule', 'Schedule stopped on failure; no automatic retry', status='failed')
        raise
    finally:
        journal.close()


if __name__ == '__main__':
    main()
