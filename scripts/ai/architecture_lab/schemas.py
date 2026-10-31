"""Canonical v1 synthetic planner tool schemas, shared by every architecture."""
from copy import deepcopy

SCHEMA_VERSION = "planner-world-v1"


def obj(properties):
    return {"type": "object", "properties": properties,
            "required": list(properties), "additionalProperties": False}


def nullable(schema):
    return {"anyOf": [schema, {"type": "null"}]}


STRING = {"type": "string"}
INTEGER = {"type": "integer", "minimum": 1}
VALUES = obj({
    "kind": {"type": "string", "enum": ["event", "reminder", "alarm", "note"]},
    "title": {"type": "string", "minLength": 1, "maxLength": 300},
    "start": nullable(STRING), "end": nullable(STRING), "due": nullable(STRING),
    "timezone": STRING,
    "weekdays": {"type": "array", "items": {"type": "integer", "minimum": 0, "maximum": 6}},
    "attendees": {"type": "array", "items": STRING},
    "calendar": {"type": "string", "enum": ["personal", "work"]},
    "completed": {"type": "boolean"}, "notes": STRING,
})
CHANGE = obj({
    "op": {"type": "string", "enum": ["create", "update", "delete"]},
    "target_id": nullable(STRING), "expected_version": nullable(INTEGER),
    "values": nullable(VALUES),
})
PARAMETERS = {
    "read_state": obj({}),
    "schedule_range": obj({"start": STRING, "end": STRING,
                            "calendar": {"type": "string", "enum": ["all", "personal", "work"]}}),
    "entity_detail": obj({"entity_id": STRING}),
    "free_slots": obj({"start": STRING, "end": STRING,
                        "duration_minutes": {"type": "integer", "minimum": 1, "maximum": 1440},
                        "calendar": {"type": "string", "enum": ["all", "personal", "work"]}}),
    "propose_changes": obj({"base_revision": INTEGER, "proposal_id": nullable(STRING),
                            "changes": {"type": "array", "items": CHANGE, "minItems": 1, "maxItems": 20},
                            "reason": STRING}),
}
DESCRIPTIONS = {
    "read_state": "Read synthetic state and pending proposals. Does not write planner entities.",
    "schedule_range": "Read occurrences overlapping a half-open offset-aware time range, scoped to calendar.",
    "entity_detail": "Read one stable entity handle. Titles are not unique identifiers.",
    "free_slots": "Compute local free intervals from events only. External attendee availability remains unknown.",
    "propose_changes": "Preview a complete atomic change set. Never applies changes. Use full replacement values for update; omit nothing. A new preview version invalidates earlier versions. Harness Apply is required.",
}
TOOLS = [{"type": "function", "name": name, "description": DESCRIPTIONS[name],
          "strict": True, "parameters": deepcopy(parameters)} for name, parameters in PARAMETERS.items()]
TOOL_SCHEMAS = TOOLS


def validate_arguments(name, arguments):
    """Validate strict JSON shape with the actual jsonschema library."""
    from jsonschema import Draft202012Validator
    if name not in PARAMETERS:
        raise ValueError(f"Unknown tool: {name}")
    Draft202012Validator(PARAMETERS[name]).validate(arguments)
