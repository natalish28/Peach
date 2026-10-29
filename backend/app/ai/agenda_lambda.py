"""agenda-parser Lambda: pasted text in, a suggested agenda out.

Runs outside the VPC (it needs no database) behind its own function URL. It
authenticates the caller, bounds the input, calls Bedrock and logs one JSON line
per parse. It never writes anything.
"""

import base64
import json
import logging
import time
from datetime import date
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.ai.agenda import PROMPT_VERSION, AgendaParseError, cost_usd, parse_agenda
from app.config import get_settings
from app.security import verify_id_token

log = logging.getLogger("agenda-parser")
log.setLevel(logging.INFO)


def _response(status: int, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body, ensure_ascii=False),
    }


def _throttled(exc: Exception) -> bool:
    return getattr(exc, "status_code", None) == 429


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    settings = get_settings()
    # CORS preflight is answered by the function URL itself; this is only POST.
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}

    auth = headers.get("authorization", "")
    if not settings.auth_configured:
        return _response(503, {"error": "Authentication is not configured"})
    try:
        if not auth.startswith("Bearer "):
            raise ValueError("missing bearer token")
        user = verify_id_token(auth[7:].strip(), settings)
    except Exception:
        return _response(401, {"error": "Invalid or expired authentication token"})

    raw = event.get("body") or ""
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode("utf-8", errors="replace")
    try:
        body = json.loads(raw)
        text = body["text"]
        today = date.fromisoformat(body["today"])
        tz = body["tz"]
        ZoneInfo(tz)
        if not isinstance(text, str) or not text.strip():
            raise ValueError("empty text")
    except ValueError, KeyError, TypeError, ZoneInfoNotFoundError:
        return _response(400, {"error": "Expected JSON with text, today (YYYY-MM-DD) and tz"})

    if len(text) > settings.parser_max_chars:
        return _response(
            413, {"error": f"Text is longer than {settings.parser_max_chars} characters"}
        )

    started = time.monotonic()
    try:
        agenda, usage = parse_agenda(text, today, tz)
    except AgendaParseError as e:
        return _response(422, {"error": str(e)})
    except Exception as e:
        log.exception("bedrock call failed")
        if _throttled(e):
            return _response(429, {"error": "The service is busy, try again in a minute"})
        return _response(502, {"error": "The model is unavailable"})

    log.info(
        json.dumps(
            {
                "event": "agenda_parsed",
                "user": user["sub"],
                "model": settings.parser_model,
                "prompt_version": PROMPT_VERSION,
                **usage,
                "latency_ms": int((time.monotonic() - started) * 1000),
                "cost_usd": cost_usd(settings.parser_model, usage),
            }
        )
    )
    return _response(
        200,
        {
            "agenda": agenda.model_dump(mode="json"),
            "model": settings.parser_model,
            "prompt_version": PROMPT_VERSION,
        },
    )
