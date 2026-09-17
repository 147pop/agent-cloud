#!/usr/bin/env python3
import json
import os
import pathlib
import subprocess
import tempfile
import time
import uuid


NAMESPACE = "cloud-minecraft-paper"
DEPLOYMENT = os.environ.get("CLOUD_VERIFY_DEPLOYMENT", "paper-e0-oracle")
SELECTOR = os.environ.get("CLOUD_VERIFY_SELECTOR", f"app={DEPLOYMENT}")


def kubectl(*args, timeout=30):
    return subprocess.check_output(
        ["k3s", "kubectl", "-n", NAMESPACE, *args], text=True, timeout=timeout
    )


def pod():
    pods = json.loads(kubectl("get", "pods", "-l", SELECTOR, "-o", "json"))["items"]
    assert len(pods) == 1, "expected exactly one Paper Pod"
    return pods[0]


def console(name, command, expected):
    kubectl("exec", name, "--", "gosu", "1000:1000", "mc-send-to-console", command, timeout=10)
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if expected in kubectl("logs", name, "--tail=100"):
            return
        time.sleep(0.5)
    raise AssertionError("Minecraft did not confirm the console command")


def verify():
    deployment = json.loads(kubectl("get", "deployment", DEPLOYMENT, "-o", "json"))
    assert deployment["spec"]["replicas"] == 1, "Paper must already be running"
    spec = deployment["spec"]["template"]["spec"]
    grace = spec["terminationGracePeriodSeconds"]
    assert grace == 120
    limits = spec["containers"][0]["resources"]["limits"]
    assert limits == {"cpu": "2", "memory": "3Gi"}
    original = pod()
    name = original["metadata"]["name"]
    status = kubectl("exec", name, "--", "mc-monitor", "status", "--host", "127.0.0.1", "--port", "25565")
    assert " online=0 " in status, "do not interrupt a server with players or unknown player count"
    marker = str(uuid.uuid4())
    console(name, f'data modify storage cloud:acceptance shutdown set value "{marker}"', "Modified storage cloud:acceptance")
    console(name, "data get storage cloud:acceptance shutdown", marker)
    evidence = pathlib.Path(tempfile.mkdtemp(prefix="paper-shutdown-"))
    path = f"/api/v1/namespaces/{NAMESPACE}/pods?watch=1&resourceVersion={original['metadata']['resourceVersion']}&fieldSelector=metadata.name%3D{name}&timeoutSeconds={grace + 20}"
    with (evidence / "watch.jsonl").open("w") as watch_output, (evidence / "shutdown.log").open("w") as log_output:
        watch = subprocess.Popen(["k3s", "kubectl", "get", "--raw", path], stdout=watch_output, stderr=subprocess.DEVNULL)
        logs = subprocess.Popen(["k3s", "kubectl", "logs", "-n", NAMESPACE, name, "--follow", "--tail=10"], stdout=log_output, stderr=subprocess.DEVNULL)
        try:
            started = time.monotonic()
            kubectl("scale", f"deployment/{DEPLOYMENT}", "--replicas=0")
            kubectl("wait", "--for=delete", f"pod/{name}", f"--timeout={grace + 10}s", timeout=grace + 20)
            stopped_seconds = time.monotonic() - started
        finally:
            for process in (watch, logs):
                if process.poll() is None:
                    process.terminate()
                process.wait(timeout=10)

    exits = []
    for line in (evidence / "watch.jsonl").read_text().splitlines():
        event = json.loads(line)
        for container in event.get("object", {}).get("status", {}).get("containerStatuses", []):
            terminated = container.get("state", {}).get("terminated")
            if terminated:
                exits.append(terminated["exitCode"])

    started = time.monotonic()
    kubectl("scale", f"deployment/{DEPLOYMENT}", "--replicas=1")
    kubectl("rollout", "status", f"deployment/{DEPLOYMENT}", "--timeout=600s", timeout=620)
    replacement = pod()
    assert replacement["metadata"]["uid"] != original["metadata"]["uid"]
    assert replacement["status"]["containerStatuses"][0]["restartCount"] == 0
    kubectl("exec", replacement["metadata"]["name"], "--", "mc-monitor", "status", "--host", "127.0.0.1", "--port", "25565")
    console(replacement["metadata"]["name"], "data get storage cloud:acceptance shutdown", marker)
    ready_seconds = time.monotonic() - started
    console(replacement["metadata"]["name"], "data remove storage cloud:acceptance shutdown", "Modified storage cloud:acceptance")
    assert exits and set(exits) == {0}, f"missing clean termination evidence; inspect {evidence}"
    assert stopped_seconds < grace, "shutdown exceeded the grace period"
    print(json.dumps({
        "result": "passed", "shutdown_seconds": round(stopped_seconds, 3),
        "restart_seconds": round(ready_seconds, 3), "exit_code": 0,
        "world_marker": "preserved", "limits": limits, "private_evidence": str(evidence)
    }))


if __name__ == "__main__":
    verify()
