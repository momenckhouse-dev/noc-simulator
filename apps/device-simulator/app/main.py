import os
import threading
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Response
from prometheus_client import CONTENT_TYPE_LATEST, CollectorRegistry, generate_latest
from pydantic import BaseModel, Field

from .metrics import NetworkMetrics
from .simulator import FAULTS, Network

TICK_SECONDS = float(os.getenv("TICK_SECONDS", "5"))

network = Network(
    random_fault_chance=float(os.getenv("RANDOM_FAULT_CHANCE", "0")),
    random_fault_seconds=int(os.getenv("RANDOM_FAULT_SECONDS", "180")),
)
registry = CollectorRegistry()
metrics = NetworkMetrics(registry)


def refresh() -> None:
    network.tick()
    metrics.update(network.snapshot())


def _run_ticks(stop: threading.Event) -> None:
    while not stop.wait(TICK_SECONDS):
        refresh()


@asynccontextmanager
async def lifespan(app: FastAPI):
    refresh()
    stop = threading.Event()
    threading.Thread(target=_run_ticks, args=(stop,), daemon=True).start()
    yield
    stop.set()


app = FastAPI(title="Device Simulator", lifespan=lifespan)


class ChaosRequest(BaseModel):
    device: str
    fault: str
    duration_seconds: int | None = Field(default=None, gt=0, le=86400)


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/metrics")
def prometheus_metrics():
    return Response(generate_latest(registry), media_type=CONTENT_TYPE_LATEST)


@app.get("/api/devices")
def list_devices():
    return network.snapshot()


@app.get("/api/faults")
def list_faults():
    return {"faults": list(FAULTS)}


@app.post("/api/chaos", status_code=201)
def inject_fault(req: ChaosRequest):
    try:
        network.inject(req.device, req.fault, req.duration_seconds)
    except KeyError as e:
        raise HTTPException(404, e.args[0])
    except ValueError as e:
        raise HTTPException(400, str(e))
    refresh()
    return {"device": req.device, "fault": req.fault, "duration_seconds": req.duration_seconds}


@app.delete("/api/chaos/{device}")
def clear_faults(device: str):
    try:
        network.clear(device)
    except KeyError as e:
        raise HTTPException(404, e.args[0])
    refresh()
    return {"device": device, "faults": []}
