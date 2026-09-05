#!/usr/bin/env python3
"""Run the E0 scenarios on the authorized Contabo host, preserving the E0 recipe."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import shutil
import subprocess
import threading
import time
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parent
SERVER = 'cloud-mc-benchmark-e0'
PLAYERS = 'cloud-mc-benchmark-players'
ORIGINAL = 'cloud-mc-paper-e0'
PROTECTED = ['co-tenant-app', 'co-tenant-db']
NODE = 'node@sha256:b506e7321f176aae77317f99d67a24b272c1f09f1d10f1761f2773447d8da26c'


def command(*args, timeout=120, check=True, env=None):
    result = subprocess.run(args, capture_output=True, text=True, timeout=timeout, env=env, cwd=ROOT)
    if check and result.returncode:
        raise RuntimeError(f'{args}: {result.stderr or result.stdout}')
    return result


def state(name):
    data = json.loads(command('docker', 'inspect', name).stdout)[0]
    return {'id': data['Id'], 'started_at': data['State']['StartedAt'],
            'running': data['State']['Running'], 'restarts': data['RestartCount'],
            'health': data['State'].get('Health', {}).get('Status'), 'pid': data['State']['Pid']}


def rcon(text):
    return command('docker', 'exec', SERVER, 'rcon-cli', text, timeout=45).stdout.strip()


def app_probe():
    start = time.monotonic()
    with urllib.request.urlopen('http://127.0.0.1:3000/', timeout=2) as response:
        assert response.status == 200
        response.read(1024)
    elapsed = time.monotonic() - start
    assert elapsed < 1, f'Protected app took {elapsed:.3f}s'
    return elapsed


def world_bytes(data):
    directories = [str(path) for path in data.glob('world*') if path.is_dir()]
    return sum(int(line.split()[0]) for line in command('du', '-sb', *directories).stdout.splitlines()) if directories else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('label')
    parser.add_argument('--players', nargs='+', type=int, default=[1, 2, 4, 8])
    parser.add_argument('--seconds', type=int, default=60)
    parser.add_argument('--repeats', type=int, default=2)
    args = parser.parse_args()
    assert re.fullmatch(r'[a-z0-9-]+', args.label)
    assert args.players and all(value in (1, 2, 4, 8) for value in args.players)
    assert 10 <= args.seconds <= 300 and 1 <= args.repeats <= 3
    assert os.geteuid() == 0, 'Run through the authorized sudo session'
    assert shutil.disk_usage(ROOT).free > 20 * 1024**3
    assert (ROOT / '.env').is_file()
    def interrupted(signum, frame):
        raise RuntimeError(f'Interrupted by signal {signum}')
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    output = ROOT / 'evidence' / args.label
    output.mkdir(parents=True, exist_ok=False)
    original = state(ORIGINAL)
    assert original['running'], 'Expected the original E0 container to be running'
    status = command('docker', 'exec', ORIGINAL, 'mc-monitor', 'status', '--host', '127.0.0.1', '--port', '25565').stdout
    assert re.search(r'\bonline=0\b', status), 'Do not interrupt real players'
    protected = {name: state(name) for name in PROTECTED}
    result = {'label': args.label, 'started_at': time.time(), 'parameters': vars(args),
              'host': os.uname().nodename, 'original_before': original,
              'protected_before': protected, 'cases': [], 'app_baseline_seconds': [app_probe() for _ in range(5)],
              'source_sha256': {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
                                for name in ['run.py', 'players.js', 'compose.yml', 'package-lock.json']}}
    abort = threading.Event()
    finished = threading.Event()
    current = {'stage': 'baseline', 'case': None}
    failures = []

    def sample():
        with (output / 'metrics.jsonl').open('w', buffering=1) as stream:
            while not finished.is_set():
                record = {'time': time.time(), **current.copy()}
                try:
                    record['app_seconds'] = app_probe()
                    memory = dict(line.split(':', 1) for line in Path('/proc/meminfo').read_text().splitlines())
                    record['available_bytes'] = int(memory['MemAvailable'].split()[0]) * 1024
                    assert record['available_bytes'] > 1024**3, 'Less than 1 GiB available on the shared host'
                    assert shutil.disk_usage(ROOT).free > 20 * 1024**3, 'Less than 20 GiB free disk'
                    record['pressure_io'] = Path('/proc/pressure/io').read_text().strip()
                    record['pressure_memory'] = Path('/proc/pressure/memory').read_text().strip()
                    found = command('docker', 'inspect', SERVER, check=False)
                    if found.returncode == 0:
                        container = json.loads(found.stdout)[0]
                        record['oom_killed'] = container['State']['OOMKilled']
                        assert not record['oom_killed'], 'Benchmark container was OOM killed'
                        pid = container['State']['Pid']
                        if pid:
                            group = Path('/sys/fs/cgroup') / Path(f'/proc/{pid}/cgroup').read_text().strip().split('::')[1].lstrip('/')
                            record['memory_bytes'] = int((group / 'memory.current').read_text())
                            record['cpu_stat'] = dict(line.split() for line in (group / 'cpu.stat').read_text().splitlines())
                            record['memory_events'] = (group / 'memory.events').read_text().strip()
                            top = command('docker', 'top', SERVER, '-eo', 'pid,comm', check=False)
                            for line in top.stdout.splitlines()[1:]:
                                parts = line.split()
                                if len(parts) == 2 and parts[1] == 'java':
                                    status_text = Path(f'/proc/{parts[0]}/status').read_text()
                                    record['java_rss_bytes'] = int(re.search(r'VmRSS:\s+(\d+)', status_text).group(1)) * 1024
                            if current['stage'] == 'players':
                                record['tps'] = rcon('tps')
                                record['mspt'] = rcon('mspt')
                                if int(time.time()) // 30 != sample.last_heap:
                                    record['heap'] = command('docker', 'exec', SERVER, 'sh', '-c', 'jattach "$(pidof java)" jcmd GC.heap_info').stdout
                                    sample.last_heap = int(time.time()) // 30
                except (FileNotFoundError, ProcessLookupError) as error:
                    if current['stage'] == 'players':
                        record['error'] = str(error)
                        failures.append(str(error))
                        abort.set()
                except Exception as error:
                    record['error'] = str(error)
                    failures.append(str(error))
                    abort.set()
                stream.write(json.dumps(record) + '\n')
                finished.wait(5)
    sample.last_heap = None

    def guard():
        if abort.is_set():
            raise RuntimeError(f'Benchmark stopped to protect the host: {failures[-1]}')

    def ready(name=SERVER):
        started = time.monotonic()
        while time.monotonic() - started < 240:
            if name == SERVER:
                guard()
            observed = state(name)
            assert observed['running'], f'{name} exited before readiness'
            if observed['health'] == 'healthy':
                try:
                    test = command('docker', 'exec', name, 'mc-monitor', 'status', '--host', '127.0.0.1', '--port', '25565', check=False, timeout=10)
                    if test.returncode == 0:
                        return test.stdout.strip()
                except subprocess.TimeoutExpired:
                    pass
            time.sleep(2)
        raise RuntimeError('Paper did not become ready in 240 seconds')

    worker = threading.Thread(target=sample, daemon=True)
    worker.start()
    try:
        command('docker', 'stop', '-t', '120', ORIGINAL, timeout=150)
        for repeat in range(1, args.repeats + 1):
            for count in args.players:
                guard()
                name = f'r{repeat}-n{count}'
                data = ROOT / 'data' / f'{args.label}-{name}'
                data.mkdir(parents=True, exist_ok=False)
                operators = []
                for number in range(1, 9):
                    username = f'Bench{number:02}'
                    offline_id = uuid.UUID(bytes=hashlib.md5(f'OfflinePlayer:{username}'.encode()).digest(), version=3)
                    operators.append({'uuid': str(offline_id), 'name': username, 'level': 4, 'bypassesPlayerLimit': False})
                (data / 'ops.json').write_text(json.dumps(operators))
                env = {**os.environ, 'BENCH_DATA': str(data)}
                current.update(case=name, stage='cold_start')
                case = {'name': name, 'players': count, 'repeat': repeat, 'started_at': time.time()}
                result['cases'].append(case)
                started = time.monotonic()
                command('docker', 'compose', '-p', 'cloud-e0-benchmark', '-f', 'compose.yml', 'up', '-d', '--force-recreate', env=env, timeout=180)
                case['cold_status'] = ready()
                case['cold_ready_seconds'] = time.monotonic() - started
                tracked = ['paper-26.2-121.jar', 'bukkit.yml', 'spigot.yml', 'config/paper-global.yml', 'config/paper-world-defaults.yml']
                case['recipe_sha256'] = {path: hashlib.sha256((data / path).read_bytes()).hexdigest() for path in tracked}
                if len(result['cases']) > 1:
                    assert case['recipe_sha256'] == result['cases'][0]['recipe_sha256'], 'Downloaded recipe changed between runs'
                properties = dict(line.split('=', 1) for line in (data / 'server.properties').read_text().splitlines() if '=' in line and not line.startswith('#'))
                case['properties'] = {key: properties[key] for key in ['level-seed', 'max-players', 'view-distance', 'simulation-distance', 'online-mode', 'gamemode', 'difficulty', 'allow-flight']}
                case['world_bytes_before'] = world_bytes(data)
                current['stage'] = 'players'
                with (output / f'{name}-players.jsonl').open('w') as stream:
                    player_process = subprocess.Popen(['docker', 'run', '--rm', '--name', PLAYERS,
                        '--network', f'container:{SERVER}', '--cpus', '1', '--memory', '1g', '--memory-swap', '1g',
                        '--pids-limit', '128', '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges',
                        '--read-only', '--tmpfs', '/tmp', '--user', '1001:1001',
                        '-v', f'{ROOT}:/work:ro', '-w', '/work', NODE, 'node', 'players.js', str(count), str(args.seconds)],
                        stdout=stream, stderr=subprocess.STDOUT)
                    deadline = time.monotonic() + args.seconds * 5 + count * 100 + 120
                    try:
                        while player_process.poll() is None:
                            guard()
                            assert time.monotonic() < deadline, 'Player scenario timed out'
                            time.sleep(2)
                        assert player_process.returncode == 0, f'Player scenario failed; see {name}-players.jsonl'
                    finally:
                        command('docker', 'stop', '-t', '5', PLAYERS, check=False, timeout=15)
                        player_process.wait(timeout=15)
                current['stage'] = 'save'
                case['marker_create'] = rcon('setblock 0 201 0 minecraft:diamond_block')
                assert 'Changed the block' in case['marker_create'], 'World marker was not created'
                started = time.monotonic()
                case['save_response'] = rcon('save-all flush')
                case['save_seconds'] = time.monotonic() - started
                assert 'Saved the game' in case['save_response']
                case['world_bytes_after'] = world_bytes(data)
                case['heap_after_players'] = command('docker', 'exec', SERVER, 'sh', '-c', 'jattach "$(pidof java)" jcmd GC.heap_info').stdout
                current['stage'] = 'stop'
                started = time.monotonic()
                command('docker', 'stop', '-t', '120', SERVER, timeout=150)
                case['stop_seconds'] = time.monotonic() - started
                stopped = json.loads(command('docker', 'inspect', SERVER).stdout)[0]['State']
                assert stopped['ExitCode'] == 0 and not stopped['OOMKilled'], stopped
                logs = command('docker', 'logs', SERVER)
                (output / f'{name}-server.log').write_text(logs.stdout + logs.stderr)
                current['stage'] = 'warm_start'
                started = time.monotonic()
                command('docker', 'start', SERVER)
                case['warm_status'] = ready()
                case['warm_ready_seconds'] = time.monotonic() - started
                rcon('forceload add 0 0')
                time.sleep(1)
                case['marker_restore'] = rcon('execute if block 0 201 0 minecraft:diamond_block')
                assert 'Test passed' in case['marker_restore'], 'World marker did not persist'
                current['stage'] = 'stop'
                command('docker', 'stop', '-t', '120', SERVER, timeout=150)
                print(json.dumps(case), flush=True)
                (output / 'summary.json').write_text(json.dumps(result, indent=2) + '\n')
        result['scenarios_complete'] = True
    except Exception as error:
        result['error'] = str(error)
        raise
    finally:
        current['stage'] = 'cleanup'
        finished.set()
        worker.join(timeout=60)
        command('docker', 'stop', '-t', '5', PLAYERS, check=False, timeout=15)
        command('docker', 'stop', '-t', '120', SERVER, check=False, timeout=150)
        command('docker', 'start', ORIGINAL)
        result['original_restored_status'] = ready(ORIGINAL)
        result['protected_after'] = {name: state(name) for name in PROTECTED}
        result['original_after'] = state(ORIGINAL)
        result['app_after_seconds'] = app_probe()
        result['finished_at'] = time.time()
        result['guard_failures'] = failures
        result['complete'] = bool(result.get('scenarios_complete') and not failures and protected == result['protected_after'])
        (output / 'summary.json').write_text(json.dumps(result, indent=2) + '\n')
        assert protected == result['protected_after'], 'Protected containers changed during the benchmark'


if __name__ == '__main__':
    main()
