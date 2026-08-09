from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Literal, Protocol

from langgraph.graph import END, START, StateGraph

from inbox_agent.analyzer import Analyzer
from inbox_agent.schemas import InboxState, LoadedMessage


class GmailPort(Protocol):
    def load_message(self, message_id: str) -> LoadedMessage: ...

    def create_reply_draft(self, message: LoadedMessage, draft_text: str) -> str: ...

    def add_labels(self, message_id: str, label_ids: list[str]) -> None: ...


class ProcessedPort(Protocol):
    def mark_processed(self, message_id: str, outcome: str, draft_id: str | None) -> None: ...


@dataclass(frozen=True)
class Dependencies:
    gmail: GmailPort
    analyzer: Analyzer
    processed_store: ProcessedPort
    apply: bool
    processed_label_id: str = ""
    review_label_id: str = ""


def build_graph(deps: Dependencies, checkpointer: Any | None = None):
    def load_message(state: InboxState) -> dict:
        return {"message": deps.gmail.load_message(state["message_id"])}

    def analyze(state: InboxState) -> dict:
        analysis = deps.analyzer(state["message"])
        return {"analysis": analysis.model_dump()}

    def route_after_analysis(state: InboxState) -> Literal["create_draft", "mark_processed"]:
        analysis = state["analysis"]
        if (
            analysis["needs_reply"] is True
            and float(analysis["confidence"]) >= 0.80
            and str(analysis["draft"]).strip()
        ):
            return "create_draft"
        return "mark_processed"

    def create_draft(state: InboxState) -> dict:
        if not deps.apply:
            return {"draft_id": "", "outcome": "DRY-RUN: napravila bi se skica", "applied": False}
        draft_id = deps.gmail.create_reply_draft(
            state["message"], str(state["analysis"]["draft"]).strip()
        )
        return {"draft_id": draft_id, "outcome": "SKICA", "applied": True}

    def mark_processed(state: InboxState) -> dict:
        draft_id = state.get("draft_id") or None
        outcome = state.get("outcome") or ("DRY-RUN: samo sažetak" if not deps.apply else "SAZETAK")
        if deps.apply:
            label_ids = [deps.processed_label_id]
            if draft_id:
                label_ids.append(deps.review_label_id)
            deps.gmail.add_labels(state["message_id"], label_ids)
            deps.processed_store.mark_processed(state["message_id"], outcome, draft_id)
        return {"outcome": outcome, "applied": deps.apply}

    builder = StateGraph(InboxState)
    builder.add_node("load_message", load_message)
    builder.add_node("analyze", analyze)
    builder.add_node("create_draft", create_draft)
    builder.add_node("mark_processed", mark_processed)
    builder.add_edge(START, "load_message")
    builder.add_edge("load_message", "analyze")
    builder.add_conditional_edges(
        "analyze",
        route_after_analysis,
        {"create_draft": "create_draft", "mark_processed": "mark_processed"},
    )
    builder.add_edge("create_draft", "mark_processed")
    builder.add_edge("mark_processed", END)
    return builder.compile(checkpointer=checkpointer)
