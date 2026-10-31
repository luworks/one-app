"""Typed lossless boundary for canonical planner state, shared by SDK candidates.

PlannerWorld remains the policy/schema authority. These models type stable state
handles without inventing independent application behavior or oracle labels.
"""
from typing import Any, Literal
from pydantic import BaseModel, ConfigDict, Field


class OpenState(BaseModel):
    model_config = ConfigDict(extra="allow")


class EntityState(OpenState):
    id: str
    version: int = Field(ge=1)
    kind: Literal["event", "reminder", "alarm", "note"]
    title: str
    due: str | None
    start: str | None
    end: str | None
    timezone: str
    weekdays: list[int]
    attendees: list[str]


class ProposalState(OpenState):
    proposal_id: str
    version: int = Field(ge=1)
    base_revision: int = Field(ge=1)
    status: str
    changes: list[dict[str, Any]]


class ReceiptState(OpenState):
    receipt_id: str
    status: str
    revision: int


class PlannerState(OpenState):
    schema_version: Literal["planner-world-v1"]
    revision: int = Field(ge=1)
    entities: dict[str, EntityState]
    proposals: dict[str, ProposalState]
    receipts: list[ReceiptState]
    events: list[dict[str, Any]]
