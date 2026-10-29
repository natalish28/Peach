from httpx import AsyncClient

PAYLOAD = {
    "title": "Pricing sync",
    "duration_minutes": 45,
    "items": [{"topic": "New Pro tariffs", "owner": "Olena", "minutes": 15}],
    "action_items": [{"task": "Competitor comparison", "owner": "Taras", "due": "2026-10-30"}],
    "ai_suggestion": {
        "agenda": {"title": "Pricing sync", "items": [{"topic": "New tariffs"}]},
        "model": "anthropic.claude-opus-5-5",
        "prompt_version": "agenda-v1",
    },
}


async def test_agendas_require_auth(anon_client: AsyncClient) -> None:
    assert (await anon_client.get("/api/v1/agendas")).status_code == 401
    assert (await anon_client.post("/api/v1/agendas", json=PAYLOAD)).status_code == 401


async def test_create_keeps_the_ai_suggestion(client: AsyncClient) -> None:
    response = await client.post("/api/v1/agendas", json=PAYLOAD)
    assert response.status_code == 201
    body = response.json()
    assert body["items"][0]["topic"] == "New Pro tariffs"
    assert body["ai_suggestion"]["prompt_version"] == "agenda-v1"
    listed = (await client.get("/api/v1/agendas")).json()
    assert listed["total"] == 1 and listed["agendas"][0]["id"] == body["id"]


async def test_hand_typed_agenda_has_no_suggestion(client: AsyncClient) -> None:
    payload = {k: v for k, v in PAYLOAD.items() if k != "ai_suggestion"}
    response = await client.post("/api/v1/agendas", json=payload)
    assert response.status_code == 201
    assert response.json()["ai_suggestion"] is None


async def test_create_validates_like_any_input(client: AsyncClient) -> None:
    assert (await client.post("/api/v1/agendas", json={**PAYLOAD, "items": []})).status_code == 422
    bad = {**PAYLOAD, "items": [{"topic": "x", "minutes": 9999}]}
    assert (await client.post("/api/v1/agendas", json=bad)).status_code == 422
