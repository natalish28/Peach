import base64
import json
from datetime import date

import pytest

from app.ai import agenda_lambda
from app.ai.agenda import AgendaParseError, ParsedAgenda
from app.config import Settings


@pytest.fixture(autouse=True)
def configured(monkeypatch):
    settings = Settings(cognito_user_pool_id="pool", cognito_client_id="client")
    monkeypatch.setattr(agenda_lambda, "get_settings", lambda: settings)
    monkeypatch.setattr(agenda_lambda, "verify_id_token", lambda token, s: {"sub": "u1"})
    return settings


def _event(body: dict | str, token: str | None = "Bearer abc") -> dict:
    return {
        "headers": {"Authorization": token} if token else {},
        "body": body if isinstance(body, str) else json.dumps(body),
    }


GOOD = {"text": "Пн 10:00 синк", "today": "2026-10-28", "tz": "Europe/Kyiv"}


def test_missing_token_is_401() -> None:
    assert agenda_lambda.handler(_event(GOOD, token=None), None)["statusCode"] == 401


def test_bad_token_is_401(monkeypatch) -> None:
    def boom(token, settings):
        raise ValueError("bad")

    monkeypatch.setattr(agenda_lambda, "verify_id_token", boom)
    assert agenda_lambda.handler(_event(GOOD), None)["statusCode"] == 401


def test_long_text_is_413_before_the_model(monkeypatch) -> None:
    def never(*a, **k):
        raise AssertionError("model must not be called")

    monkeypatch.setattr(agenda_lambda, "parse_agenda", never)
    response = agenda_lambda.handler(_event({**GOOD, "text": "x" * 10_001}), None)
    assert response["statusCode"] == 413


@pytest.mark.parametrize(
    "body",
    ["not json", {"text": "x"}, {**GOOD, "tz": "Mars/Base"}, {**GOOD, "text": "  "}],
)
def test_malformed_body_is_400(body) -> None:
    assert agenda_lambda.handler(_event(body), None)["statusCode"] == 400


def test_parse_error_is_422(monkeypatch) -> None:
    def fail(*a, **k):
        raise AgendaParseError("no agenda found in the text")

    monkeypatch.setattr(agenda_lambda, "parse_agenda", fail)
    assert agenda_lambda.handler(_event(GOOD), None)["statusCode"] == 422


def test_success_returns_agenda_and_logs_one_line(monkeypatch, caplog) -> None:
    parsed = ParsedAgenda(items=[{"topic": "t"}], language="uk")
    usage = {"input_tokens": 1000, "output_tokens": 200}
    monkeypatch.setattr(agenda_lambda, "parse_agenda", lambda text, today, tz: (parsed, usage))
    with caplog.at_level("INFO", logger="agenda-parser"):
        response = agenda_lambda.handler(_event(GOOD), None)
    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["agenda"]["items"][0]["topic"] == "t"
    assert body["prompt_version"] == "agenda-v3"
    line = json.loads(caplog.records[-1].message)
    assert line["event"] == "agenda_parsed" and line["user"] == "u1"
    assert line["input_tokens"] == 1000 and line["cost_usd"] > 0 and "latency_ms" in line


def test_base64_body_and_today_are_decoded(monkeypatch) -> None:
    seen = {}

    def fake(text, today, tz):
        seen.update(text=text, today=today)
        return ParsedAgenda(items=[{"topic": "t"}], language="en"), {
            "input_tokens": 1,
            "output_tokens": 1,
        }

    monkeypatch.setattr(agenda_lambda, "parse_agenda", fake)
    event = _event("")
    event["body"] = base64.b64encode(json.dumps(GOOD).encode()).decode()
    event["isBase64Encoded"] = True
    assert agenda_lambda.handler(event, None)["statusCode"] == 200
    assert seen == {"text": GOOD["text"], "today": date(2026, 10, 28)}


def test_throttling_is_429(monkeypatch) -> None:
    class Throttled(Exception):
        status_code = 429

    def fail(*a, **k):
        raise Throttled()

    monkeypatch.setattr(agenda_lambda, "parse_agenda", fail)
    assert agenda_lambda.handler(_event(GOOD), None)["statusCode"] == 429
