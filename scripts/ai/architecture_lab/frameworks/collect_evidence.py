"""Collect reproducible Linux SDK/process evidence; never infer iOS memory."""
import argparse
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    from ..schemas import TOOLS
    modules = {"pydanticai": "pydantic_ai", "agents": "agents", "langgraph": "langgraph.graph"}
    env = dict(os.environ, PYDANTIC_AI_NO_BANNER="1", LANGCHAIN_TRACING_V2="false", LANGSMITH_TRACING="false")
    output = [{"type": "function_call", "id": "fc_read", "call_id": "call_read", "name": "read_state",
               "arguments": "{}", "status": "completed"}]
    def response(items, number):
        return {"id": f"resp_{number}", "object": "response", "created_at": 1,
                "status": "completed", "model": "gpt-6-luna", "output": items,
                "usage": {"input_tokens": 10, "output_tokens": 5, "total_tokens": 15}}
    replay = [response(output, 1), response([{"type": "message", "id": "msg_1", "role": "assistant", "status": "completed",
              "content": [{"type": "output_text", "text": "Synthetic preview only.", "annotations": []}]}], 2)]
    replay_path = args.output / "replay.json"
    replay_path.write_text(json.dumps(replay))
    inputs = [{"session_id": "evidence-session", "event": {"type": "user", "text": "Read the current synthetic planner state."}},
              {"session_id": "evidence-session", "event": {"type": "restart"}}]
    stdin = "".join(json.dumps(item) + "\n" for item in inputs)
    (args.output / "input.jsonl").write_text(stdin)
    results = {}
    for name, module in modules.items():
        probe = ("import importlib,json,resource,time; start=time.perf_counter(); "
                 f"importlib.import_module({module!r}); "
                 "print(json.dumps({'import_seconds':time.perf_counter()-start,"
                 "'peak_rss_kib':resource.getrusage(resource.RUSAGE_SELF).ru_maxrss}))")
        imported = subprocess.run([sys.executable, "-c", probe], text=True, capture_output=True, env=env)
        (args.output / f"{name}-import.stdout").write_text(imported.stdout)
        (args.output / f"{name}-import.stderr").write_text(imported.stderr)
        command = [sys.executable, "-m", "scripts.ai.architecture_lab.frameworks.runner", "--framework", name,
                   "--storage", str(args.output / name / str(time.time_ns())), "--replay", str(replay_path), "--transcript", str(args.output / f"{name}-requests.jsonl")]
        start = time.perf_counter()
        run = subprocess.run(command, input=stdin, text=True, capture_output=True, env=env)
        elapsed = time.perf_counter() - start
        (args.output / f"{name}-run.jsonl").write_text(run.stdout)
        (args.output / f"{name}-run.stderr").write_text(run.stderr)
        results[name] = {"import": json.loads(imported.stdout), "process_elapsed_seconds": elapsed,
                         "exit_code": run.returncode, "command": command,
                         "responses": len(run.stdout.splitlines()), "evidence_kind": "offline_scripted"}
        assert run.returncode == 0
        for line in run.stdout.splitlines():
            assert json.loads(line).get("error") is None, line
    distributions = []
    for dist in importlib.metadata.distributions():
        files = [dist.locate_file(file) for file in (dist.files or [])]
        distributions.append({"name": dist.metadata["Name"], "version": dist.version,
                              "installed_record_bytes": sum(file.stat().st_size for file in files if file.is_file())})
    manifest = {"platform": platform.platform(), "python": sys.version, "executable": sys.executable,
                "frameworks": results, "distributions": distributions,
                "tools": [tool["name"] for tool in TOOLS], "paid_evaluation": "pending",
                "notes": "Single observations on Linux, shared venv; RSS is process high-water mark, not iOS RAM. Scripted usage is fake."}
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2))
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
