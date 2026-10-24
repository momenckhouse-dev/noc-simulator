from prometheus_client import CollectorRegistry, Gauge

DEVICE_LABELS = ["device", "type", "site"]
INTERFACE_LABELS = ["device", "interface"]


class NetworkMetrics:
    """Turns the simulator state into Prometheus metrics (served at /metrics)."""

    def __init__(self, registry: CollectorRegistry):
        def gauge(name, help_text, labels):
            return Gauge(name, help_text, labels, registry=registry)

        self.device_up = gauge("device_up", "1 when the device responds, 0 when it is down", DEVICE_LABELS)
        self.cpu = gauge("device_cpu_percent", "CPU usage in percent", DEVICE_LABELS)
        self.memory = gauge("device_memory_percent", "Memory usage in percent", DEVICE_LABELS)
        self.latency = gauge("device_latency_ms", "Round-trip latency to the device in milliseconds", DEVICE_LABELS)
        self.packet_loss = gauge("device_packet_loss_percent", "Packet loss to the device in percent", DEVICE_LABELS)
        self.interface_up = gauge("interface_up", "1 when the interface is up, 0 when it is down", INTERFACE_LABELS)
        self.interface_traffic = gauge("interface_traffic_bps", "Traffic on the interface in bits per second", INTERFACE_LABELS)

    def update(self, devices: list[dict]) -> None:
        for d in devices:
            labels = (d["name"], d["type"], d["site"])
            self.device_up.labels(*labels).set(1 if d["up"] else 0)
            self.cpu.labels(*labels).set(d["cpu_percent"])
            self.memory.labels(*labels).set(d["memory_percent"])
            self.latency.labels(*labels).set(d["latency_ms"])
            self.packet_loss.labels(*labels).set(d["packet_loss_percent"])
            for iface in d["interfaces"]:
                self.interface_up.labels(d["name"], iface["name"]).set(1 if iface["up"] else 0)
                self.interface_traffic.labels(d["name"], iface["name"]).set(iface["traffic_bps"])
