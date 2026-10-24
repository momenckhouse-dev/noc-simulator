import json
import logging
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import Depends, FastAPI, HTTPException, Response
from fastapi.responses import FileResponse
from prometheus_client import CONTENT_TYPE_LATEST, CollectorRegistry, Counter, generate_latest
from sqlalchemy import func, select, text
from sqlalchemy.exc import DBAPIError
from sqlalchemy.orm import Session, selectinload

from .alertmanager import process_webhook
from .db import Base, engine, get_db
from .models import Alert, Incident, IncidentNote, utcnow
from .schemas import AckIn, AlertOut, ChaosIn, IncidentIn, IncidentOut, IncidentUpdate, NoteIn

SIMULATOR_URL = os.getenv("SIMULATOR_URL", "http://localhost:8001")
STATIC_DIR = Path(__file__).parent / "static"

log = logging.getLogger("noc-console")
registry = CollectorRegistry()
webhooks_received = Counter("noc_webhooks_received_total", "Alertmanager webhook calls received", registry=registry)


def wait_for_database(attempts: int = 30, delay: float = 2.0) -> None:
    # In Docker/Kubernetes the database may start after us, so retry instead of crashing.
    # Two replicas starting together can also race on CREATE TABLE; the retry covers that too.
    for attempt in range(1, attempts + 1):
        try:
            Base.metadata.create_all(engine)
            return
        except DBAPIError:
            if attempt == attempts:
                raise
            log.warning("database not ready (attempt %d/%d), retrying in %.0fs", attempt, attempts, delay)
            time.sleep(delay)


@asynccontextmanager
async def lifespan(app: FastAPI):
    wait_for_database()
    yield


app = FastAPI(title="NOC Console", lifespan=lifespan)


def _get_alert(db: Session, alert_id: int) -> Alert:
    alert = db.get(Alert, alert_id)
    if alert is None:
        raise HTTPException(404, "alert not found")
    return alert


def _incident_query():
    return select(Incident).options(selectinload(Incident.alerts), selectinload(Incident.notes))


def _get_incident(db: Session, incident_id: int) -> Incident:
    incident = db.scalar(_incident_query().where(Incident.id == incident_id))
    if incident is None:
        raise HTTPException(404, "incident not found")
    return incident


def _call_simulator(method: str, path: str, body: dict | None = None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        SIMULATOR_URL + path, data=data, method=method, headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return json.loads(resp.read() or b"null")
    except urllib.error.HTTPError as e:
        try:
            detail = json.loads(e.read()).get("detail", e.reason)
        except ValueError:
            detail = e.reason
        raise HTTPException(e.code, detail)
    except (urllib.error.URLError, TimeoutError):
        raise HTTPException(502, "device simulator is unreachable")


# ---- health & metrics ----------------------------------------------------

@app.get("/", include_in_schema=False)
def index():
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/readyz")
def readyz(db: Session = Depends(get_db)):
    db.execute(text("SELECT 1"))
    return {"status": "ready"}


@app.get("/metrics", include_in_schema=False)
def prometheus_metrics():
    return Response(generate_latest(registry), media_type=CONTENT_TYPE_LATEST)


# ---- alerts --------------------------------------------------------------

@app.post("/api/alertmanager")
def alertmanager_webhook(payload: dict, db: Session = Depends(get_db)):
    webhooks_received.inc()
    return {"processed": process_webhook(db, payload)}


@app.get("/api/alerts", response_model=list[AlertOut])
def list_alerts(status: str | None = None, db: Session = Depends(get_db)):
    query = select(Alert).order_by(Alert.starts_at.desc()).limit(200)
    if status:
        query = query.where(Alert.status == status)
    return db.scalars(query).all()


@app.post("/api/alerts/{alert_id}/ack", response_model=AlertOut)
def acknowledge_alert(alert_id: int, body: AckIn, db: Session = Depends(get_db)):
    alert = _get_alert(db, alert_id)
    if not alert.acknowledged_by:
        alert.acknowledged_by = body.user
        alert.acknowledged_at = utcnow()
        db.commit()
    return alert


# ---- incidents -----------------------------------------------------------

@app.get("/api/incidents", response_model=list[IncidentOut])
def list_incidents(db: Session = Depends(get_db)):
    return db.scalars(_incident_query().order_by(Incident.created_at.desc()).limit(100)).all()


@app.post("/api/incidents", response_model=IncidentOut, status_code=201)
def create_incident(body: IncidentIn, db: Session = Depends(get_db)):
    alerts = [_get_alert(db, alert_id) for alert_id in body.alert_ids]
    incident = Incident(title=body.title, severity=body.severity, alerts=alerts, notes=[])
    db.add(incident)
    db.commit()
    return incident


@app.patch("/api/incidents/{incident_id}", response_model=IncidentOut)
def update_incident(incident_id: int, body: IncidentUpdate, db: Session = Depends(get_db)):
    incident = _get_incident(db, incident_id)
    incident.status = body.status
    incident.resolved_at = utcnow() if body.status == "resolved" else None
    db.commit()
    return incident


@app.post("/api/incidents/{incident_id}/notes", response_model=IncidentOut, status_code=201)
def add_note(incident_id: int, body: NoteIn, db: Session = Depends(get_db)):
    incident = _get_incident(db, incident_id)
    incident.notes.append(IncidentNote(author=body.author, text=body.text))
    db.commit()
    return incident


@app.get("/api/summary")
def summary(db: Session = Depends(get_db)):
    firing = db.scalars(select(Alert).where(Alert.status == "firing")).all()
    open_incidents = db.scalar(select(func.count()).select_from(Incident).where(Incident.status != "resolved"))
    return {
        "firing": len(firing),
        "unacknowledged": sum(1 for a in firing if not a.acknowledged_by),
        "by_severity": {s: sum(1 for a in firing if a.severity == s) for s in ("critical", "major", "minor")},
        "open_incidents": open_incidents,
    }


# ---- devices & lab control (proxied to the device simulator) -------------

@app.get("/api/devices")
def list_devices():
    return _call_simulator("GET", "/api/devices")


@app.post("/api/lab/chaos", status_code=201)
def inject_fault(body: ChaosIn):
    return _call_simulator("POST", "/api/chaos", body.model_dump())


@app.delete("/api/lab/chaos/{device}")
def clear_faults(device: str):
    return _call_simulator("DELETE", f"/api/chaos/{urllib.parse.quote(device, safe='')}")
