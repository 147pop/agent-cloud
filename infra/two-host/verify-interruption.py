#!/usr/bin/env python3
import importlib.util
from datetime import datetime
import json
import pathlib
import subprocess
import tempfile
import time
import uuid

module = importlib.util.spec_from_file_location("shutdown", "infra/two-host/verify-shutdown.py")
shutdown = importlib.util.module_from_spec(module)
module.loader.exec_module(shutdown)
kubectl, console = shutdown.kubectl, shutdown.console

original_list = json.loads(kubectl("get", "pods", "-l", "app=paper-e0-oracle", "-o", "json"))
assert len(original_list["items"]) == 1
original = original_list["items"][0]
name = original["metadata"]["name"]
status = kubectl("exec", name, "--", "mc-monitor", "status", "--host", "127.0.0.1", "--port", "25565")
assert " online=0 " in status
pid = kubectl("exec", name, "--", "pgrep", "-x", "java").strip()
assert pid.isdecimal()
marker = str(uuid.uuid4())
console(name, f'data modify storage cloud:acceptance interruption set value "{marker}"', "Modified storage cloud:acceptance")
console(name, "data get storage cloud:acceptance interruption", marker)
evidence = pathlib.Path(tempfile.mkdtemp(prefix="paper-interruption-"))
watch_path = f"/api/v1/namespaces/cloud-minecraft-paper/pods?watch=1&resourceVersion={original_list['metadata']['resourceVersion']}&labelSelector=app%3Dpaper-e0-oracle&timeoutSeconds=140"

with (evidence / "watch.jsonl").open("w") as output:
    watch = subprocess.Popen(["k3s", "kubectl", "get", "--raw", watch_path], stdout=output, stderr=subprocess.DEVNULL)
    try:
        # Resume automatically if this operator process loses its connection.
        kubectl("exec", name, "--", "sh", "-c", f"(sleep 45; kill -CONT {pid}) </dev/null >/dev/null 2>&1 & kill -STOP {pid}")
        try:
            started = time.monotonic()
            kubectl("delete", "pod", name, "--wait=false")
            observed = 0
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                pods = json.loads(kubectl("get", "pods", "-l", "app=paper-e0-oracle", "-o", "json"))["items"]
                old = next(item for item in pods if item["metadata"]["uid"] == original["metadata"]["uid"])
                assert old["metadata"].get("deletionTimestamp")
                assert old["status"]["containerStatuses"][0]["state"].get("running")
                process_state = kubectl("exec", name, "--", "ps", "-o", "stat=", "-p", pid).strip()
                assert process_state.startswith("T"), "old Java process must remain paused and alive"
                for replacement in (item for item in pods if item["metadata"]["uid"] != original["metadata"]["uid"]):
                    assert replacement["status"]["phase"] == "Pending"
                    assert not replacement["status"].get("containerStatuses"), "replacement container started while old writer was alive"
                    if any(condition["type"] == "PodScheduled" and condition["status"] == "False" and
                           condition["reason"] == "Unschedulable" for condition in replacement["status"].get("conditions", [])):
                        observed += 1
                        (evidence / "blocked-replacement.json").write_text(json.dumps(replacement))
                time.sleep(1)
            assert observed >= 3, "replacement was not observed blocked repeatedly"
        finally:
            kubectl("exec", name, "--", "kill", "-CONT", pid)
        kubectl("wait", "--for=delete", f"pod/{name}", "--timeout=130s", timeout=140)
        stopped_seconds = time.monotonic() - started
        kubectl("rollout", "status", "deployment/paper-e0-oracle", "--timeout=600s", timeout=620)
    finally:
        if watch.poll() is None:
            watch.terminate()
        watch.wait(timeout=10)

replacement = shutdown.pod()
assert replacement["metadata"]["uid"] != original["metadata"]["uid"]
assert replacement["status"]["containerStatuses"][0]["restartCount"] == 0
console(replacement["metadata"]["name"], "data get storage cloud:acceptance interruption", marker)
console(replacement["metadata"]["name"], "data remove storage cloud:acceptance interruption", "Modified storage cloud:acceptance")
exits = []
finished_at = None
for line in (evidence / "watch.jsonl").read_text().splitlines():
    event = json.loads(line).get("object", {})
    if event.get("metadata", {}).get("uid") == original["metadata"]["uid"]:
        for container in event.get("status", {}).get("containerStatuses", []):
            terminated = container.get("state", {}).get("terminated")
            if terminated:
                exits.append(terminated["exitCode"])
                finished_at = terminated["finishedAt"]
assert exits and set(exits) == {0}
assert finished_at is not None
started_at = replacement["status"]["containerStatuses"][0]["state"]["running"]["startedAt"]
assert datetime.fromisoformat(started_at) > datetime.fromisoformat(finished_at), "replacement must start after the old container exits"
assert stopped_seconds < 120
print(json.dumps({"result": "passed", "shutdown_seconds_including_pause": round(stopped_seconds, 3),
    "blocked_replacement_observations": observed, "old_java_alive": True,
    "replacement_started_before_old_exit": False, "exit_code": 0,
    "world_marker": "preserved", "replacement_restarts": 0, "private_evidence": str(evidence)}))
