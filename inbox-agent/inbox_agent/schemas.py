from __future__ import annotations

from typing import Literal, NotRequired, TypedDict

from pydantic import BaseModel, ConfigDict, Field


class EmailAnalysis(BaseModel):
    model_config = ConfigDict(extra="forbid")

    priority: Literal["low", "normal", "high"]
    needs_reply: bool
    summary: str = Field(max_length=800)
    reason: str = Field(max_length=800)
    draft: str = Field(max_length=5000)
    confidence: float = Field(ge=0.0, le=1.0)
    has_calendar_item: bool
    event_title: str = Field(max_length=500)
    event_start: str = Field(
        description="RFC3339 s vremenskom zonom ili prazan niz kada datum nije potpuno određen"
    )
    event_end: str = Field(
        description="RFC3339 s vremenskom zonom ili prazan niz kada datum nije potpuno određen"
    )
    event_timezone: str = Field(default="Europe/Zagreb", max_length=100)


class LoadedMessage(TypedDict):
    message_id: str
    thread_id: str
    sender_name: str
    sender_email: str
    subject: str
    received_at: str
    body: str
    rfc_message_id: str
    references: str


class InboxState(TypedDict):
    message_id: str
    message: NotRequired[LoadedMessage]
    analysis: NotRequired[dict]
    draft_id: NotRequired[str]
    outcome: NotRequired[str]
    applied: NotRequired[bool]
