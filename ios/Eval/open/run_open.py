#!/usr/bin/env python3
"""Run open small models (via llama.cpp llama-server, JSON-schema constrained output, temperature 0) on the same
eval files the Apple Foundation Models spike uses. Prompts are copied from ios/One/Understanding.swift.

usage: run_open.py MODEL SET MODE [--out DIR]
  SET:  r1 | r3 | r4 | edit4      MODE: full | kind | edit
Writes DIR/<model>__<SET>__<MODE>.json = list of {input, out, error, seconds, eval_count, prompt_count}.
Scoring is in score_open.py. Standard library only.
"""
import json, sys, time, urllib.request, pathlib, datetime, re

HERE = pathlib.Path(__file__).resolve().parent
CASES = HERE.parent / "Understanding"
FILES = {
    "r1": CASES / "understanding-cases.json",
    "r3": CASES / "understanding-cases-r3.json",
    "r4": CASES / "understanding-cases-r4.json",
    "edit4": CASES / "edit-cases-r4.json",
}
SERVER = "http://127.0.0.1:8089/v1/chat/completions"

NOW = datetime.datetime(2026, 10, 15, 9, 41)
WEEKDAY_EN = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
WEEKDAY_ZH = ["一", "二", "三", "四", "五", "六", "日"]


def full_instructions(locale="zh_CN", table=True):
    lines = [
        "You extract ONE action from the user's message for a planner app.",
        "Today is Thursday 2026-10-15, timezone Asia/Shanghai.",
        f"The person's locale is {locale}.",
        "kind: addTask = something to do. addEvent = a meeting, appointment, meal or trip at a fixed time. "
        "addAlarm = the user asks to be woken up or rung at a time. other = not an action.",
        "dayOffset counts days from today. hour is a 24-hour clock: 3pm and 下午3点 are 15.",
        "If no day is given leave dayOffset empty. If no time is given leave hour and minute empty. Never invent them.",
        "Keep the title in the user's original language.",
    ]
    if table:
        lines.append("Calendar (dayOffset, weekday). A bare weekday means its next occurrence; 下周X / next X is in the "
                     "week starting Monday Thursday 2026-10-19:".replace("Thursday 2026-10-19", "Monday 2026-10-19"))
        for n in range(14):
            d = NOW.date() + datetime.timedelta(days=n)
            w = d.weekday()
            lines.append(f"{n} = {WEEKDAY_EN[w]} 周{WEEKDAY_ZH[w]}")
    return "\n".join(lines)


def kind_instructions(locale="zh_CN"):
    return "\n".join([
        "You classify ONE message for a planner app.",
        f"The person's locale is {locale}.",
        "task = something to do. event = a meeting, appointment, meal, trip or class. "
        "alarm = the user asks to be woken up or rung at a time. Ignore dates and times.",
    ])


def opt_int(desc=None):
    d = {"anyOf": [{"type": "integer"}, {"type": "null"}]}
    if desc:
        d["description"] = desc
    return d


FULL_SCHEMA = {
    "type": "object",
    "properties": {
        "kind": {"type": "string", "enum": ["addTask", "addEvent", "addAlarm", "other"]},
        "title": {"type": "string", "description": "Short title in the user's own language, without date or time words"},
        "dayOffset": opt_int("Days from today: 0 today, 1 tomorrow. Empty if the user gave no day"),
        "hour": opt_int("Hour on a 24-hour clock. Empty if the user gave no time"),
        "minute": opt_int(),
        "durationMinutes": opt_int("Length in minutes, only if the user gave a length or a time range"),
    },
    "required": ["kind", "title", "dayOffset", "hour", "minute", "durationMinutes"],
}
KIND_SCHEMA = {
    "type": "object",
    "properties": {"kind": {"type": "string", "enum": ["task", "event", "alarm"]}},
    "required": ["kind"],
}
EDIT_SCHEMA = {
    "type": "object",
    "properties": {
        "op": {"type": "string", "enum": ["move", "delete", "clarify", "none"]},
        "target": {"anyOf": [{"type": "string"}, {"type": "null"}]},
        "dayOffset": opt_int(),
        "hour": opt_int(),
        "minute": opt_int(),
    },
    "required": ["op", "target", "dayOffset", "hour", "minute"],
}


def edit_instructions():
    tpl = (CASES / "edit-prompt-r4.txt").read_text()
    items = (HERE / "edit-items-r4.txt").read_text().strip()
    return tpl.replace("{ITEMS}", items)


def chat(model, system, user, schema, num_ctx=4096, think=False):
    """llama-server (llama.cpp) OpenAI-style endpoint with a JSON-schema grammar, temperature 0.
    `model` is only a label here: the server is started for one model by run_all.sh."""
    body = {
        "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
        "temperature": 0, "seed": 7, "max_tokens": 200,
        "response_format": {"type": "json_object", "schema": schema},
        "chat_template_kwargs": {"enable_thinking": False},
    }
    req = urllib.request.Request(SERVER, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            j = json.load(r)
    except urllib.error.HTTPError as e:
        raise RuntimeError(e.read().decode()[:300])
    u = j.get("usage", {})
    return {"message": {"content": j["choices"][0]["message"]["content"]},
            "eval_count": u.get("completion_tokens"), "prompt_eval_count": u.get("prompt_tokens")}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    model, name, mode = args[:3]
    out_dir = pathlib.Path(sys.argv[sys.argv.index("--out") + 1]) if "--out" in sys.argv else HERE / "results"
    out_dir.mkdir(exist_ok=True)
    suite = json.load(open(FILES[name]))
    if mode == "full":
        system, schema = full_instructions(), FULL_SCHEMA
    elif mode == "kind":
        system, schema = kind_instructions(), KIND_SCHEMA
    elif mode == "edit":
        system, schema = edit_instructions(), EDIT_SCHEMA
    else:
        raise SystemExit("mode")
    # warm-up: load the model, not counted
    t0 = time.time()
    chat(model, system, "买牛奶", schema)
    cold = time.time() - t0
    rows = []
    for c in suite["cases"]:
        t = time.time()
        try:
            r = chat(model, system, c["input"], schema)
            content = r["message"]["content"]
            out = json.loads(content)
            err = None
            rows.append({"input": c["input"], "out": out, "error": err, "seconds": time.time() - t,
                         "eval_count": r.get("eval_count"), "prompt_count": r.get("prompt_eval_count")})
        except Exception as e:  # noqa: BLE001
            rows.append({"input": c["input"], "out": None, "error": str(e)[:200], "seconds": time.time() - t})
    fn = out_dir / f"{model.replace(':','_')}__{name}__{mode}.json"
    json.dump({"model": model, "set": name, "mode": mode, "cold_seconds": cold, "rows": rows}, open(fn, "w"),
              ensure_ascii=False, indent=1)
    secs = sorted(r["seconds"] for r in rows)
    errs = sum(1 for r in rows if r["error"])
    print(f"{model} {name} {mode}: {len(rows)} cases, errors {errs}, p50 {secs[len(secs)//2]:.2f}s p90 {secs[int(len(secs)*0.9)]:.2f}s cold {cold:.1f}s -> {fn.name}")


if __name__ == "__main__":
    main()
