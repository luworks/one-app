#!/usr/bin/env python3
"""Run bounded independent screen lanes from one completed simulator build.

First build-for-testing once from this checkout. This entrypoint copies Products
(including the relative-path xctestrun) to each lane's own cache, then delegates
lifecycle, command/test journaling and complete result retention to run-e2e.py.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import signal
import threading
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("e2e", ROOT / "ios/Eval/run-e2e.py")
e2e = importlib.util.module_from_spec(spec)
spec.loader.exec_module(e2e)


def copy_products(source, destination):
    """Require relocatable Xcode products; never rewrite signed app/test bundles."""
    runs = list(source.glob("*.xctestrun"))
    if len(runs) != 1:
        raise ValueError("Products must contain exactly one completed .xctestrun")
    data = plistlib.loads(runs[0].read_bytes())
    def check(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if key in ("TestHostPath", "TestBundlePath", "UITargetAppPath") and not item.startswith(("__TESTROOT__/", "__TESTHOST__/")):
                    raise ValueError(f"Non-relocatable {key}: {item}")
                check(item)
        elif isinstance(value, list):
            for item in value:
                check(item)
    check(data)
    shutil.copytree(source, destination)  # Refuse existing/live lane products.
    return destination / runs[0].name


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--products", type=Path, required=True, help="completed Build/Products; no active build")
    p.add_argument("--source-head", required=True, help="exact git SHA of that build; must match this checkout")
    p.add_argument("--lane", action="append", choices=["small", "standard", "mini"], required=True)
    p.add_argument("--workers", type=int, choices=[1, 2, 3], default=2)
    p.add_argument("--output", type=Path, required=True, help="new batch directory under persistent results")
    args = p.parse_args()
    args.output = args.output.resolve()
    args.products = args.products.resolve()
    if e2e.capture(["git", "rev-parse", "HEAD"]) != args.source_head:
        p.error("Build source HEAD differs from this checkout")
    # Infrastructure edits are allowed; app/tests/fixture edits require a new build.
    dirty = e2e.capture(["git", "diff", "HEAD", "--name-only", "--", "ios/One", "ios/OneUITests", "ios/Shared", "tests/fixtures"])
    if dirty:
        p.error("Unbuilt app/test/fixture changes: " + dirty)
    config = json.loads(Path(__file__).with_name("compatibility.json").read_text())
    runtime = config["runtime"]
    available = json.loads(e2e.capture(["xcrun", "simctl", "list", "runtimes", "--json"]))["runtimes"]
    supported = {d["identifier"] for r in available if r["identifier"] == runtime and r["isAvailable"]
                 for d in r["supportedDeviceTypes"]}
    lanes = list(dict.fromkeys(args.lane))
    for lane in lanes:
        device = "com.apple.CoreSimulator.SimDeviceType." + config["lanes"][lane]["device_type"]
        if device not in supported:
            p.error(f"Installed runtime does not support {device}")
    args.output.mkdir(parents=True, exist_ok=False)
    journal = e2e.RunJournal(args.output.name, [])
    journal.record("qa.development", "Copy completed build products; bounded independent device lanes", status="running")
    commands = []
    for lane in lanes:
        settings = config["lanes"][lane]
        cache = args.output / (lane + "-cache")
        products = copy_products(args.products.resolve(), cache / "Build/Products")
        command = [sys.executable, str(ROOT / "ios/Eval/run-e2e.py"),
                   "--simulator-name", settings["name"], "--device-type",
                   "com.apple.CoreSimulator.SimDeviceType." + settings["device_type"],
                   "--runtime", runtime, "--derived-data", str(cache), "--test-products", str(products),
                   "--appearance", settings["appearance"], "--content-size", settings["content_size"],
                   "--output", str(args.output / lane)]
        for method in config["methods"]:
            command.extend(["--only", method])
        commands.append(command)
    processes = set()
    mutex = threading.Lock()
    stopping = threading.Event()
    def stop(*_):
        stopping.set()
        with mutex:
            for process in processes:
                if process.poll() is None:
                    process.terminate()  # Child runner terminates Xcode's process group and shuts down.
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    def execute(command):
        lane = Path(command[command.index("--output") + 1]).name
        with (args.output / (lane + "-runner.log")).open("w") as log:
            with mutex:
                if stopping.is_set():
                    return 130
                process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
                processes.add(process)
            try:
                return process.wait()
            finally:
                with mutex:
                    processes.discard(process)
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        codes = list(pool.map(execute, commands))
    summary = {"status": "interrupted" if stopping.is_set() else ("passed" if not any(codes) else "failed"), "source_head": args.source_head,
               "lanes": dict(zip(lanes, codes)), "commands": commands, "workers": args.workers}
    (args.output / "batch.json").write_text(json.dumps(summary, indent=2) + "\n")
    # Each lane indexes its own completed bundle. Index batch metadata without
    # hashing large duplicate build caches (they are disposable, not evidence).
    journal.record("qa.run.result", json.dumps(summary), status=summary["status"])
    if journal.store:
        for path in [args.output / "batch.json", *args.output.glob("*-runner.log")]:
            journal.store.artifact(args.output.name, path)
        journal.store.close()
    print(json.dumps(summary, indent=2))
    return int(any(codes))


if __name__ == "__main__":
    sys.exit(main())
