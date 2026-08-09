from __future__ import annotations

import argparse
import json
import sqlite3
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from dotenv import load_dotenv
from langgraph.checkpoint.sqlite import SqliteSaver

from inbox_agent.analyzer import OpenAIAnalyzer
from inbox_agent.gmail_client import GmailClient
from inbox_agent.graph import Dependencies, build_graph
from inbox_agent.settings import Settings
from inbox_agent.store import ProcessedStore

DEFAULT_QUERY = "is:unread newer_than:1d -category:promotions -category:social -label:AI/Obradeno"


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Jutarnja obrada Gmaila; zadano je siguran dry-run bez ikakvih promjena."
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--apply", action="store_true", help="Stvori skice i dodaj Gmail oznake.")
    mode.add_argument(
        "--dry-run", action="store_true", help="Samo prikaži planirane radnje (zadano)."
    )
    parser.add_argument("--limit", type=int, default=20, help="Najviše poruka, 1-100.")
    parser.add_argument("--message-id", help="Obradi samo navedeni Gmail message ID.")
    parser.add_argument("--query", default=DEFAULT_QUERY, help="Gmail search query.")
    parser.add_argument("--model", help="Nadjačaj OPENAI_MODEL iz .env.")
    return parser.parse_args(argv)


def _write_summary(results: list[dict], output_dir: Path, timezone: str) -> Path:
    now = datetime.now(ZoneInfo(timezone))
    path = output_dir / f"jutarnji-pregled-{now:%Y-%m-%d}.md"
    lines = [f"# Jutarnji pregled pošte - {now:%d.%m.%Y.}", "", f"Poruka: {len(results)}", ""]
    for index, result in enumerate(results, start=1):
        message = result.get("message", {})
        analysis = result.get("analysis", {})
        lines.extend(
            [
                "## "
                f"{index}. [{str(analysis.get('priority', 'normal')).upper()}] "
                f"{message.get('subject', '(bez naslova)')}",
                "",
                f"- Od: {message.get('sender_name', '')} <{message.get('sender_email', '')}>",
                f"- Ishod: {result.get('outcome', '')}",
                f"- Pouzdanost: {float(analysis.get('confidence', 0)):.2f}",
                f"- Sažetak: {analysis.get('summary', '')}",
                f"- Razlog: {analysis.get('reason', '')}",
            ]
        )
        if analysis.get("has_calendar_item"):
            lines.append(
                "- Kalendar (samo prijedlog): "
                f"{analysis.get('event_title', '')}; "
                f"{analysis.get('event_start') or 'vrijeme nije pouzdano određeno'}; "
                f"{analysis.get('event_timezone') or timezone}"
            )
        lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")
    return path


def main(argv: list[str] | None = None) -> int:
    load_dotenv()
    args = parse_args(argv)
    apply_changes = bool(args.apply)
    if not 1 <= args.limit <= 100:
        raise SystemExit("--limit mora biti između 1 i 100.")

    settings = Settings.from_env()
    settings.prepare_directories()
    settings.validate()
    gmail = GmailClient.from_oauth(settings.credentials_file, settings.token_file)
    store = ProcessedStore(settings.processed_db)
    labels = {settings.processed_label: "", settings.review_label: ""}
    if apply_changes:
        labels = gmail.ensure_labels([settings.processed_label, settings.review_label])

    checkpoint_connection = sqlite3.connect(settings.checkpoint_db, check_same_thread=False)
    checkpointer = SqliteSaver(checkpoint_connection)
    if hasattr(checkpointer, "setup"):
        checkpointer.setup()
    graph = build_graph(
        Dependencies(
            gmail=gmail,
            analyzer=OpenAIAnalyzer(args.model or settings.openai_model),
            processed_store=store,
            apply=apply_changes,
            processed_label_id=labels[settings.processed_label],
            review_label_id=labels[settings.review_label],
        ),
        checkpointer=checkpointer,
    )

    message_ids = (
        [args.message_id] if args.message_id else gmail.list_message_ids(args.query, args.limit)
    )
    results: list[dict] = []
    failures = 0
    for message_id in message_ids:
        if apply_changes and store.is_processed(message_id):
            print(
                json.dumps(
                    {"message_id": message_id, "outcome": "PRESKOČENO: već obrađeno"},
                    ensure_ascii=False,
                )
            )
            continue
        try:
            result = graph.invoke(
                {"message_id": message_id},
                config={"configurable": {"thread_id": message_id}, "recursion_limit": 12},
            )
            results.append(result)
            print(
                json.dumps(
                    {
                        "message_id": message_id,
                        "subject": result.get("message", {}).get("subject"),
                        "outcome": result.get("outcome"),
                        "confidence": result.get("analysis", {}).get("confidence"),
                    },
                    ensure_ascii=False,
                )
            )
        except Exception as exc:  # svaki mail je zasebna jedinica rada
            failures += 1
            print(json.dumps({"message_id": message_id, "error": str(exc)}, ensure_ascii=False))

    summary_path = _write_summary(results, settings.output_dir, settings.timezone)
    print(f"Sažetak: {summary_path}")
    store.close()
    checkpoint_connection.close()
    return 1 if failures else 0
