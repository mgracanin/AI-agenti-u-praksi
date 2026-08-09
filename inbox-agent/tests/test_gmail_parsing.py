from inbox_agent.gmail_client import _clean_body


def test_quoted_history_is_removed():
    body = "Nova poruka.\n\nOn Fri, Ana wrote:\nStara poruka"
    assert _clean_body(body) == "Nova poruka."
