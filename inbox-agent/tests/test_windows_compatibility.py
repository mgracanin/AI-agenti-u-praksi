from datetime import datetime
from zoneinfo import ZoneInfo


def test_europe_zagreb_timezone_is_available() -> None:
    value = datetime(2026, 8, 9, 7, 30, tzinfo=ZoneInfo("Europe/Zagreb"))

    assert value.utcoffset() is not None
    assert value.utcoffset().total_seconds() == 2 * 60 * 60
