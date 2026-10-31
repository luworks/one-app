"""Deterministic offline PlannerWorld. Only trusted harness methods can write.

CLI: python3 -m scripts.ai.architecture_lab.world
JSONL requests: {"state": snapshot_or_null, "tool": name, "arguments": object}.
Response: {"result": object, "state": snapshot}; errors never mutate the input.
Harness controls use {"control":"apply|undo|external_update", "arguments":...}.
Do not expose controls to model tools. Persist the complete returned state.
"""
from copy import deepcopy
from datetime import datetime, timedelta, timezone
import json
import sys
from zoneinfo import ZoneInfo

from .schemas import SCHEMA_VERSION, VALUES, validate_arguments


def instant(value):
    result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if result.tzinfo is None:
        raise ValueError("An explicit UTC offset is required")
    return result.astimezone(timezone.utc)


def values(kind="reminder", title="Draft", **updates):
    result = dict(kind=kind, title=title, start=None, end=None, due=None,
                  timezone="America/Los_Angeles", weekdays=[], attendees=[],
                  calendar="personal", completed=False, notes="")
    result.update(updates)
    return result


def default_state():
    rows = [
        ("e-dentist-a", values("event", "Dentist", start="2026-11-02T09:00:00-08:00", end="2026-11-02T10:00:00-08:00")),
        ("e-dentist-b", values("event", "Dentist", start="2026-11-03T15:00:00-08:00", end="2026-11-03T16:00:00-08:00")),
        ("e-team", values("event", "Team sync", start="2026-11-02T11:00:00-08:00", end="2026-11-02T12:00:00-08:00", calendar="work", attendees=["alex@example.invalid"])),
        ("r-report", values(title="Report", due="2026-11-02T17:00:00-08:00", calendar="work")),
        ("r-overdue", values(title="Renew library card", due="2026-10-29")),
    ]
    return dict(schema_version=SCHEMA_VERSION, revision=1, now="2026-10-31T09:00:00-07:00",
                timezone="America/Los_Angeles", entities={key: dict(id=key, version=1, **row) for key, row in rows},
                proposals={}, receipts=[], events=[], next_entity=1, next_proposal=1, next_receipt=1,
                failure_mode=None)


class PlannerWorld:
    def __init__(self, initial_state=None):
        self._state = deepcopy(initial_state if initial_state is not None else default_state())
        if self._state.get("schema_version") != SCHEMA_VERSION:
            raise ValueError("Unsupported world schema")

    def snapshot(self):
        return deepcopy(self._state)

    @classmethod
    def from_snapshot(cls, state):
        return cls(state)

    @property
    def revision(self):
        return self._state["revision"]

    def dispatch(self, tool_name, arguments):
        validate_arguments(tool_name, arguments)
        return deepcopy(getattr(self, "_" + tool_name)(**arguments))

    def _read_state(self):
        return {k: deepcopy(self._state[k]) for k in ("schema_version", "revision", "now", "timezone", "entities", "proposals", "receipts")}

    def _entity_detail(self, entity_id):
        return {"entity": deepcopy(self._state["entities"].get(entity_id)), "revision": self.revision,
                "external_attendee_availability": "unknown"}

    def _schedule_range(self, start, end, calendar):
        lo, hi = instant(start), instant(end)
        if hi <= lo or hi - lo > timedelta(days=93):
            raise ValueError("Range must be positive and at most 93 days")
        found = []
        for row in self._state["entities"].values():
            if calendar != "all" and row["calendar"] != calendar:
                continue
            at = row["start"] if row["kind"] == "event" else row["due"]
            if not at:
                continue
            zone = ZoneInfo(row["timezone"])
            seed = datetime.fromisoformat(at)
            if seed.tzinfo is None:
                seed = seed.replace(tzinfo=zone)
            starts = [seed]
            if row["weekdays"]:
                starts = []
                day = lo.astimezone(zone).date() - timedelta(days=1)
                while day <= hi.astimezone(zone).date():
                    candidate = datetime.combine(day, seed.timetz().replace(tzinfo=None), zone)
                    if candidate.weekday() in row["weekdays"] and candidate >= seed:
                        starts.append(candidate)
                    day += timedelta(days=1)
            duration = instant(row["end"]) - instant(row["start"]) if row["kind"] == "event" else timedelta(0)
            for occurrence in starts:
                begin = occurrence.astimezone(timezone.utc)
                finish = begin + duration
                if (finish > lo and begin < hi) if duration else (lo <= begin < hi):
                    found.append(dict(entity_id=row["id"], version=row["version"], title=row["title"], kind=row["kind"],
                                      start=begin.isoformat(), end=finish.isoformat(), calendar=row["calendar"]))
        return {"revision": self.revision, "occurrences": sorted(found, key=lambda r: (r["start"], r["entity_id"])),
                "external_attendee_availability": "unknown"}

    def _free_slots(self, start, end, duration_minutes, calendar):
        occurrences = self._schedule_range(start, end, calendar)["occurrences"]
        cursor, stop = instant(start), instant(end)
        slots = []
        for row in occurrences:
            if row["kind"] != "event":
                continue
            begin, finish = instant(row["start"]), instant(row["end"])
            if begin - cursor >= timedelta(minutes=duration_minutes):
                slots.append({"start": cursor.isoformat(), "end": min(begin, stop).isoformat()})
            cursor = max(cursor, finish)
        if stop - cursor >= timedelta(minutes=duration_minutes):
            slots.append({"start": cursor.isoformat(), "end": stop.isoformat()})
        return {"revision": self.revision, "slots": slots, "external_attendee_availability": "unknown"}

    @staticmethod
    def _validate_values(row):
        from jsonschema import Draft202012Validator
        Draft202012Validator(VALUES).validate(row)
        zone = ZoneInfo(row["timezone"])
        if len(set(row["weekdays"])) != len(row["weekdays"]) or len(set(row["attendees"])) != len(row["attendees"]):
            raise ValueError("Duplicate weekdays or attendees")
        for field in ("start", "end", "due"):
            value = row[field]
            if value is None:
                continue
            if field == "due" and len(value) == 10:
                datetime.strptime(value, "%Y-%m-%d")
                continue
            utc = instant(value)
            local = datetime.fromisoformat(value.replace("Z", "+00:00"))
            if local.replace(tzinfo=None) != utc.astimezone(zone).replace(tzinfo=None):
                raise ValueError("Offset does not match timezone or wall time does not exist")
        if row["kind"] == "event":
            if not row["start"] or not row["end"] or instant(row["end"]) <= instant(row["start"]) or row["due"]:
                raise ValueError("Events require start/end only")
        elif row["start"] or row["end"]:
            raise ValueError("Only events have start/end; reminders have one due")
        if row["kind"] == "alarm" and (not row["due"] or len(row["due"]) == 10):
            raise ValueError("Alarm requires a time")
        if row["kind"] == "note" and (row["due"] or row["weekdays"]):
            raise ValueError("Ideas are not scheduled obligations")
        if row["weekdays"] and not (row["start"] or row["due"]):
            raise ValueError("Recurring items require an anchor date")
        if row["attendees"] and row["kind"] != "event":
            raise ValueError("Only events have attendees")

    def _check_changes(self, changes):
        targets = set()
        for change in changes:
            target = change["target_id"]
            if change["op"] == "create":
                if target is not None or change["expected_version"] is not None or change["values"] is None:
                    raise ValueError("Create requires null target/version and complete values")
            else:
                current = self._state["entities"].get(target)
                if not current or current["version"] != change["expected_version"]:
                    raise ValueError("Unknown handle or stale entity version")
                if target in targets:
                    raise ValueError("Duplicate target in one proposal")
                targets.add(target)
                if (change["op"] == "delete") != (change["values"] is None):
                    raise ValueError("Delete requires null values; update requires complete values")
            if change["values"] is not None:
                self._validate_values(change["values"])

    def _propose_changes(self, base_revision, proposal_id, changes, reason):
        if base_revision != self.revision:
            raise ValueError("Stale world revision")
        self._check_changes(changes)
        if proposal_id is None:
            proposal_id = f"p-{self._state['next_proposal']:04d}"
            self._state["next_proposal"] += 1
            version = 1
        else:
            previous = self._state["proposals"].get(proposal_id)
            if not previous or previous["status"] != "pending":
                raise ValueError("Only pending proposals can be revised")
            version = previous["version"] + 1
        affected = sum(len((c["values"] or self._state["entities"].get(c["target_id"], {})).get("attendees", [])) for c in changes)
        proposal = dict(proposal_id=proposal_id, version=version, base_revision=base_revision,
                        changes=deepcopy(changes), reason=reason, status="pending", affected_attendees=affected)
        self._state["proposals"][proposal_id] = proposal
        self._state["events"].append({"type": "proposal", "proposal_id": proposal_id, "version": version})
        return proposal

    def apply(self, proposal_id, version, *, approval_id):
        """Trusted harness Apply. A nonempty explicit UI approval ID is required."""
        if not isinstance(approval_id, str) or not approval_id.strip():
            raise ValueError("Explicit approval is required")
        for receipt in self._state["receipts"]:
            if receipt.get("approval_id") == approval_id:
                if receipt.get("proposal_id") == proposal_id and receipt.get("proposal_version") == version:
                    return deepcopy(receipt)
                raise ValueError("Approval ID already used for another action")
        proposal = self._state["proposals"].get(proposal_id)
        if not proposal or proposal["version"] != version or proposal["status"] != "pending" or proposal["base_revision"] != self.revision:
            raise ValueError("Stale or resolved proposal")
        self._check_changes(proposal["changes"])
        mode = self._state["failure_mode"]
        if mode in ("offline", "429", "timeout", "unknown"):
            result = {"status": "unknown" if mode in ("timeout", "unknown") else "failed", "reason": mode,
                      "proposal_id": proposal_id, "proposal_version": version, "approval_id": approval_id,
                      "receipt_id": None, "retry_safe": mode in ("offline", "429")}
            self._state["events"].append(dict(type="apply_outcome", **result))
            if result["status"] == "unknown":
                proposal["status"] = "unknown"
            return result
        before, after = {}, {}
        for change in proposal["changes"]:
            target = change["target_id"]
            if change["op"] == "create":
                target = f"n-{self._state['next_entity']:04d}"
                self._state["next_entity"] += 1
            before[target] = deepcopy(self._state["entities"].get(target))
            if change["op"] == "delete":
                del self._state["entities"][target]
                after[target] = None
            else:
                entity = dict(id=target, version=(before[target]["version"] + 1 if before[target] else 1), **deepcopy(change["values"]))
                self._state["entities"][target] = entity
                after[target] = deepcopy(entity)
        self._state["revision"] += 1
        receipt_id = f"receipt-{self._state['next_receipt']:04d}"
        self._state["next_receipt"] += 1
        receipt = dict(receipt_id=receipt_id, status="applied", proposal_id=proposal_id, proposal_version=version,
                       approval_id=approval_id, before=before, after=after, revision=self.revision, undone=False)
        proposal["status"] = "applied"
        self._state["receipts"].append(receipt)
        self._state["events"].append({"type": "apply", "receipt_id": receipt_id, "approval_id": approval_id})
        return deepcopy(receipt)

    def undo(self, receipt_id, *, approval_id):
        if not isinstance(approval_id, str) or not approval_id.strip():
            raise ValueError("Explicit Undo approval required")
        receipt = next((r for r in self._state["receipts"] if r["receipt_id"] == receipt_id), None)
        if not receipt or receipt["undone"]:
            raise ValueError("Unknown or already undone receipt")
        for target, expected in receipt["after"].items():
            if self._state["entities"].get(target) != expected:
                raise ValueError("Undo blocked by outside changes")
        if any((r or {}).get("attendees") for r in [*receipt["before"].values(), *receipt["after"].values()]):
            raise ValueError("Undo never sends attendee updates")
        for target, previous in receipt["before"].items():
            if previous is None:
                self._state["entities"].pop(target, None)
            else:
                self._state["entities"][target] = dict(deepcopy(previous), version=max(previous["version"], (receipt["after"][target] or {}).get("version", 0)) + 1)
        receipt["undone"] = True
        self._state["revision"] += 1
        result = {"status": "undone", "undo_of": receipt_id, "approval_id": approval_id, "revision": self.revision}
        self._state["events"].append(dict(type="undo", **result))
        return result

    def external_update(self, entity_id, values):
        """Harness-only outside calendar mutation, invalidating pending previews."""
        self._validate_values(values)
        current = self._state["entities"][entity_id]
        self._state["entities"][entity_id] = dict(id=entity_id, version=current["version"] + 1, **deepcopy(values))
        self._state["revision"] += 1
        self._state["events"].append({"type": "external_update", "entity_id": entity_id})
        return self._entity_detail(entity_id)


def main():
    for line in sys.stdin:
        try:
            request = json.loads(line)
            world = PlannerWorld(request.get("state"))
            if "tool" in request:
                result = world.dispatch(request["tool"], request.get("arguments", {}))
            elif request.get("control") in ("apply", "undo", "external_update"):
                result = getattr(world, request["control"])(**request.get("arguments", {}))
            elif request.get("control") == "schemas":
                from .schemas import TOOLS
                result = TOOLS
            else:
                raise ValueError("Unknown request")
            print(json.dumps({"result": result, "state": world.snapshot()}, ensure_ascii=False))
        except Exception as error:
            print(json.dumps({"error": type(error).__name__, "message": str(error)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
