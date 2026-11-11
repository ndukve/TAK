import pytest
from fastapi import HTTPException

from api import groups as groups_module

SAMPLE = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<UserAuthenticationFile xmlns="http://bbn.com/marti/xml/bindings">
    <User identifier="efdi-gateway-Service" fingerprint="AA:BB" passwordHashed="false"><groupList>TAK-USERS</groupList></User>
    <User identifier="alpha1-ATAK" fingerprint="CC:DD" passwordHashed="false"><groupList>TAK-USERS Alpha</groupList></User>
    <User identifier="old-WinTAK" fingerprint="EE:FF" passwordHashed="false"><groupList>revoked</groupList></User>
</UserAuthenticationFile>"""


def test_parse_user_file_reads_users_and_groups_only():
    users = groups_module.parse_user_file(SAMPLE)
    assert users[1] == {"username": "alpha1-ATAK", "groups": ["TAK-USERS", "Alpha"]}
    assert "fingerprint" not in str(users)


def test_by_group_lists_members_per_group():
    result = groups_module.by_group(groups_module.parse_user_file(SAMPLE))
    assert {g["name"]: g["members"] for g in result} == {
        "Alpha": ["alpha1-ATAK"], "TAK-USERS": ["alpha1-ATAK", "efdi-gateway-Service"], "revoked": ["old-WinTAK"]}


def test_a_dtd_or_entity_in_the_user_file_is_refused():
    with pytest.raises(ValueError):
        groups_module.parse_user_file('<!DOCTYPE x [<!ENTITY a "b">]><UserAuthenticationFile/>')


def test_build_args_maps_directions_and_modes():
    req = groups_module.AssignRequest(username="alpha1-ATAK", mode="add", both=["Alpha"], send=["Medics"], receive=["Logistics"])
    assert groups_module.build_args(req) == ["-a", "-g", "Alpha", "-ig", "Medics", "-og", "Logistics"]
    assert groups_module.build_args(groups_module.AssignRequest(username="alpha1-ATAK", mode="remove", both=["Alpha"])) == ["-r", "-g", "Alpha"]
    assert groups_module.build_args(groups_module.AssignRequest(username="alpha1-ATAK", both=["A", "B"])) == ["-g", "A", "-g", "B"]


@pytest.mark.parametrize("req,status", [
    (dict(username="alpha1-ATAK"), 400),                                           # no group named
    (dict(username="alpha1-ATAK", both=["bad name"]), 400),
    (dict(username="alpha1-ATAK", both=["x; rm -rf /"]), 400),
    (dict(username="alpha1-ATAK", both=["revoked"]), 400),                          # that bucket is for disabling
    (dict(username="efdi-gateway-Service", mode="set", both=["Alpha"]), 409),      # service accounts: add only
    (dict(username="efdi-gateway-Service", mode="remove", both=["TAK-USERS"]), 409),
    (dict(username="bad user", both=["Alpha"]), 400),
])
def test_build_args_refuses_what_it_must(req, status):
    with pytest.raises(HTTPException) as err:
        groups_module.build_args(groups_module.AssignRequest(**req))
    assert err.value.status_code == status


def test_a_service_account_may_gain_a_group():
    assert groups_module.build_args(groups_module.AssignRequest(username="efdi-gateway-Service", mode="add", send=["Alpha"])) == ["-a", "-ig", "Alpha"]


@pytest.fixture
def container(monkeypatch):
    state = {"code": 0, "out": "", "calls": []}

    async def fake(cmd, env=None, workdir=None):
        state["calls"].append(cmd)
        return state["code"], state["out"]

    monkeypatch.setattr(groups_module, "run_in_container", fake)
    return state


async def test_list_groups_endpoint(admin_client, container):
    container["out"] = SAMPLE
    body = (await admin_client.get("/api/groups")).json()
    assert [g["name"] for g in body["groups"]] == ["Alpha", "TAK-USERS", "revoked"]
    assert body["default_group"] == "TAK-USERS"


async def test_assign_needs_superadmin(admin_client, container):
    resp = await admin_client.post("/api/groups/assign", json={"username": "alpha1-ATAK", "both": ["Alpha"]})
    assert resp.status_code == 403 and container["calls"] == []


async def test_assign_runs_certmod_with_values_as_arguments(superadmin_client, container, monkeypatch):
    monkeypatch.setattr(groups_module.os.path, "isfile", lambda p: True)
    resp = await superadmin_client.post("/api/groups/assign", json={"username": "alpha1-ATAK", "mode": "add", "both": ["Alpha"], "receive": ["Logistics"]})
    assert resp.status_code == 200
    cmd = container["calls"][0]
    assert cmd[:2] == ["bash", "-c"] and "Alpha" not in cmd[2]                      # values never inside the shell text
    assert cmd[3:] == ["_", "-a", "-g", "Alpha", "-og", "Logistics", "/opt/tak/data/certs/files/alpha1-ATAK.pem"]


async def test_assign_unknown_certificate_is_404(superadmin_client, container, monkeypatch):
    monkeypatch.setattr(groups_module.os.path, "isfile", lambda p: False)
    resp = await superadmin_client.post("/api/groups/assign", json={"username": "ghost-ATAK", "both": ["Alpha"]})
    assert resp.status_code == 404 and container["calls"] == []
