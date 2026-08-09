from __future__ import annotations

import base64
import re
from email.mime.text import MIMEText
from email.utils import parseaddr
from html import unescape
from html.parser import HTMLParser
from pathlib import Path
from typing import Any

from inbox_agent.schemas import LoadedMessage

GMAIL_SCOPES = [
    "https://www.googleapis.com/auth/gmail.modify",
    "https://www.googleapis.com/auth/gmail.compose",
]


class _TextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.parts: list[str] = []

    def handle_data(self, data: str) -> None:
        self.parts.append(data)

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() in {"br", "p", "div", "li", "tr"}:
            self.parts.append("\n")

    def text(self) -> str:
        return unescape(" ".join(self.parts))


def _decode_part(data: str | None) -> str:
    if not data:
        return ""
    padding = "=" * (-len(data) % 4)
    return base64.urlsafe_b64decode(data + padding).decode("utf-8", errors="replace")


def _walk_parts(part: dict[str, Any]) -> tuple[list[str], list[str]]:
    plain: list[str] = []
    html: list[str] = []
    mime_type = part.get("mimeType", "")
    body = _decode_part(part.get("body", {}).get("data"))
    if mime_type == "text/plain" and body:
        plain.append(body)
    elif mime_type == "text/html" and body:
        html.append(body)
    for child in part.get("parts", []) or []:
        child_plain, child_html = _walk_parts(child)
        plain.extend(child_plain)
        html.extend(child_html)
    return plain, html


def _clean_body(text: str, limit: int = 12_000) -> str:
    text = text.replace("\r", "")
    text = re.split(
        r"\n(?:On .+ wrote:|Dana .+ napisao je:|From:|Od:|-----Original Message-----)",
        text,
        maxsplit=1,
        flags=re.IGNORECASE,
    )[0]
    text = re.sub(r"\n{3,}", "\n\n", text).strip()
    return text[:limit]


def _payload_text(payload: dict[str, Any]) -> str:
    plain, html_parts = _walk_parts(payload)
    if plain:
        return _clean_body("\n".join(plain))
    parser = _TextExtractor()
    parser.feed("\n".join(html_parts))
    return _clean_body(parser.text())


class GmailClient:
    """Tanki Gmail omotač. Namjerno nema metodu za slanje poruke."""

    def __init__(self, service: Any):
        self.service = service

    @classmethod
    def from_oauth(cls, credentials_file: Path, token_file: Path) -> GmailClient:
        from google.auth.transport.requests import Request
        from google.oauth2.credentials import Credentials
        from google_auth_oauthlib.flow import InstalledAppFlow
        from googleapiclient.discovery import build

        creds = None
        if token_file.exists():
            creds = Credentials.from_authorized_user_file(str(token_file), GMAIL_SCOPES)
        if not creds or not creds.valid:
            if creds and creds.expired and creds.refresh_token:
                creds.refresh(Request())
            else:
                flow = InstalledAppFlow.from_client_secrets_file(
                    str(credentials_file), GMAIL_SCOPES
                )
                creds = flow.run_local_server(port=0)
            token_file.write_text(creds.to_json(), encoding="utf-8")
        return cls(build("gmail", "v1", credentials=creds, cache_discovery=False))

    def list_message_ids(self, query: str, limit: int = 20) -> list[str]:
        response = (
            self.service.users()
            .messages()
            .list(userId="me", q=query, maxResults=min(max(limit, 1), 100))
            .execute(num_retries=3)
        )
        return [item["id"] for item in response.get("messages", [])][:limit]

    def load_message(self, message_id: str) -> LoadedMessage:
        data = (
            self.service.users()
            .messages()
            .get(userId="me", id=message_id, format="full")
            .execute(num_retries=3)
        )
        headers = {
            header.get("name", "").lower(): header.get("value", "")
            for header in data.get("payload", {}).get("headers", [])
        }
        sender_name, sender_email = parseaddr(headers.get("from", ""))
        return LoadedMessage(
            message_id=data["id"],
            thread_id=data["threadId"],
            sender_name=sender_name,
            sender_email=sender_email,
            subject=headers.get("subject", "(bez naslova)"),
            received_at=headers.get("date", ""),
            body=_payload_text(data.get("payload", {})),
            rfc_message_id=headers.get("message-id", ""),
            references=headers.get("references", ""),
        )

    def ensure_labels(self, names: list[str]) -> dict[str, str]:
        existing = (
            self.service.users().labels().list(userId="me").execute(num_retries=3).get("labels", [])
        )
        mapping = {label["name"]: label["id"] for label in existing}
        for name in names:
            if name in mapping:
                continue
            created = (
                self.service.users()
                .labels()
                .create(
                    userId="me",
                    body={
                        "name": name,
                        "labelListVisibility": "labelShow",
                        "messageListVisibility": "show",
                    },
                )
                .execute(num_retries=3)
            )
            mapping[name] = created["id"]
        return {name: mapping[name] for name in names}

    def create_reply_draft(self, message: LoadedMessage, draft_text: str) -> str:
        subject = message["subject"]
        if not re.match(r"^re:", subject, re.IGNORECASE):
            subject = f"Re: {subject}"
        mime = MIMEText(draft_text, _subtype="plain", _charset="utf-8")
        mime["To"] = message["sender_email"]
        mime["Subject"] = subject
        if message["rfc_message_id"]:
            mime["In-Reply-To"] = message["rfc_message_id"]
            references = " ".join(
                item for item in (message["references"], message["rfc_message_id"]) if item
            )
            mime["References"] = references
        raw = base64.urlsafe_b64encode(mime.as_bytes()).decode("ascii").rstrip("=")
        created = (
            self.service.users()
            .drafts()
            .create(
                userId="me",
                body={"message": {"raw": raw, "threadId": message["thread_id"]}},
            )
            .execute(num_retries=3)
        )
        return created["id"]

    def add_labels(self, message_id: str, label_ids: list[str]) -> None:
        (
            self.service.users()
            .messages()
            .modify(userId="me", id=message_id, body={"addLabelIds": label_ids})
            .execute(num_retries=3)
        )
