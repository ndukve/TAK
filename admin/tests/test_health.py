import builtins

import pytest

from api import health as health_module


@pytest.fixture
def broken_open(monkeypatch):
    def _raise(*args, **kwargs):
        raise OSError("simulated /proc read failure")
    monkeypatch.setattr(builtins, "open", _raise)


def test_get_cpu_percent_returns_none_on_proc_read_failure(broken_open):
    assert health_module._get_cpu_percent() is None


def test_get_memory_returns_none_pair_on_proc_read_failure(broken_open):
    assert health_module._get_memory() == (None, None)


def test_get_uptime_seconds_returns_none_on_proc_read_failure(broken_open):
    assert health_module._get_uptime_seconds() is None


def test_get_load_avg_returns_none_on_proc_read_failure(broken_open):
    assert health_module._get_load_avg() is None


async def test_health_endpoint_survives_proc_read_failure(superadmin_client, broken_open):
    resp = await superadmin_client.get("/api/health")
    assert resp.status_code == 200
    system = resp.json()["system"]
    assert system["cpu_percent"] is None
    assert system["mem_used_mb"] is None
    assert system["uptime_seconds"] is None
    assert system["load_avg"] is None
