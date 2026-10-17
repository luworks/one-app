#!/usr/bin/env python3
"""Score results/*.json from run_open.py the same way ios/Eval/Understanding/main.swift scores Apple FM.

usage: score_open.py [results_dir]  -> prints a markdown table per (set, mode) and writes summary.json
Needs parser-outputs-<set>.json (from the spike) for the 'kind' (A2) and hybrid rows; without it only raw rows are scored.
"""
import json, sys, pathlib, datetime, glob, collections

HERE = pathlib.Path(__file__).resolve().parent
CASES = HERE.parent / "Understanding"
FILES = {"r1": "understanding-cases.json", "r3": "understanding-cases-r3.json", "r4": "understanding-cases-r4.json",
         "edit4": "edit-cases-r4.json"}
NOW = datetime.datetime(2026, 10, 15, 9, 41)


def norm(s):
    return "".join(ch for ch in (s or "").lower() if not ch.isspace() and ch not in "，。,.、")


def title_ok(got, want):
    if want is None:
        return True
    a, b = norm(got), norm(want)
    return a == b or a in b or b in a


def from_full(out):
    """Mirror Understanding.capture(from:)."""
    title = (out.get("title") or "").strip()
    kind = out.get("kind")
    if kind == "other" or not title:
        return None
    off = out.get("dayOffset")
    has_day = isinstance(off, int) and 0 <= off <= 365
    day = off if has_day else 0
    hour = out.get("hour") if isinstance(out.get("hour"), int) and 0 <= out["hour"] <= 23 else None
    minute = 0
    if hour is not None:
        m = out.get("minute")
        minute = m if isinstance(m, int) and 0 <= m <= 59 else 0
    if kind == "addAlarm" and hour is None:
        return None
    if hour is not None and not has_day:
        if datetime.time(hour, minute) < NOW.time():
            day, has_day = 1, True
    dur = out.get("durationMinutes")
    cap = {"title": title, "day": day, "hasDay": has_day, "hour": hour, "minute": minute,
           "duration": dur if kind == "addEvent" and isinstance(dur, int) and 1 <= dur <= 1440 else None}
    cap["kind"] = {"addTask": "task", "addEvent": "event", "addAlarm": "alarm"}[kind]
    return cap


def combine_kind(parser, kind):
    """Mirror Understanding.combine(parser:kind:) (A2)."""
    if parser["kind"] == "habit":
        return dict(parser)
    c = dict(parser)
    c["kind"] = "event" if kind == "event" else "task"
    if kind == "alarm" and parser.get("hour") is not None:
        c["kind"] = "alarm"
    return c


def score(case, got):
    if got is None:
        return dict(all=False, kind=False, day=False, hasDay=False, hour=False, minute=False, title=False, dur=False)
    r = {}
    r["kind"] = got["kind"] == case["kind"]
    r["day"] = got["day"] == case["day"]
    r["hasDay"] = got["hasDay"] == case["hasDay"]
    r["hour"] = got.get("hour") == case.get("hour")
    r["minute"] = case.get("hour") is None or got.get("minute", 0) == case.get("minute", 0)
    r["dur"] = case.get("duration") is None or got.get("duration") == case["duration"]
    r["title"] = title_ok(got["title"], case.get("title"))
    r["all"] = all(r[k] for k in ("kind", "day", "hasDay", "hour", "minute", "title", "dur"))
    return r


def pct(rows, key):
    return 100.0 * sum(1 for r in rows if r[key]) / max(1, len(rows))


def pctl(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(len(xs) * p))]


def edit_score(case, out, items):
    exp_start = case.get("start")
    ok_op = out is not None and out.get("op") == case["op"]
    exp_target = case.get("target")
    ok_target = ok_op and (exp_target is None or out.get("target") == exp_target)
    ok_time = True
    if case["op"] == "move":
        d = datetime.datetime.fromisoformat(exp_start)
        off = (d.date() - NOW.date()).days
        ok_time = out is not None and (out.get("dayOffset"), out.get("hour"), out.get("minute")) == (off, d.hour, d.minute)
    return dict(op=ok_op, target=ok_target, time=ok_time, all=ok_op and ok_target and ok_time)


def main():
    rdir = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "results"
    summary = []
    for f in sorted(glob.glob(str(rdir / "*__*__*.json"))):
        d = json.load(open(f))
        name, mode = d["set"], d["mode"]
        suite = json.load(open(CASES / FILES[name]))
        rows = d["rows"]
        label = pathlib.Path(f).name.split("__")[0]
        secs = [r["seconds"] for r in rows]
        errs = sum(1 for r in rows if r["error"])
        if mode == "edit":
            sc = [edit_score(c, r["out"], suite["items"]) for c, r in zip(suite["cases"], rows)]
            summary.append(dict(model=label, set=name, mode="edit", n=len(sc), all=pct(sc, "all"), op=pct(sc, "op"),
                                target=pct(sc, "target"), time=pct(sc, "time"), errors=errs,
                                p50=pctl(secs, .5), p90=pctl(secs, .9), cold=d["cold_seconds"]))
            continue
        parser = None
        pf = HERE / f"parser-outputs-{name}.json"
        if pf.exists():
            parser = {p["input"]: p for p in json.load(open(pf))}
        variants = {}
        if mode == "full":
            caps = [from_full(r["out"]) if r["out"] else None for r in rows]
            variants["full raw"] = caps
            if parser:
                hyb = []
                for c, cap in zip(suite["cases"], caps):
                    cap = dict(cap) if cap else None
                    p = parser.get(c["input"])
                    if cap and p and p["hasDay"]:
                        cap["day"], cap["hasDay"] = p["day"], True
                    hyb.append(cap)
                variants["full + parser day"] = hyb
        else:
            if parser:
                variants["A2 (parser + model kind)"] = [
                    combine_kind(parser[c["input"]], r["out"]["kind"]) if r["out"] and c["input"] in parser else None
                    for c, r in zip(suite["cases"], rows)]
            # kind-only accuracy of the model itself (no parser)
            km = [dict(kind=(r["out"] or {}).get("kind") == c["kind"]) for c, r in zip(suite["cases"], rows)]
            summary.append(dict(model=label, set=name, mode="kind-only", n=len(km), kind=pct(km, "kind"), errors=errs,
                                p50=pctl(secs, .5), p90=pctl(secs, .9), cold=d["cold_seconds"]))
        for vname, caps in variants.items():
            sc = [score(c, cap) for c, cap in zip(suite["cases"], caps)]
            langs = collections.defaultdict(list)
            for c, s in zip(suite["cases"], sc):
                langs[c["lang"]].append(s)
            summary.append(dict(model=label, set=name, mode=vname, n=len(sc), all=pct(sc, "all"), kind=pct(sc, "kind"),
                                day=pct(sc, "day"), hour=pct(sc, "hour"), title=pct(sc, "title"),
                                zh=pct(langs["zh"], "all"), en=pct(langs["en"], "all"), mixed=pct(langs["mixed"], "all"),
                                errors=errs, p50=pctl(secs, .5), p90=pctl(secs, .9), cold=d["cold_seconds"]))
    json.dump(summary, open(rdir / "summary.json", "w"), indent=1)
    for s in summary:
        print({k: (round(v, 1) if isinstance(v, float) else v) for k, v in s.items()})


if __name__ == "__main__":
    main()
