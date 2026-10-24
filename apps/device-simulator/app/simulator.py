"""A fake network: routers, switches, a firewall and a server that report health numbers.

Every "tick" the numbers drift a little, like real devices. A trainer (or the random
fault mode) can inject faults so the NOC has something to troubleshoot.
"""

import random
import threading
import time
from dataclasses import dataclass, field

FAULTS = ("down", "high_cpu", "interface_down", "high_latency", "packet_loss")

INVENTORY = [
    {"name": "core-rtr-01", "type": "router", "site": "dc-east", "interfaces": ["Gi0/0", "Gi0/1", "Gi0/2"]},
    {"name": "core-rtr-02", "type": "router", "site": "dc-west", "interfaces": ["Gi0/0", "Gi0/1", "Gi0/2"]},
    {"name": "dist-sw-01", "type": "switch", "site": "dc-east", "interfaces": ["Te1/0/1", "Te1/0/2", "Gi1/0/1", "Gi1/0/2"]},
    {"name": "dist-sw-02", "type": "switch", "site": "dc-west", "interfaces": ["Te1/0/1", "Te1/0/2", "Gi1/0/1", "Gi1/0/2"]},
    {"name": "edge-fw-01", "type": "firewall", "site": "dc-east", "interfaces": ["outside", "inside", "dmz"]},
    {"name": "web-srv-01", "type": "server", "site": "dc-west", "interfaces": ["eth0"]},
]


@dataclass
class Interface:
    name: str
    up: bool = True
    traffic_bps: float = 0.0


@dataclass
class Device:
    name: str
    type: str
    site: str
    interfaces: list[Interface]
    up: bool = True
    cpu_percent: float = 20.0
    memory_percent: float = 45.0
    latency_ms: float = 3.0
    packet_loss_percent: float = 0.0
    # fault name -> unix time when it clears by itself (None = stays until cleared by hand)
    faults: dict[str, float | None] = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "type": self.type,
            "site": self.site,
            "up": self.up,
            "cpu_percent": round(self.cpu_percent, 1),
            "memory_percent": round(self.memory_percent, 1),
            "latency_ms": round(self.latency_ms, 1),
            "packet_loss_percent": round(self.packet_loss_percent, 2),
            "interfaces": [
                {"name": i.name, "up": i.up, "traffic_bps": round(i.traffic_bps)} for i in self.interfaces
            ],
            "faults": sorted(self.faults),
        }


def _drift(value: float, low: float, high: float, step: float) -> float:
    return min(high, max(low, value + random.uniform(-step, step)))


class Network:
    def __init__(self, inventory=INVENTORY, random_fault_chance: float = 0.0, random_fault_seconds: int = 180):
        self.devices = {
            d["name"]: Device(
                name=d["name"],
                type=d["type"],
                site=d["site"],
                interfaces=[Interface(name) for name in d["interfaces"]],
            )
            for d in inventory
        }
        self.random_fault_chance = random_fault_chance
        self.random_fault_seconds = random_fault_seconds
        self._lock = threading.Lock()

    def _get(self, name: str) -> Device:
        try:
            return self.devices[name]
        except KeyError:
            raise KeyError(f"unknown device '{name}'") from None

    def inject(self, device_name: str, fault: str, duration_seconds: int | None = None) -> None:
        if fault not in FAULTS:
            raise ValueError(f"unknown fault '{fault}', choose one of: {', '.join(FAULTS)}")
        with self._lock:
            device = self._get(device_name)
            device.faults[fault] = time.time() + duration_seconds if duration_seconds else None

    def clear(self, device_name: str) -> None:
        with self._lock:
            self._get(device_name).faults.clear()

    def snapshot(self) -> list[dict]:
        with self._lock:
            return [d.to_dict() for d in self.devices.values()]

    def tick(self, now: float | None = None) -> None:
        now = now if now is not None else time.time()
        with self._lock:
            self._maybe_random_fault(now)
            for device in self.devices.values():
                device.faults = {f: t for f, t in device.faults.items() if t is None or t > now}
                self._update(device)

    def _maybe_random_fault(self, now: float) -> None:
        if random.random() >= self.random_fault_chance:
            return
        device = random.choice(list(self.devices.values()))
        if not device.faults:
            device.faults[random.choice(FAULTS)] = now + self.random_fault_seconds

    @staticmethod
    def _update(device: Device) -> None:
        faults = device.faults
        if "down" in faults:
            device.up = False
            device.cpu_percent = device.memory_percent = device.latency_ms = 0.0
            device.packet_loss_percent = 100.0
            for iface in device.interfaces:
                iface.up = False
                iface.traffic_bps = 0.0
            return

        device.up = True
        device.cpu_percent = random.uniform(92, 99) if "high_cpu" in faults else _drift(device.cpu_percent, 5, 60, 4)
        device.memory_percent = _drift(device.memory_percent, 30, 75, 2)
        device.latency_ms = (
            random.uniform(250, 400) if "high_latency" in faults else _drift(device.latency_ms, 1, 15, 1.5)
        )
        device.packet_loss_percent = (
            random.uniform(10, 25) if "packet_loss" in faults else _drift(device.packet_loss_percent, 0, 0.5, 0.1)
        )
        for index, iface in enumerate(device.interfaces):
            # interface_down always hits the first interface: the uplink
            iface.up = not (index == 0 and "interface_down" in faults)
            iface.traffic_bps = _drift(iface.traffic_bps or 200e6, 10e6, 900e6, 50e6) if iface.up else 0.0
