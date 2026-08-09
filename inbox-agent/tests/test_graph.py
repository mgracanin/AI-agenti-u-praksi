from __future__ import annotations

from pathlib import Path

from inbox_agent.graph import Dependencies, build_graph
from inbox_agent.schemas import EmailAnalysis
from inbox_agent.store import ProcessedStore

MESSAGE = {
    "message_id": "m1",
    "thread_id": "t1",
    "sender_name": "Ana",
    "sender_email": "ana@example.com",
    "subject": "Molim potvrdu",
    "received_at": "2026-08-09T07:00:00+02:00",
    "body": "Možete li potvrditi primitak?",
    "rfc_message_id": "<m1@example.com>",
    "references": "",
}


class FakeGmail:
    def __init__(self):
        self.drafts: list[tuple[str, str]] = []
        self.labels: list[tuple[str, list[str]]] = []

    def load_message(self, message_id: str):
        return {**MESSAGE, "message_id": message_id}

    def create_reply_draft(self, message, draft_text: str) -> str:
        self.drafts.append((message["message_id"], draft_text))
        return "draft-1"

    def add_labels(self, message_id: str, label_ids: list[str]) -> None:
        self.labels.append((message_id, label_ids))


class StaticAnalyzer:
    def __init__(
        self, needs_reply: bool, confidence: float, draft: str = "Hvala, potvrđujem primitak."
    ):
        self.result = EmailAnalysis(
            priority="normal",
            needs_reply=needs_reply,
            summary="Traži potvrdu primitka.",
            reason="Izravno pitanje.",
            draft=draft,
            confidence=confidence,
            has_calendar_item=False,
            event_title="",
            event_start="",
            event_end="",
            event_timezone="Europe/Zagreb",
        )

    def __call__(self, message):
        return self.result


def test_dry_run_never_mutates(tmp_path: Path):
    gmail = FakeGmail()
    store = ProcessedStore(tmp_path / "processed.sqlite")
    graph = build_graph(Dependencies(gmail, StaticAnalyzer(True, 0.95), store, apply=False))
    result = graph.invoke({"message_id": "m1"})
    assert result["outcome"].startswith("DRY-RUN")
    assert gmail.drafts == []
    assert gmail.labels == []
    assert not store.is_processed("m1")


def test_apply_creates_one_draft_and_labels(tmp_path: Path):
    gmail = FakeGmail()
    store = ProcessedStore(tmp_path / "processed.sqlite")
    graph = build_graph(
        Dependencies(
            gmail,
            StaticAnalyzer(True, 0.95),
            store,
            apply=True,
            processed_label_id="processed",
            review_label_id="review",
        )
    )
    result = graph.invoke({"message_id": "m1"})
    assert result["draft_id"] == "draft-1"
    assert gmail.drafts == [("m1", "Hvala, potvrđujem primitak.")]
    assert gmail.labels == [("m1", ["processed", "review"])]
    assert store.is_processed("m1")


def test_low_confidence_never_creates_draft(tmp_path: Path):
    gmail = FakeGmail()
    store = ProcessedStore(tmp_path / "processed.sqlite")
    graph = build_graph(
        Dependencies(
            gmail,
            StaticAnalyzer(True, 0.79),
            store,
            apply=True,
            processed_label_id="processed",
            review_label_id="review",
        )
    )
    result = graph.invoke({"message_id": "m2"})
    assert result["outcome"] == "SAZETAK"
    assert gmail.drafts == []
    assert gmail.labels == [("m2", ["processed"])]
