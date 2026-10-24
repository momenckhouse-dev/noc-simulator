"""Turns Alertmanager webhook calls into Alert rows.

Alertmanager re-sends a firing alert every group_interval, so we only create a row
when there is no open (firing) row with the same fingerprint yet.
"""

from datetime import datetime

from sqlalchemy import select
from sqlalchemy.orm import Session

from .models import Alert, utcnow


def parse_time(value: str | None) -> datetime | None:
    # Alertmanager sends nanoseconds and "0001-01-01T00:00:00Z" for "no end time yet".
    if not value or value.startswith("0001-"):
        return None
    value = value.replace("Z", "+00:00")
    if "." in value:
        head, rest = value.split(".", 1)
        digits = len(rest) - len(rest.lstrip("0123456789"))
        value = f"{head}.{rest[:digits][:6]}{rest[digits:]}"
    return datetime.fromisoformat(value)


def process_webhook(db: Session, payload: dict) -> int:
    processed = 0
    for item in payload.get("alerts", []):
        labels = item.get("labels", {})
        annotations = item.get("annotations", {})
        fingerprint = item.get("fingerprint") or labels.get("alertname", "unknown")
        open_alert = db.scalar(select(Alert).where(Alert.fingerprint == fingerprint, Alert.status == "firing"))

        if item.get("status") == "resolved":
            if open_alert:
                open_alert.status = "resolved"
                open_alert.ends_at = parse_time(item.get("endsAt")) or utcnow()
        elif open_alert is None:
            db.add(
                Alert(
                    fingerprint=fingerprint,
                    alertname=labels.get("alertname", "unknown"),
                    device=labels.get("device", ""),
                    severity=labels.get("severity", "minor"),
                    summary=annotations.get("summary", ""),
                    starts_at=parse_time(item.get("startsAt")) or utcnow(),
                )
            )
            db.flush()
        processed += 1
    db.commit()
    return processed
