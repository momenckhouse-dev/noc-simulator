from app.alertmanager import parse_time


def webhook(status="firing", fingerprint="abc123", device="core-rtr-01"):
    return {
        "alerts": [
            {
                "status": status,
                "fingerprint": fingerprint,
                "labels": {"alertname": "DeviceDown", "device": device, "severity": "critical"},
                "annotations": {"summary": f"{device} is DOWN"},
                "startsAt": "2026-10-24T10:00:00.123456789Z",
                "endsAt": "2026-10-24T10:05:00Z" if status == "resolved" else "0001-01-01T00:00:00Z",
            }
        ]
    }


def test_parse_time_handles_alertmanager_formats():
    assert parse_time("0001-01-01T00:00:00Z") is None
    parsed = parse_time("2026-10-24T10:00:00.123456789Z")
    assert parsed.microsecond == 123456 and parsed.utcoffset().total_seconds() == 0


def test_firing_alert_is_stored_once_then_resolved(client):
    client.post("/api/alertmanager", json=webhook())
    client.post("/api/alertmanager", json=webhook())  # Alertmanager repeats firing alerts

    firing = client.get("/api/alerts", params={"status": "firing"}).json()
    assert len(firing) == 1
    assert firing[0]["device"] == "core-rtr-01" and firing[0]["severity"] == "critical"

    client.post("/api/alertmanager", json=webhook(status="resolved"))
    assert client.get("/api/alerts", params={"status": "firing"}).json() == []
    assert client.get("/api/alerts").json()[0]["ends_at"].startswith("2026-10-24T10:05:00")


def test_ack_alert(client):
    client.post("/api/alertmanager", json=webhook())
    alert_id = client.get("/api/alerts").json()[0]["id"]

    acked = client.post(f"/api/alerts/{alert_id}/ack", json={"user": "momen"}).json()
    assert acked["acknowledged_by"] == "momen"
    assert client.get("/api/summary").json()["unacknowledged"] == 0
    assert client.post("/api/alerts/999/ack", json={"user": "momen"}).status_code == 404


def test_incident_lifecycle(client):
    client.post("/api/alertmanager", json=webhook())
    alert_id = client.get("/api/alerts").json()[0]["id"]

    resp = client.post("/api/incidents", json={"title": "Core router down", "severity": "critical", "alert_ids": [alert_id]})
    assert resp.status_code == 201
    incident = resp.json()
    assert [a["id"] for a in incident["alerts"]] == [alert_id]

    noted = client.post(f"/api/incidents/{incident['id']}/notes", json={"author": "momen", "text": "Called ISP"}).json()
    assert noted["notes"][0]["text"] == "Called ISP"

    resolved = client.patch(f"/api/incidents/{incident['id']}", json={"status": "resolved"}).json()
    assert resolved["status"] == "resolved" and resolved["resolved_at"]
    assert client.get("/api/summary").json()["open_incidents"] == 0


def test_validation_and_simulator_unreachable(client, monkeypatch):
    monkeypatch.setattr("app.main.SIMULATOR_URL", "http://127.0.0.1:9")
    assert client.post("/api/incidents", json={"title": "x", "severity": "huge"}).status_code == 422
    assert client.get("/api/devices").status_code == 502
