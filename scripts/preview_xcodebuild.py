#!/usr/bin/env python3
"""Record axe's exact xcodebuild stages without changing their arguments/results."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

folder = Path(os.environ['TODAY_PREVIEW_BUILD_LOGS'])
folder.mkdir(parents=True, exist_ok=True)
name = str(time.time_ns())
start = time.monotonic()
row = {'arguments': sys.argv[1:], 'start': time.time(), 'pid': os.getpid()}
log = folder / (name + '.log')
try:
    with log.open('wb') as output:
        result = subprocess.run(['/usr/bin/xcodebuild', *sys.argv[1:]], stdout=output, stderr=subprocess.STDOUT)
    row['exit'] = result.returncode
    sys.stdout.buffer.write(log.read_bytes())
finally:
    row['seconds'] = time.monotonic() - start
    row['log'] = str(log)
    (folder / (name + '.json')).write_text(json.dumps(row, indent=2))
sys.exit(result.returncode)
