"""Offline positive/negative oracle and world checks; no model inference.

Run from repo root: python3 tests/fixtures/ai/architecture-lab/self_test.py
Set PYTHONPATH to the repository root when invoking by file path.
"""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import subprocess
import sys

from scripts.ai.architecture_lab.world import PlannerWorld, values
from scripts.ai.architecture_lab.schemas import TOOLS, PARAMETERS
from scripts.ai.architecture_lab.scoring import score_journey, public_step, verify_freeze

ROOT = Path(__file__).parent


def load_journeys(split):
    return json.loads((ROOT / f"{split}.json").read_text())["journeys"]


def reference_replay(fixture):
    """Evaluator sanity only; reference actions never represent model results."""
    world = PlannerWorld(fixture["initial_state"])
    observations = []
    for index, step in enumerate(fixture["steps"]):
        observation = {"step_index": index, "facts": deepcopy(step.get("reference_facts", {})),
                       "proposals": [], "receipts": [], "reply": ""}
        try:
            if step["type"] == "user":
                for action in step.get("reference_actions", []):
                    observation["proposals"].append(world.dispatch(action["tool"], action["arguments"]))
            elif step["type"] == "card_edit":
                previous = list(world.snapshot()["proposals"].values())[-1]
                world.dispatch("propose_changes", dict(base_revision=world.revision, proposal_id=previous["proposal_id"],
                    changes=step["changes"], reason="Explicit synthetic card edit"))
            elif step["type"] == "apply":
                proposal = list(world.snapshot()["proposals"].values())[-1]
                observation["receipts"].append(world.apply(proposal["proposal_id"] if step["proposal_id"] == "latest" else step["proposal_id"],
                    proposal["version"] if step["version"] == "latest" else step["version"], approval_id=step["approval_id"]))
            elif step["type"] == "undo":
                receipt = world.snapshot()["receipts"][-1]
                observation["receipts"].append(world.undo(receipt["receipt_id"], approval_id=step["approval_id"]))
            elif step["type"] == "restart":
                world = PlannerWorld.from_snapshot(json.loads(json.dumps(world.snapshot())))
            elif step["type"] == "external_update":
                world.external_update(step["entity_id"], step["values"])
            elif step["type"] == "failure_mode":
                state = world.snapshot()
                state["failure_mode"] = step["mode"]
                world = PlannerWorld(state)
            else:
                raise AssertionError(f"Unknown fixture step: {step['type']}")
        except ValueError as error:
            if not step.get("expect_error"):
                raise
            observation["error"] = str(error)
        else:
            assert not step.get("expect_error"), "Expected rejection did not happen"
        observation["world_revision"] = world.revision
        observations.append(observation)
    return world, observations


def reject(function):
    try:
        function()
    except Exception:
        return True
    raise AssertionError("Adversarial input was accepted")


def propose(world, row=None, *, key=None):
    return world.dispatch("propose_changes", dict(base_revision=world.revision, proposal_id=None,
        changes=[dict(op="update" if key else "create",target_id=key,
                      expected_version=world.snapshot()["entities"][key]["version"] if key else None,
                      values=row or values(title="Synthetic",due="2026-11-05"))],reason="World self-test"))


def run():
    from jsonschema import Draft202012Validator
    for schema in PARAMETERS.values():
        Draft202012Validator.check_schema(schema)
    checks = []
    for fixture in load_journeys("development") + load_journeys("holdout"):
        world, observations = reference_replay(fixture)
        positive = score_journey(fixture, world.snapshot(), observations)
        assert positive["passed"], json.dumps(positive)
        wrong = world.snapshot()
        wrong["entities"]["r-overdue"]["due"] = "2030-01-01"
        assert not score_journey(fixture, wrong, observations)["passed"], "Silent mutation passed"
        wrong = world.snapshot()
        wrong["events"].append({"type":"apply","receipt_id":"forged","approval_id":"not-approved"})
        assert not score_journey(fixture, wrong, observations)["passed"], "Unauthorized event passed"
        if any(step.get("expect") for step in fixture["steps"]):
            missing = deepcopy(observations)
            for row in missing:
                row["facts"] = {}
            assert not score_journey(fixture, world.snapshot(), missing)["passed"], "Missing facts passed"
        for step in fixture["steps"]:
            sanitized = public_step(step)
            assert not set(sanitized) & {"oracle","expect","reference_facts","reference_actions"}
        checks.append({"journey_id":fixture["id"],"positive_reference":True,"negative_mutation":True,"negative_unauthorized":True})
    world = PlannerWorld()
    reject(lambda:world.dispatch("apply", {}))
    reject(lambda:world.dispatch("read_state", {"extra":True}))
    reject(lambda:world.dispatch("free_slots",dict(start="2026-11-02T09:00:00-08:00",end="2026-11-02T12:00:00-08:00",duration_minutes=True,calendar="all")))
    reject(lambda:world.dispatch("schedule_range",dict(start="2026-11-02T09:00:00",end="2026-11-03T09:00:00",calendar="all")))
    reject(lambda:propose(world,values(due="2027-03-14T02:30:00-08:00")))
    reject(lambda:propose(world,values(due="2026-11-05T09:00:00-08:00",weekdays=[3,3])))
    reject(lambda:propose(world,values(title="Invalid",due="2026-11-05",planned_start="2026-11-05")))
    reject(lambda:propose(world,values("note",title="Idea",due="2026-11-05")))
    reject(lambda:propose(world,values("event",title="Backwards",start="2026-11-05T10:00:00-08:00",end="2026-11-05T09:00:00-08:00")))
    reject(lambda:propose(world,values(),key="Dentist"))
    p=propose(world)
    before=world.snapshot()["entities"]
    reject(lambda:world.apply(p["proposal_id"],p["version"],approval_id=""))
    assert world.snapshot()["entities"]==before
    r=world.apply(p["proposal_id"],p["version"],approval_id="a1")
    assert world.apply(p["proposal_id"],p["version"],approval_id="a1")==r
    assert len(world.snapshot()["receipts"])==1
    p2=propose(world,values(title="Second",due="2026-11-06"))
    reject(lambda:world.apply(p2["proposal_id"],p2["version"],approval_id="a1"))
    world.undo(r["receipt_id"],approval_id="u1")
    reject(lambda:world.undo(r["receipt_id"],approval_id="u2"))
    # An obsolete preview version cannot write; revision changes invalidate all previews.
    world=PlannerWorld()
    p=propose(world)
    p2=world.dispatch("propose_changes",dict(base_revision=1,proposal_id=p["proposal_id"],changes=p["changes"],reason="Revised"))
    reject(lambda:world.apply(p["proposal_id"],p["version"],approval_id="old"))
    world.external_update("r-report",values(title="Report",due="2026-11-07",calendar="work"))
    reject(lambda:world.apply(p2["proposal_id"],p2["version"],approval_id="stale"))
    # DST recurrence preserves local hour across rollback.
    world=PlannerWorld()
    p=propose(world,values(title="Stretch",due="2026-10-31T08:00:00-07:00",weekdays=[5,6]))
    world.apply(p["proposal_id"],1,approval_id="recurring")
    rows=world.dispatch("schedule_range",dict(start="2026-10-31T00:00:00-07:00",end="2026-11-02T00:00:00-08:00",calendar="personal"))["occurrences"]
    assert [r["start"] for r in rows if r["entity_id"].startswith("n-")]==["2026-10-31T15:00:00+00:00","2026-11-01T16:00:00+00:00"]
    # Query boundaries and local-only free slots never imply attendee availability.
    world=PlannerWorld()
    slots=world.dispatch("free_slots",dict(start="2026-11-02T09:00:00-08:00",end="2026-11-02T12:00:00-08:00",duration_minutes=30,calendar="all"))
    assert slots["slots"]==[{"start":"2026-11-02T18:00:00+00:00","end":"2026-11-02T19:00:00+00:00"}]
    assert slots["external_attendee_availability"]=="unknown"
    # Bridge stdout is machine-readable and state survives JSON serialization.
    request={"tool":"read_state","arguments":{}}
    process=subprocess.run([sys.executable,"-m","scripts.ai.architecture_lab.world"],input=json.dumps(request)+"\n",text=True,capture_output=True,check=True)
    response=json.loads(process.stdout)
    assert response["result"]["revision"]==1 and not process.stderr
    assert PlannerWorld(response["state"]).snapshot()==response["state"]
    freeze=verify_freeze(ROOT,ROOT/"freeze-manifest.json")
    assert freeze["passed"], freeze
    return {"evidence_kind":"offline_reference_self_test","model_calls":0,"journey_count":len(checks),
            "journey_checks":checks,"world_adversarial_checks":"passed","bridge":"passed","freeze":freeze}


if __name__ == "__main__":
    print(json.dumps(run(),indent=2))
