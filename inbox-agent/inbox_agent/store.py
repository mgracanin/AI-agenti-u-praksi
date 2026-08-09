from __future__ import annotations

import sqlite3
from pathlib import Path


class ProcessedStore:
    def __init__(self, path: Path):
        self.connection = sqlite3.connect(path)
        self.connection.execute(
            """
            CREATE TABLE IF NOT EXISTS processed_messages (
                message_id TEXT PRIMARY KEY,
                processed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                outcome TEXT NOT NULL,
                draft_id TEXT
            )
            """
        )
        self.connection.commit()

    def is_processed(self, message_id: str) -> bool:
        row = self.connection.execute(
            "SELECT 1 FROM processed_messages WHERE message_id = ?", (message_id,)
        ).fetchone()
        return row is not None

    def mark_processed(self, message_id: str, outcome: str, draft_id: str | None) -> None:
        self.connection.execute(
            """
            INSERT INTO processed_messages(message_id, outcome, draft_id)
            VALUES (?, ?, ?)
            ON CONFLICT(message_id) DO NOTHING
            """,
            (message_id, outcome, draft_id),
        )
        self.connection.commit()

    def close(self) -> None:
        self.connection.close()
