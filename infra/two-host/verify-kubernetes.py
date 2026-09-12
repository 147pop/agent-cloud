#!/usr/bin/env python3
import json
import pathlib
import runpy
import subprocess
import tempfile
import time
import uuid
from types import SimpleNamespace

HERE = pathlib.Path(__file__).resolve().parent
paper = SimpleNamespace(**runpy.run_path(str(HERE / "verify-shutdown.py")))
NS = "cloud-minecraft-paper"


def k(*args, timeout=30):
    return subprocess.check_output(["k3s", "kubectl", *args], text=True, timeout=timeout)


def control(action, value, request_id=""):
    return json.loads(subprocess.check_output(
        ["k3s", "kubectl", "exec", "-i", "-n", "cloud-system", "deployment/cloud-control", "--",
         "node", "--input-type=module", "-", action, value, request_id],
        input=(HERE / "verify-kubernetes.mjs").read_text(), text=True, timeout=650
    ))


def pods(server_id):
    return json.loads(k("get", "pods", "-n", NS, "-l", f"cloud.example/server-id={server_id}", "-o", "json"))["items"]


def identities(server_id):
    result = {}
    name = f"paper-{server_id}"
    for kind, resource_name in [("deployment", name), ("service", name), ("pvc", name + "-data")]:
        resource = json.loads(k("get", kind, resource_name, "-n", NS, "-o", "json"))
        result[kind] = resource["metadata"]["uid"]
        if kind == "pvc":
            volume = json.loads(k("get", "pv", resource["spec"]["volumeName"], "-o", "json"))
            assert volume["spec"]["persistentVolumeReclaimPolicy"] == "Retain"
            result["pv"] = volume["metadata"]["uid"]
    return result


def restart_control():
    before = json.loads(k("get", "pods", "-n", "cloud-system", "-l", "app=cloud-control", "-o", "json"))["items"][0]["metadata"]["uid"]
    k("rollout", "restart", "deployment/cloud-control", "-n", "cloud-system")
    k("rollout", "status", "deployment/cloud-control", "-n", "cloud-system", "--timeout=180s", timeout=200)
    after = json.loads(k("get", "pods", "-n", "cloud-system", "-l", "app=cloud-control", "-o", "json"))["items"][0]["metadata"]["uid"]
    assert before != after


def verify():
    original = paper.pod()
    status = paper.kubectl("exec", original["metadata"]["name"], "--", "mc-monitor", "status", "--host", "127.0.0.1", "--port", "25565")
    assert " online=0 " in status, "reference server has players or unknown player count"
    assert not json.loads(k("get", "pods", "-n", NS, "-l", "cloud.example/server-id", "-o", "json"))["items"], "managed slot must be empty"
    evidence = pathlib.Path(tempfile.mkdtemp(prefix="kubernetes-lifecycle-"))
    key = f"tes-69-{uuid.uuid4()}"
    server_id = None
    timings = {}
    try:
        paper.kubectl("scale", "deployment/paper-e0-oracle", "--replicas=0")
        paper.kubectl("wait", "--for=delete", f"pod/{original['metadata']['name']}", "--timeout=140s", timeout=160)
        started = time.monotonic()
        created = control("create", key, key + "-create")
        server_id = created["server_id"]
        (evidence / "fixture.json").write_text(json.dumps(created))
        restart_control()
        assert control("create", key, key + "-create") == created
        ready = control("wait", server_id, "running")
        timings["create_with_control_restart_seconds"] = round(time.monotonic() - started, 3)
        print(json.dumps({"phase": "created", **timings}), flush=True)
        before = identities(server_id)
        pod = pods(server_id)
        assert len(pod) == 1
        pod = pod[0]
        assert pod["spec"]["nodeName"] == "game-1"
        assert pod["spec"]["automountServiceAccountToken"] is False
        control("retry", server_id)
        assert identities(server_id) == before
        paper.console(pod["metadata"]["name"], f'data modify storage cloud:acceptance kubernetes set value "{key}"', "Modified storage cloud:acceptance")
        restart_control()
        assert control("wait", server_id, "running") == ready
        assert identities(server_id) == before
        assert pods(server_id)[0]["metadata"]["uid"] == pod["metadata"]["uid"]
        path = f"/api/v1/namespaces/{NS}/pods?watch=1&resourceVersion={pod['metadata']['resourceVersion']}&fieldSelector=metadata.name%3D{pod['metadata']['name']}&timeoutSeconds=150"
        with (evidence / "stop-watch.jsonl").open("w") as output:
            watch = subprocess.Popen(["k3s", "kubectl", "get", "--raw", path], stdout=output, stderr=subprocess.DEVNULL)
            try:
                started = time.monotonic()
                control("stop", server_id, key + "-stop")
                control("wait", server_id, "stopped")
                timings["stop_seconds"] = round(time.monotonic() - started, 3)
            finally:
                watch.terminate()
                watch.wait(timeout=10)
        assert pods(server_id) == []
        exits = []
        for line in (evidence / "stop-watch.jsonl").read_text().splitlines():
            for container in json.loads(line).get("object", {}).get("status", {}).get("containerStatuses", []):
                if "terminated" in container.get("state", {}):
                    exits.append(container["state"]["terminated"]["exitCode"])
        assert exits and set(exits) == {0}, "clean exit evidence missing"
        assert identities(server_id) == before
        started = time.monotonic()
        control("start", server_id, key + "-start")
        assert control("wait", server_id, "running")["world_identity"] == ready["world_identity"]
        timings["restart_seconds"] = round(time.monotonic() - started, 3)
        replacement = pods(server_id)
        assert len(replacement) == 1
        replacement = replacement[0]
        assert replacement["metadata"]["uid"] != pod["metadata"]["uid"]
        assert replacement["status"]["containerStatuses"][0]["restartCount"] == 0
        paper.console(replacement["metadata"]["name"], "data get storage cloud:acceptance kubernetes", key)
        paper.console(replacement["metadata"]["name"], "data remove storage cloud:acceptance kubernetes", "Modified storage cloud:acceptance")
        assert identities(server_id) == before
        result = {"result": "passed", "world_marker": "preserved", "resource_uids": "unchanged", "control_restarts": 2,
                  "exit_code": 0, **timings, "private_evidence": str(evidence)}
    finally:
        if server_id is not None:
            control("stop", server_id, key + "-cleanup")
            control("wait", server_id, "stopped")
            assert pods(server_id) == []
        paper.kubectl("scale", "deployment/paper-e0-oracle", "--replicas=1")
        paper.kubectl("rollout", "status", "deployment/paper-e0-oracle", "--timeout=600s", timeout=620)
    (evidence / "result.json").write_text(json.dumps(result))
    print(json.dumps(result), flush=True)


if __name__ == "__main__":
    verify()
