"""Sequential synthetic journey execution and deterministic oracle integration.

A runner may be sync or async. Only public current-step fields reach a candidate;
reference actions and facts never generate model replies or candidate behavior.
"""
from copy import deepcopy
import inspect
import time
from .scoring import score_journey


def event_for(step, state):
    kind = step["type"]
    if kind == "user":
        return {"type": kind, "text": step["text"]}
    if kind == "restart":
        return {"type": kind}
    if kind == "failure_mode":
        return {"type": kind, "mode": step.get("mode")}
    if kind not in ("apply", "undo", "card_edit", "external_update"):
        raise ValueError("Unsupported public fixture event: " + kind)
    arguments = deepcopy(step.get("arguments", {k: v for k, v in step.items()
                                if k not in ("type", "expect", "oracle", "reference_actions", "reference_facts", "comment")}))
    if kind in ("apply", "card_edit"):
        if arguments.get("proposal_id") == "latest":
            proposals = list(state["proposals"].values())
            if not proposals:
                raise ValueError("No proposal available for explicit fixture control")
            arguments["proposal_id"] = proposals[-1]["proposal_id"]
        if arguments.get("version") == "latest":
            arguments["version"] = state["proposals"][arguments["proposal_id"]]["version"]
    if kind == "undo" and arguments.get("receipt_id") == "latest":
        if not state["receipts"]:
            raise ValueError("No receipt available for Undo")
        arguments["receipt_id"] = state["receipts"][-1]["receipt_id"]
    return {"type": kind, "arguments": arguments}


async def run_journey(runner, fixture, *, session_id):
    state = deepcopy(fixture["initial_state"])
    observations, raw = [], []
    errors = []
    started = time.perf_counter()
    for index, step in enumerate(fixture["steps"]):
        try:
            event = event_for(step, state)
            request = {"session_id": session_id, "event": event}
            if index == 0:
                request["initial_state"] = deepcopy(state)
            result = runner.handle(request)
            if inspect.isawaitable(result):
                result = await result
            raw.append(result)
            if result.get("error"):
                raise ValueError("Candidate returned error: " + str(result["error"]))
            state = result["state"]
            observations.append({"step_index": index, "reply": result.get("reply", ""),
                                 "facts": result.get("facts", {}), "proposals": result.get("proposals", []),
                                 "receipts": result.get("receipts", [])})
        except Exception as exc:
            errors.append({"step_index": index, "type": type(exc).__name__, "message": str(exc)})
            # Preserve partial execution, score missing observations as failures,
            # and stop; do not invent follow-ups or auto-retry unresolved writes.
            break
    score = score_journey(fixture, state, observations)
    if errors:
        score["passed"] = False
    return {"session_id": session_id, "journey_id": fixture["id"], "score": score,
            "execution_complete": not errors and len(observations) == len(fixture["steps"]),
            "errors": errors, "observations": observations, "raw": raw,
            "elapsed_ms": (time.perf_counter() - started) * 1000}
