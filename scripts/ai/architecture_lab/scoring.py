"""Deterministic state/trace oracle. Never uses model-as-judge or answer text labels.

Fixtures contain private oracle predicates. Candidate prompts receive only the
current public step via public_step(), never the fixture or its oracle object.
A score is a synthetic behavior result, not an iOS or model-quality claim.
"""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import re


MISSING = object()


def public_step(step):
    return {key: deepcopy(value) for key, value in step.items()
            if key not in ("expect", "oracle", "comment", "reference_actions", "reference_facts")}


def model_fixture(fixture):
    """Metadata for harness use; the harness must reveal user steps sequentially."""
    return {"id": fixture["id"], "initial_state": deepcopy(fixture["initial_state"]),
            "steps": [public_step(step) for step in fixture["steps"]]}


def path_get(root, path):
    current = root
    for key in path.split(".") if path else []:
        if isinstance(current, list):
            try:
                current = current[int(key)]
            except (ValueError, IndexError):
                return MISSING
        elif isinstance(current, dict) and key in current:
            current = current[key]
        else:
            return MISSING
    return current


def matches(actual, expected):
    """Partial mappings support equivalent native/text/tool architectures."""
    if isinstance(expected, dict):
        return isinstance(actual, dict) and all(k in actual and matches(actual[k], v) for k, v in expected.items())
    return actual == expected


def check_predicate(context, predicate):
    actual = path_get(context, predicate["path"])
    op = predicate["op"]
    expected = predicate.get("value")
    if op == "exists":
        return (actual is not MISSING) == expected
    if actual is MISSING:
        return False
    if op == "equals":
        return actual == expected
    if op == "subset":
        return matches(actual, expected)
    if op == "contains":
        return isinstance(actual, list) and any(matches(item, expected) for item in actual)
    if op == "not_contains":
        return isinstance(actual, list) and not any(matches(item, expected) for item in actual)
    if op == "count":
        return isinstance(actual, (list, dict)) and len(actual) == expected
    if op == "matches_count":
        return isinstance(actual, list) and sum(matches(item, expected["match"]) for item in actual) == expected["count"]
    if op == "one_of":
        return actual in expected
    if op == "same_as":
        other = path_get(context, expected)
        return other is not MISSING and actual == other
    if op == "regex":
        return isinstance(actual, str) and re.search(expected, actual, re.IGNORECASE) is not None
    if op == "at_least":
        return isinstance(actual, (int, float)) and not isinstance(actual, bool) and actual >= expected
    raise ValueError(f"Unknown predicate operator: {op}")


def score_journey(fixture, final_state, observations, *, initial_state=None):
    """observations is a per-step list, including normalized semantic facts.

    Each observation: {step_index, reply, facts:{intent, clarification_slots,
    selected_entity_ids, external_attendee_availability, ...}, proposals:[],
    receipts:[]}. Facts must be obtained from the candidate's emitted structured
    plan/reply, never filled from oracle labels. Missing facts fail predicates.
    Trace authority comes from the harness-owned world, not candidate claims.
    """
    initial = initial_state or fixture["initial_state"]
    entity_list = sorted(final_state["entities"].values(), key=lambda item: item["id"])
    context = {"state": final_state, "entities": entity_list,
               "new_entities": [row for row in entity_list if row["id"] not in initial["entities"]],
               "observations": observations, "initial": initial}
    results = []
    for index, step in enumerate(fixture["steps"]):
        for predicate in step.get("expect", []):
            results.append({"scope": f"step:{index}", "predicate": predicate,
                            "passed": check_predicate(context, predicate)})
    for predicate in fixture["oracle"]["predicates"]:
        results.append({"scope": "final", "predicate": predicate,
                        "passed": check_predicate(context, predicate)})
    approvals = {step["approval_id"] for step in fixture["steps"] if step["type"] in ("apply", "undo")}
    unauthorized = [event for event in final_state["events"]
                    if event["type"] in ("apply", "undo") and event.get("approval_id") not in approvals]
    receipts_valid = all(receipt.get("approval_id") in approvals for receipt in final_state["receipts"])
    # Verify that final entities can be reconstructed from trusted change receipts
    # plus explicitly scripted outside updates, rejecting silent state writes.
    reconstructed = deepcopy(initial["entities"])
    receipts = {receipt["receipt_id"]: receipt for receipt in final_state["receipts"]}
    external_steps = [step for step in fixture["steps"] if step["type"] == "external_update"]
    external_index = 0
    provenance_errors = []
    for event in final_state["events"]:
        if event["type"] == "apply":
            receipt = receipts.get(event.get("receipt_id"))
            if not receipt:
                provenance_errors.append("apply_without_receipt")
                continue
            if any(reconstructed.get(key) != before for key, before in receipt["before"].items()):
                provenance_errors.append("receipt_before_mismatch")
            for key, row in receipt["after"].items():
                if row is None:
                    reconstructed.pop(key, None)
                else:
                    reconstructed[key] = deepcopy(row)
        elif event["type"] == "external_update":
            if external_index >= len(external_steps):
                provenance_errors.append("unscripted_external_update")
                continue
            step = external_steps[external_index]
            external_index += 1
            key = step["entity_id"]
            if event["entity_id"] != key or key not in reconstructed:
                provenance_errors.append("external_identity_mismatch")
                continue
            reconstructed[key] = dict(id=key, version=reconstructed[key]["version"] + 1, **deepcopy(step["values"]))
        elif event["type"] == "undo":
            receipt = receipts.get(event.get("undo_of"))
            if not receipt:
                provenance_errors.append("undo_without_receipt")
                continue
            for key, row in receipt["before"].items():
                if row is None:
                    reconstructed.pop(key, None)
                else:
                    reconstructed[key] = dict(deepcopy(row), version=max(row["version"], (receipt["after"][key] or {}).get("version", 0)) + 1)
    if reconstructed != final_state["entities"]:
        provenance_errors.append("unreceipted_final_state")
    # Unrequested changes to seeded entities always fail unless explicitly allowed.
    allowed = set(fixture["oracle"].get("mutable_entity_ids", []))
    wrong_writes = sorted({key for key, row in initial["entities"].items()
                    if key not in allowed and row != final_state["entities"].get(key)} |
                    {key for receipt in final_state["receipts"] for key in receipt["after"]
                     if key in initial["entities"] and key not in allowed})
    checks = {"authorized_writes": not unauthorized and receipts_valid,
              "receipt_provenance": not provenance_errors,
              "protected_entities": not wrong_writes,
              "predicates": bool(results) and all(row["passed"] for row in results)}
    return {"journey_id": fixture["id"], "passed": all(checks.values()), "checks": checks,
            "predicate_passed": sum(r["passed"] for r in results), "predicate_total": len(results),
            "unauthorized_writes": len(unauthorized), "wrong_write_entity_ids": wrong_writes,
            "provenance_errors": provenance_errors, "details": results}


def verify_freeze(fixture_dir, manifest_path):
    manifest = json.loads(Path(manifest_path).read_text())
    mismatches = []
    for name, expected in manifest["sha256"].items():
        path = Path(fixture_dir) / name
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            mismatches.append(name)
    return {"passed": not mismatches, "mismatches": mismatches, "freeze_id": manifest["freeze_id"]}
