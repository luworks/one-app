#!/usr/bin/env python3
"""Same prompts, schemas and case files as run_open.py, against the OpenAI API (structured outputs, strict).
usage: run_openai.py MODEL SET MODE [--workers N]
The API key is read from <repo root>/.env (a bare key or KEY=value); it is never printed or written anywhere.
"""
import json, re, sys, time, pathlib, urllib.request, concurrent.futures as cf
import run_open as ro

ENV = ro.HERE.parents[3] / ".env"          # <main checkout>/.env is two levels above .claude/worktrees/...
if not ENV.exists():
    ENV = pathlib.Path("/Users/yuanlu/code/one-app/.env")
KEY = re.search(r"sk-[A-Za-z0-9_-]+", ENV.read_text()).group(0)


def strict(schema):
    s = json.loads(json.dumps(schema))
    s["additionalProperties"] = False
    return s


def call(model, system, user, schema):
    body = {"model": model,
            "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
            "response_format": {"type": "json_schema", "json_schema": {"name": "out", "strict": True, "schema": strict(schema)}}}
    req = urllib.request.Request("https://api.openai.com/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            msg = e.read().decode()
            if e.code in (429, 500, 502, 503) and attempt < 3:
                time.sleep(3 * (attempt + 1)); continue
            raise RuntimeError(re.sub(r"sk-[A-Za-z0-9_-]+", "sk-***", msg)[:200])


def main():
    a = [x for x in sys.argv[1:] if not x.startswith("--")]
    model, name, mode = a[:3]
    workers = int(sys.argv[sys.argv.index("--workers") + 1]) if "--workers" in sys.argv else 6
    suite = json.load(open(ro.FILES[name]))
    system, schema = {"full": (ro.full_instructions(), ro.FULL_SCHEMA), "kind": (ro.kind_instructions(), ro.KIND_SCHEMA),
                      "edit": (ro.edit_instructions(), ro.EDIT_SCHEMA)}[mode]

    def one(c):
        t = time.time()
        try:
            j = call(model, system, c["input"], schema)
            u = j.get("usage", {})
            return {"input": c["input"], "out": json.loads(j["choices"][0]["message"]["content"]), "error": None,
                    "seconds": time.time() - t, "eval_count": u.get("completion_tokens"), "prompt_count": u.get("prompt_tokens"),
                    "reasoning": (u.get("completion_tokens_details") or {}).get("reasoning_tokens")}
        except Exception as e:  # noqa: BLE001
            return {"input": c["input"], "out": None, "error": str(e)[:200], "seconds": time.time() - t}

    with cf.ThreadPoolExecutor(workers) as ex:
        rows = list(ex.map(one, suite["cases"]))
    out_dir = ro.HERE / "results"
    fn = out_dir / f"{model}__{name}__{mode}.json"
    json.dump({"model": model, "set": name, "mode": mode, "cold_seconds": 0.0, "rows": rows}, open(fn, "w"), ensure_ascii=False, indent=1)
    s = sorted(r["seconds"] for r in rows)
    print(f"{model} {name} {mode}: {len(rows)} cases, errors {sum(1 for r in rows if r['error'])}, p50 {s[len(s)//2]:.2f}s p90 {s[int(len(s)*.9)]:.2f}s")


if __name__ == "__main__":
    main()
