"""Read-only aggregation of retained receipts; never executes or repairs a run."""
import hashlib
import json
from pathlib import Path

from .core import canonical_root, state_root
from .process import Redactor


def collect(root, paths=()):
    """Return observed records and blockers, without opening a writable journal.

    Explicit paths must be retained JSON files under canonical tests/results.
    Defaults include dev receipts and authority reports, not mutable gallery state.
    Recorded statuses are source claims, never freshly inferred acceptance.
    """
    root = Path(root).resolve()
    retained = (canonical_root(root) / 'tests/results').resolve()
    if paths:
        candidates = [Path(p) if Path(p).is_absolute() else root / p for p in paths]
    else:
        base = state_root(root)
        candidates = sorted((base / 'runs').glob('*.json'))
    records, blockers = [], []
    for path in candidates:
        path = Path(path)
        if path.is_symlink() or retained not in path.resolve().parents or not path.is_file():
            blockers.append({'path': str(path), 'reason': 'Not a retained regular evidence file'})
            continue
        try:
            raw = path.read_bytes()
            data = json.loads(raw)
            if not isinstance(data, dict):
                raise ValueError('Expected JSON object')
        except (OSError, ValueError) as error:
            blockers.append({'path': str(path), 'reason': str(error)})
            continue
        if not paths and data.get('worktree') != str(root):
            continue
        own = data.get('kind') in ('check', 'benchmark') and data.get('schema') == 1
        record = {'path': str(path), 'sha256': hashlib.sha256(raw).hexdigest(),
                  'recorded_status': data.get('status'), 'recorded_exit': data.get('exit'),
                  'worktree': data.get('worktree'), 'kind': data.get('kind', 'authority-report'),
                  'data': data}
        records.append(record)
        if own:
            attempts = data.get('attempts' if data['kind'] == 'check' else 'samples')
            if not isinstance(attempts, list) or not attempts:
                blockers.append({'path': str(path), 'reason': 'No measured invocations retained'})
                continue
            if data.get('exit') != 0 or data.get('source_changed') or data.get('not_run'):
                blockers.append({'path': str(path), 'reason': 'Recorded run failed, changed source, or is incomplete'})
            for attempt in attempts:
                if not isinstance(attempt, dict):
                    blockers.append({'path': str(path), 'reason': 'Malformed invocation'})
                    continue
                if attempt.get('exit') != 0 or attempt.get('reason') != 'exited':
                    blockers.append({'path': str(path), 'reason': 'Invocation did not complete successfully'})
                log_value = attempt.get('log')
                log = Path(log_value) if isinstance(log_value, str) else Path()
                try:
                    valid = (not log.is_symlink() and retained in log.resolve().parents
                             and log.is_file() and attempt.get('log_sha256') ==
                             hashlib.sha256(log.read_bytes()).hexdigest())
                except OSError:
                    valid = False
                if not valid:
                    blockers.append({'path': str(path), 'reason': 'Missing or modified raw log', 'log': str(log)})
        else:
            # Authority formats differ. Preserve their complete observations,
            # including missing/skipped/parser details, without translating them.
            status = data.get('status')
            if status not in ('passed', 'completed'):
                blockers.append({'path': str(path), 'reason': 'Authority status is failed, absent or incomplete'})
    if not records:
        blockers.append({'reason': 'No retained run evidence found'})
    result = {'schema': 1, 'read_only': True, 'records': records, 'blockers': blockers,
              'status': 'blocked' if blockers else 'observed', 'exit': 1 if blockers else 0,
              'limitations': ['Recorded results are historical evidence, not current revision acceptance.',
                              'No build, logic, simulator, screenshot or physical-device pass is inferred.',
                              'No journal, evidence, cache or report file was created or modified.']}
    # Report may expose records produced by external authorities; redact at output.
    return json.loads(Redactor()(json.dumps(result)))
