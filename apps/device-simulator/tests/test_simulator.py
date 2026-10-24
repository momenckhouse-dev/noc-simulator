import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.simulator import Network


def test_down_fault_takes_device_and_interfaces_down():
    net = Network()
    net.inject("core-rtr-01", "down")
    net.tick()
    rtr = net.devices["core-rtr-01"]
    assert rtr.up is False
    assert rtr.packet_loss_percent == 100
    assert not any(i.up for i in rtr.interfaces)
    assert net.devices["core-rtr-02"].up is True


def test_interface_down_hits_only_the_uplink():
    net = Network()
    net.inject("dist-sw-01", "interface_down")
    net.tick()
    ifaces = net.devices["dist-sw-01"].interfaces
    assert ifaces[0].up is False
    assert all(i.up for i in ifaces[1:])


def test_timed_fault_expires():
    net = Network()
    net.inject("edge-fw-01", "high_cpu", duration_seconds=60)
    net.tick()
    assert net.devices["edge-fw-01"].cpu_percent > 90
    net.tick(now=net.devices["edge-fw-01"].faults["high_cpu"] + 1)
    assert net.devices["edge-fw-01"].faults == {}
    assert net.devices["edge-fw-01"].cpu_percent <= 60


def test_unknown_device_and_fault_are_rejected():
    net = Network()
    with pytest.raises(KeyError):
        net.inject("nope", "down")
    with pytest.raises(ValueError):
        net.inject("core-rtr-01", "explode")


def test_api_metrics_and_chaos():
    with TestClient(app) as client:
        assert "device_up" in client.get("/metrics").text

        assert client.post("/api/chaos", json={"device": "web-srv-01", "fault": "down"}).status_code == 201
        assert 'device_up{device="web-srv-01",site="dc-west",type="server"} 0.0' in client.get("/metrics").text

        assert client.delete("/api/chaos/web-srv-01").status_code == 200
        assert client.post("/api/chaos", json={"device": "nope", "fault": "down"}).status_code == 404
        assert client.post("/api/chaos", json={"device": "web-srv-01", "fault": "explode"}).status_code == 400
