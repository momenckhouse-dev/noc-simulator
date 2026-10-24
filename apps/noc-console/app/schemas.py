from datetime import datetime, timezone
from typing import Annotated, Literal

from pydantic import AfterValidator, BaseModel, ConfigDict, Field

# SQLite forgets the timezone; treat stored times as UTC so the browser shows the right local time.
UTCDateTime = Annotated[datetime, AfterValidator(lambda v: v if v.tzinfo else v.replace(tzinfo=timezone.utc))]

Severity = Literal["critical", "major", "minor"]
IncidentStatus = Literal["open", "investigating", "resolved"]


class AlertOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    fingerprint: str
    alertname: str
    device: str
    severity: str
    summary: str
    status: str
    starts_at: UTCDateTime
    ends_at: UTCDateTime | None
    acknowledged_by: str | None
    acknowledged_at: UTCDateTime | None
    incident_id: int | None


class NoteOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    author: str
    text: str
    created_at: UTCDateTime


class IncidentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    title: str
    severity: str
    status: str
    created_at: UTCDateTime
    resolved_at: UTCDateTime | None
    alerts: list[AlertOut]
    notes: list[NoteOut]


class AckIn(BaseModel):
    user: str = Field(min_length=1, max_length=100)


class IncidentIn(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    severity: Severity
    alert_ids: list[int] = []


class IncidentUpdate(BaseModel):
    status: IncidentStatus


class NoteIn(BaseModel):
    author: str = Field(min_length=1, max_length=100)
    text: str = Field(min_length=1, max_length=5000)


class ChaosIn(BaseModel):
    device: str
    fault: str
    duration_seconds: int | None = Field(default=None, gt=0, le=86400)
