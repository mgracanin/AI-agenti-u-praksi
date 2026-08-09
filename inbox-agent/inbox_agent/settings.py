from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    credentials_file: Path
    token_file: Path
    checkpoint_db: Path
    processed_db: Path
    output_dir: Path
    openai_model: str
    timezone: str
    review_label: str
    processed_label: str

    @classmethod
    def from_env(cls) -> Settings:
        data_dir = Path(os.getenv("INBOX_AGENT_DATA_DIR", ".data"))
        return cls(
            credentials_file=Path(os.getenv("GOOGLE_CREDENTIALS_FILE", "credentials.json")),
            token_file=Path(os.getenv("GOOGLE_TOKEN_FILE", str(data_dir / "token.json"))),
            checkpoint_db=Path(os.getenv("CHECKPOINT_DB", str(data_dir / "checkpoints.sqlite"))),
            processed_db=Path(os.getenv("PROCESSED_DB", str(data_dir / "processed.sqlite"))),
            output_dir=Path(os.getenv("OUTPUT_DIR", "out")),
            openai_model=os.getenv("OPENAI_MODEL", "gpt-5-mini"),
            timezone=os.getenv("TIMEZONE", "Europe/Zagreb"),
            review_label=os.getenv("REVIEW_LABEL", "AI/Za-provjeru"),
            processed_label=os.getenv("PROCESSED_LABEL", "AI/Obradeno"),
        )

    def prepare_directories(self) -> None:
        for path in (self.token_file, self.checkpoint_db, self.processed_db):
            path.parent.mkdir(parents=True, exist_ok=True)
        self.output_dir.mkdir(parents=True, exist_ok=True)

    def validate(self) -> None:
        if not self.credentials_file.is_file():
            raise FileNotFoundError(
                f"Nedostaje {self.credentials_file}. Preuzmite Desktop OAuth "
                "credentials.json iz Google Clouda."
            )
        if not os.getenv("OPENAI_API_KEY"):
            raise RuntimeError("Nedostaje varijabla OPENAI_API_KEY.")
