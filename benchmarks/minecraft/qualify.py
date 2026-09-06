#!/usr/bin/env python3
"""Compare the pinned free candidates on the dedicated Oracle host."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tarfile
import threading
import time
import uuid

from run import ROOT, NODE, command, state, world_bytes
from summarize import p95, tick_windows

PROFILE = json.loads((ROOT / 'free-profile.json').read_text())


def native_ticks(response):
    plain = re.sub(r'\x1b\[[0-9;]*m', '', response)
    match = re.search(r'Average time per tick: ([\d.]+)ms.*?P50: ([\d.]+)ms P95: ([\d.]+)ms P99: ([\d.]+)ms\. Sample: (\d+)', plain, re.S)
    assert match and '20.0 per second' in plain, f'Unexpected tick query: {plain}'
    mean, median, upper, tail = map(float, match.groups()[:4])
    assert 0 <= median <= upper <= tail and int(match[5]) == 100
    return dict(tick_mean_ms=mean, tick_p50_ms=median, tick_p95_ms=upper, tick_p99_ms=tail, tick_sample_size=100)


def game_ticks(response):
    match = re.fullmatch(r'The game time is (\d+) tick\(s\)', response)
    assert match, f'Unexpected gametime response: {response}'
    return int(match[1])


def rcon(name, text):
    return command('docker', 'exec', name, 'rcon-cli', text, timeout=20).stdout.strip()


def world_hashes(data):
    return {str(path.relative_to(data)): hashlib.sha256(path.read_bytes()).hexdigest()
            for world in sorted(data.glob('world*')) if world.is_dir()
            for path in sorted(world.rglob('*')) if path.is_file()}


def measurements(samples, events, thresholds=None):
    complete = [event for event in events if event['event'] == 'complete']
    assert len(complete) == 1 and not any(event['event'] in ('failed', 'bot_error', 'bot_kicked') for event in events)
    players = complete[0]['observations']
    assert players and all(player['confirmed_hits'] > 0 and player['survival']['block_confirmed']
                           and player['survival']['walked_blocks'] >= 3 and abs(player['survival']['vertical_change']) <= 1 for player in players)
    phases = [(datetime.fromisoformat(event['time']).timestamp(), event['name']) for event in events if event['event'] == 'phase']
    end = datetime.fromisoformat(complete[0]['time']).timestamp()
    active = [sample for sample in samples if phases[0][0] <= sample['time'] <= end and 'game_ticks' in sample]
    assert len(active) >= 3, 'Missing active tick measurements'
    windows = tick_windows(active)
    waits = [event['seconds'] for event in events if event['event'] == 'chunk_wait'
             and phases[0][0] <= datetime.fromisoformat(event['time']).timestamp() <= end]
    responses = [event['seconds'] for event in events if event['event'] in ('server_position_verified', 'server_block_verified')]
    assert waits and len(responses) == len(players) * 5
    cpu = [(int(b['cpu_stat']['usage_usec']) - int(a['cpu_stat']['usage_usec'])) / 1e6 / (b['time'] - a['time'])
           for a, b in zip(active, active[1:])]
    row = {
        'started_at': phases[0][0], 'finished_at': end,
        'active_seconds': end - phases[0][0], 'samples': len(active), 'tps_windows': len(windows),
        'minimum_tps_60s': min((value for _, value, _ in windows), default=None),
        'maximum_sampled_p95_tick_ms': max(sample['tick_p95_ms'] for sample in active),
        'maximum_sampled_p99_tick_ms': max(sample['tick_p99_ms'] for sample in active),
        'p95_chunk_wait_seconds': p95(waits), 'maximum_chunk_wait_seconds': max(waits),
        'total_chunk_wait_player_seconds': sum(waits),
        'p95_client_command_seconds': p95(responses), 'maximum_client_command_seconds': max(responses),
        'p95_rcon_seconds': p95([sample['game_tick_query_seconds'] for sample in active]),
        'maximum_rcon_seconds': max(sample['game_tick_query_seconds'] for sample in active),
        'mean_cpu_cores': sum(cpu) / len(cpu), 'peak_cpu_cores': max(cpu),
        'peak_container_mib': max(sample['memory_bytes'] for sample in samples) / 1024**2,
        'confirmed_hits': sum(player['confirmed_hits'] for player in players),
        'client_bytes': sum(player['bytes_read'] + player['bytes_written'] for player in players),
        'phases': {name: (phases[index + 1][0] if index + 1 < len(phases) else end) - start
                   for index, (start, name) in enumerate(phases)},
    }
    limits = thresholds if thresholds is not None else PROFILE['thresholds']
    row['performance_pass'] = bool(windows and
        row['minimum_tps_60s'] >= limits['minimum_tps_60s'] and
        row['maximum_sampled_p95_tick_ms'] <= limits['maximum_sampled_p95_tick_ms'] and
        row['maximum_sampled_p99_tick_ms'] <= limits['maximum_sampled_p99_tick_ms'] and
        row['p95_chunk_wait_seconds'] <= limits['p95_chunk_wait_seconds'] and
        row['maximum_chunk_wait_seconds'] <= limits['maximum_chunk_wait_seconds'] and
        row['p95_client_command_seconds'] <= limits['p95_command_seconds'] and
        row['maximum_client_command_seconds'] <= limits['maximum_command_seconds'] and
        row['p95_rcon_seconds'] <= limits['p95_command_seconds'] and
        row['maximum_rcon_seconds'] <= limits['maximum_command_seconds'])
    return row


def simultaneous_play(rows, cases, count, repeats):
    result = []
    for repeat in range(1, repeats + 1):
        names = {case['name'] for case in cases if case['repeat'] == repeat}
        for phase in ('fresh', 'populated'):
            active = [row for row in rows if row['case'] in names and row['phase'] == phase]
            seconds = max(0, min(row['finished_at'] for row in active) - max(row['started_at'] for row in active)) if len(active) == count else 0
            result.append({'repeat': repeat, 'phase': phase, 'seconds': seconds})
    return result


def report(directory):
    summary = json.loads((directory / 'summary.json').read_text())
    samples = [json.loads(line) for line in (directory / 'metrics.jsonl').read_text().splitlines()]
    rows, errors = [], []
    for case in sorted(summary['cases'], key=lambda entry: entry['name']):
        for phase in ('fresh', 'populated'):
            try:
                events = [json.loads(line) for line in (directory / f"{case['name']}-{phase}-players.jsonl").read_text().splitlines() if line.startswith('{')]
                completed = [event for event in events if event['event'] == 'complete']
                assert len(completed) == 1
                players = completed[0]['observations']
                assert len(players) == summary['parameters']['players']
                assert all(player['explored_blocks'] >= summary['parameters']['seconds'] * 8 - 2 and
                           player['revisited_blocks'] >= summary['parameters']['seconds'] * 8 - 2 for player in players)
                selected = [sample for sample in samples if sample.get('case') == case['name'] and sample.get('stage') == phase]
                row = measurements(selected, events, summary['profile']['thresholds'])
                rows.append({'case': case['name'], 'phase': phase, **row})
            except (AssertionError, KeyError, FileNotFoundError) as error:
                errors.append({'case': case['name'], 'phase': phase, 'error': str(error)})
    overlap = simultaneous_play(rows, summary['cases'], summary['parameters']['instances'], summary['parameters']['repeats'])
    host = [sample for sample in samples if 'container' not in sample and 'available_bytes' in sample]
    host_cpu = [list(map(int, sample['host_cpu_stat'].split()[1:9])) for sample in host]
    cpu_intervals = []
    for before, after in zip(host_cpu, host_cpu[1:]):
        delta = [b - a for a, b in zip(before, after)]
        if sum(delta) > 0:
            cpu_intervals.append(summary['host']['cores'] * sum(delta[index] for index in (0, 1, 2, 5, 6)) / sum(delta))
    mixed = {'startup_with_play_samples': 0, 'save_with_play_samples': 0}
    snapshots = {}
    for sample in samples:
        if 'container' in sample:
            snapshots.setdefault(sample['time'], []).append(sample)
    for timestamp, snapshot in snapshots.items():
        if any(row['started_at'] <= timestamp <= row['finished_at'] for row in rows):
            mixed['startup_with_play_samples'] += any(sample['stage'] in ('cold_start', 'warm_start', 'verify_restart') for sample in snapshot)
            mixed['save_with_play_samples'] += any(sample['stage'] == 'save' for sample in snapshot)
    mixed['background_saves_with_other_instances_playing'] = sum(
        any(row['case'] != case['name'] and row['started_at'] <= phase.get('background_save_started_at', 0) <= row['finished_at'] for row in rows)
        for case in summary['cases'] for phase in case.get('phases', {}).values())
    totals = {}
    for sample in samples:
        if 'container' in sample:
            totals[sample['time']] = totals.get(sample['time'], 0) + sample['memory_bytes']
    recipes = {json.dumps(case.get('recipe_sha256'), sort_keys=True) for case in summary['cases']}
    recipes_match = len(recipes) == 1 and all(case.get('recipe_sha256') for case in summary['cases'])
    startup_pass = all(max(case.get(key, float('inf')) for key in ['cold_ready_seconds', 'warm_ready_seconds', 'populated_ready_seconds'])
                       <= summary['profile']['thresholds']['maximum_ready_seconds'] for case in summary['cases'])
    repeated = summary['parameters']['repeats'] == 2 and summary['parameters']['seconds'] >= 60
    return {'parameters': summary['parameters'], 'report_source_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            'operational_complete': summary['complete'], 'errors': errors, 'mixed_activity': mixed,
            'guard_failures': summary['guard_failures'], 'recipes_match': recipes_match, 'startup_pass': startup_pass,
            'rows': rows, 'simultaneous_play': overlap,
            'seconds_with_all_instances_playing': sum(row['seconds'] for row in overlap),
            'peak_host_busy_cpu_cores': max(cpu_intervals, default=None),
            'peak_total_game_memory_mib': max(totals.values(), default=0) / 1024**2,
            'minimum_available_gib': min((sample['available_bytes'] for sample in host), default=0) / 1024**3,
            'minimum_free_disk_gib': min((sample['free_disk_bytes'] for sample in host), default=0) / 1024**3,
            'elapsed_minutes': (summary['finished_at'] - summary['started_at']) / 60,
            'repeated_synthetic_pass': bool(repeated and summary['complete'] and not errors and recipes_match and startup_pass
                                             and rows and all(row['performance_pass'] for row in rows) and all(row['seconds'] >= 60 for row in overlap)),
            'external_human_play': 'not measured by this runner'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('label')
    parser.add_argument('--engine', choices=['paper', 'fabric', 'fabric-c2me'], required=True)
    parser.add_argument('--players', type=int, choices=[1, 2, 4], default=2)
    parser.add_argument('--instances', type=int, default=1)
    parser.add_argument('--repeats', type=int, default=2)
    parser.add_argument('--seconds', type=int, default=60)
    args = parser.parse_args()
    assert re.fullmatch(r'[a-z0-9-]{1,32}', args.label)
    assert 1 <= args.instances <= 7 and 1 <= args.repeats <= 2 and 10 <= args.seconds <= 180
    assert os.geteuid() == 0 and os.uname().machine == 'aarch64' and os.cpu_count() == 4
    assert not command('docker', 'ps', '-q').stdout.strip(), 'The dedicated host must have no running containers'
    assert (ROOT / '.env').stat().st_mode & 0o077 == 0, 'Use a private mode-600 .env'
    output = ROOT / 'evidence' / 'free' / args.label
    output.mkdir(parents=True, exist_ok=False)
    data_root = ROOT / 'data' / 'free' / args.label
    data_root.mkdir(parents=True, exist_ok=False)
    names = {}
    lock = threading.Lock()
    abort = threading.Event()
    finished = threading.Event()
    failures = []
    result = {'parameters': vars(args), 'started_at': time.time(), 'profile': PROFILE, 'cases': [],
              'source_sha256': {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
                               for name in ['qualify.py', 'players.js', 'protocol26.js', 'run.py', 'summarize.py', 'compose.free.yml',
                                            'free-profile.json', 'package.json', 'package-lock.json']},
              'host': {'architecture': os.uname().machine, 'cores': os.cpu_count(), 'kernel': os.uname().release,
                       'memory_bytes': int(re.search(r'MemTotal:\s+(\d+)', Path('/proc/meminfo').read_text())[1]) * 1024}}
    with tarfile.open(output / 'sources.tar.gz', 'w:gz') as archive:
        for name in result['source_sha256']:
            archive.add(ROOT / name, arcname=name)

    def guard():
        assert not abort.is_set(), f'Benchmark aborted: {failures[-1] if failures else "interrupted"}'

    def sample():
        with (output / 'metrics.jsonl').open('w', buffering=1) as stream:
            while not finished.is_set():
                now = time.time()
                try:
                    memory = Path('/proc/meminfo').read_text()
                    available = int(re.search(r'MemAvailable:\s+(\d+)', memory)[1]) * 1024
                    disk = shutil.disk_usage(ROOT).free
                    assert available >= PROFILE['host_min_available_gib'] * 1024**3, 'Host memory reserve crossed'
                    assert disk >= PROFILE['host_min_free_disk_gib'] * 1024**3, 'Host disk reserve crossed'
                    host = {'time': now, 'available_bytes': available, 'free_disk_bytes': disk,
                            'host_cpu_stat': Path('/proc/stat').read_text().splitlines()[0],
                            'pressure_cpu': Path('/proc/pressure/cpu').read_text().strip(),
                            'pressure_memory': Path('/proc/pressure/memory').read_text().strip(),
                            'pressure_io': Path('/proc/pressure/io').read_text().strip()}
                    stream.write(json.dumps(host) + '\n')
                    with lock:
                        current = [(name, entry.copy()) for name, entry in names.items()]
                    for name, entry in current:
                        observed = command('docker', 'inspect', name, check=False)
                        if observed.returncode:
                            continue
                        container = json.loads(observed.stdout)[0]
                        assert not container['State']['OOMKilled'], f'{name} was OOM killed'
                        pid = container['State']['Pid']
                        if not pid:
                            continue
                        group = Path('/sys/fs/cgroup') / Path(f'/proc/{pid}/cgroup').read_text().strip().split('::')[1].lstrip('/')
                        record = {**host, 'container': name, 'case': entry['case'], 'stage': entry['stage'],
                                  'memory_bytes': int((group / 'memory.current').read_text()),
                                  'cpu_stat': dict(line.split() for line in (group / 'cpu.stat').read_text().splitlines()),
                                  'memory_events': (group / 'memory.events').read_text()}
                        if entry['stage'] in ('fresh', 'populated'):
                            start = time.time()
                            response = rcon(name, 'time query gametime')
                            record['game_tick_query_seconds'] = time.time() - start
                            record['game_tick_time'] = start + record['game_tick_query_seconds'] / 2
                            record['game_ticks'] = game_ticks(response)
                            record['tick_query'] = rcon(name, 'tick query')
                            record.update(native_ticks(record['tick_query']))
                        stream.write(json.dumps(record) + '\n')
                        if entry['stage'] in ('fresh', 'populated'):
                            assert world_bytes(Path(entry['data'])) < PROFILE['world_soft_limit_gb'] * 10**9, 'World soft limit crossed'
                except (FileNotFoundError, ProcessLookupError):
                    pass
                except Exception as error:
                    failures.append(str(error))
                    stream.write(json.dumps({'time': time.time(), 'error': str(error)}) + '\n')
                    abort.set()
                finished.wait(5)

    def mark(name, stage):
        with lock:
            names[name]['stage'] = stage
        print(json.dumps({'case': names[name]['case'], 'stage': stage, 'time': time.time()}), flush=True)

    def ready(name):
        start = time.monotonic()
        while time.monotonic() - start < 240:
            guard()
            observed = state(name)
            assert observed['running'], f'{name} stopped before readiness'
            if observed['health'] == 'healthy':
                return
            time.sleep(2)
        raise RuntimeError(f'{name} did not become ready')

    def scenario(repeat, index):
        case_id = f'r{repeat}-i{index + 1}'
        name = f'cloud-free-{args.label}-{case_id}'
        bot_name = name + '-bots'
        data = data_root / case_id
        data.mkdir()
        operators = []
        for number in range(1, 5):
            username = f'Bench{number:02}'
            ident = uuid.UUID(bytes=hashlib.md5(f'OfflinePlayer:{username}'.encode()).digest(), version=3)
            operators.append({'uuid': str(ident), 'name': username, 'level': 4, 'bypassesPlayerLimit': False})
        (data / 'ops.json').write_text(json.dumps(operators))
        mods = [] if args.engine == 'paper' else ['lithium', 'ferrite-core']
        if args.engine == 'fabric-c2me':
            mods.append('c2me-fabric')
            (data / 'config').mkdir()
            (data / 'config' / 'c2me.toml').write_text('version = 3\nglobalExecutorParallelism = 2\n')
        env = {**os.environ, 'FREE_CONTAINER': name, 'FREE_ENGINE': 'PAPER' if args.engine == 'paper' else 'FABRIC',
               'FREE_MAX_PLAYERS': str(args.players),
               'FREE_MODS': ','.join(f"{mod}:{PROFILE['mods'][mod]['modrinth_id']}" for mod in mods),
               'FREE_PORT': str(25570 + index), 'FREE_DATA': str(data)}
        compose = ['docker', 'compose', '-p', name, '-f', 'compose.free.yml']
        case = {'name': case_id, 'repeat': repeat, 'instance': index + 1, 'phases': {}, 'started_at': time.time()}
        with lock:
            names[name] = {'case': case_id, 'stage': 'cold_start', 'data': str(data)}
            result['cases'].append(case)
        try:
            start = time.monotonic()
            command(*compose, 'up', '-d', env=env, timeout=240)
            ready(name)
            case['cold_ready_seconds'] = time.monotonic() - start
            inspect = json.loads(command('docker', 'inspect', name).stdout)[0]
            case['container_limits'] = {key: inspect['HostConfig'][key] for key in ['NanoCpus', 'CpusetCpus', 'Memory', 'MemorySwap']}
            assert case['container_limits'] == {'NanoCpus': 2_000_000_000, 'CpusetCpus': '0-2', 'Memory': 3 * 1024**3, 'MemorySwap': 3 * 1024**3}
            case['java_version'] = command('docker', 'exec', name, 'java', '-version').stderr.strip()
            assert '25.0.4' in case['java_version']
            case['jvm_flags'] = command('docker', 'exec', name, 'sh', '-c', 'jattach "$(pidof java)" jcmd VM.flags').stdout
            assert '-XX:ActiveProcessorCount=2' in case['jvm_flags'] and '-XX:MaxHeapSize=2147483648' in case['jvm_flags']
            case['recipe_sha256'] = {str(path.relative_to(data)): hashlib.sha256(path.read_bytes()).hexdigest()
                                     for path in sorted(data.rglob('*.jar'))}
            config_dir = output / f'{case_id}-config'
            config_dir.mkdir()
            for path in sorted(data.glob('config/*')) + [data / 'bukkit.yml', data / 'spigot.yml']:
                if path.is_file():
                    shutil.copy2(path, config_dir / path.name)
                    case['recipe_sha256'][str(path.relative_to(data))] = hashlib.sha256(path.read_bytes()).hexdigest()
            for mod in mods:
                pinned = PROFILE['mods'][mod]
                assert hashlib.sha512((data / 'mods' / pinned['filename']).read_bytes()).hexdigest() == pinned['sha512'], f'{mod} hash mismatch'
            properties = dict(line.split('=', 1) for line in (data / 'server.properties').read_text().splitlines() if '=' in line and not line.startswith('#'))
            case['properties'] = {key: properties[key] for key in ['level-seed', 'gamemode', 'difficulty', 'view-distance', 'simulation-distance', 'max-players', 'online-mode', 'allow-flight']}
            assert case['properties'] == {'level-seed': '20260904', 'gamemode': 'survival', 'difficulty': 'normal', 'view-distance': '6',
                                          'simulation-distance': '4', 'max-players': str(args.players), 'online-mode': 'false', 'allow-flight': 'true'}
            native_ticks(rcon(name, 'tick query'))
            if index:
                time.sleep(index * 30)
            for phase in ('fresh', 'populated'):
                mark(name, phase)
                phase_file = output / f'{case_id}-{phase}-players.jsonl'
                phase_result = {'started_at': time.time(), 'world_bytes_before': world_bytes(data)}
                case['phases'][phase] = phase_result
                with phase_file.open('w') as stream:
                    process = subprocess.Popen(['docker', 'run', '--rm', '--name', bot_name, '--network', f'container:{name}',
                        '--cpuset-cpus', '3', '--cpus', '1', '--memory', '1g', '--memory-swap', '1g', '--pids-limit', '128',
                        '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges', '--read-only', '--tmpfs', '/tmp',
                        '--user', '1001:1001', '-v', f'{ROOT}:/work:ro', '-w', '/work', NODE,
                        'node', 'players.js', str(args.players), str(args.seconds), '26.2', '--survival'],
                        stdout=stream, stderr=subprocess.STDOUT)
                    deadline = time.monotonic() + args.seconds * 6 + args.players * 100 + 120
                    saved = False
                    try:
                        while process.poll() is None:
                            guard()
                            assert time.monotonic() < deadline, 'Player scenario deadline exceeded'
                            if not saved and time.time() - phase_result['started_at'] > 45:
                                phase_result['background_save_started_at'] = time.time()
                                start = time.monotonic()
                                phase_result['background_save_response'] = rcon(name, 'save-all flush')
                                phase_result['background_save_seconds'] = time.monotonic() - start
                                saved = True
                            time.sleep(2)
                        assert process.returncode == 0, f'Player actions failed in {case_id}-{phase}'
                    finally:
                        command('docker', 'stop', '-t', '5', bot_name, check=False, timeout=15)
                        process.wait(timeout=15)
                phase_result['finished_at'] = time.time()
                phase_result['world_bytes_after'] = world_bytes(data)
                mark(name, 'save')
                if phase == 'fresh':
                    assert 'Changed the block' in rcon(name, 'setblock 0 201 0 minecraft:diamond_block')
                assert 'Saved the game' in rcon(name, 'save-all flush')
                mark(name, 'stop')
                command('docker', 'stop', '-t', '120', name, timeout=150)
                assert json.loads(command('docker', 'inspect', name).stdout)[0]['State']['ExitCode'] == 0
                if phase == 'fresh':
                    before = world_hashes(data)
                    archive = data_root / f'{case_id}-world.tar.gz'
                    with tarfile.open(archive, 'w:gz') as tar:
                        for world in sorted(data.glob('world*')):
                            if world.is_dir():
                                tar.add(world, arcname=world.name)
                    retained = data_root / f'{case_id}-before-restore'
                    retained.mkdir()
                    for world in sorted(data.glob('world*')):
                        if world.is_dir():
                            world.rename(retained / world.name)
                    with tarfile.open(archive) as tar:
                        tar.extractall(data, filter='data')
                    assert world_hashes(data) == before, 'Restored world bytes differ from the clean backup'
                    command('chown', '-R', '1000:1000', *(str(world) for world in data.glob('world*') if world.is_dir()))
                    case['backup'] = {'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(), 'bytes': archive.stat().st_size,
                                      'files_verified': len(before), 'restored_into_empty_world_paths': True}
                    mark(name, 'warm_start')
                    start = time.monotonic()
                    command('docker', 'start', name)
                    ready(name)
                    case['warm_ready_seconds'] = time.monotonic() - start
                    rcon(name, 'forceload add 0 0 31 31')
                    assert 'Test passed' in rcon(name, 'execute if block 0 201 0 minecraft:diamond_block')
                    for text in ['fill 16 199 16 31 199 31 minecraft:stone',
                                 'fill 16 200 16 31 200 16 minecraft:oak_fence', 'fill 16 200 31 31 200 31 minecraft:oak_fence',
                                 'fill 16 200 17 16 200 30 minecraft:oak_fence', 'fill 31 200 17 31 200 30 minecraft:oak_fence']:
                        rcon(name, text)
                    for number in range(24):
                        rcon(name, f'summon minecraft:cow {18 + number % 6 * 2} 200 {18 + number // 6 * 2} {{PersistenceRequired:1b,Tags:["FreePopulation"]}}')
                    for number in range(8):
                        rcon(name, f'summon minecraft:villager {18 + number % 4 * 2} 200 {26 + number // 4 * 2} {{PersistenceRequired:1b,Tags:["FreePopulation"]}}')
                    for number in range(16):
                        rcon(name, f'setblock {number} 199 24 minecraft:hopper')
                    case['population_response'] = rcon(name, 'execute if entity @e[tag=FreePopulation]')
                    assert '32' in case['population_response'], case['population_response']
                else:
                    mark(name, 'verify_restart')
                    start = time.monotonic()
                    command('docker', 'start', name)
                    ready(name)
                    case['populated_ready_seconds'] = time.monotonic() - start
                    assert 'Test passed' in rcon(name, 'execute if block 0 201 0 minecraft:diamond_block')
                    case['population_after_restart'] = rcon(name, 'execute if entity @e[tag=FreePopulation]')
                    assert '32' in case['population_after_restart'], case['population_after_restart']
                    mark(name, 'stop')
                    command('docker', 'stop', '-t', '120', name, timeout=150)
            case['complete'] = True
        except Exception as error:
            case['error'] = str(error)
            failures.append(str(error))
            abort.set()
        finally:
            mark(name, 'cleanup')
            command('docker', 'stop', '-t', '5', bot_name, check=False, timeout=15)
            command('docker', 'stop', '-t', '120', name, check=False, timeout=150)
            logs = command('docker', 'logs', name, check=False)
            (output / f'{case_id}-server.log').write_text(logs.stdout + logs.stderr)
            removed = command(*compose, 'down', env=env, check=False, timeout=90)
            if removed.returncode:
                failures.append(f'Cleanup failed for {case_id}: {removed.stderr}')
                abort.set()
            case['finished_at'] = time.time()

    def interrupted(signum, frame):
        failures.append(f'Interrupted by signal {signum}')
        abort.set()

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    sampler = threading.Thread(target=sample, daemon=True)
    sampler.start()
    try:
        with ThreadPoolExecutor(max_workers=args.instances) as pool:
            for repeat in range(1, args.repeats + 1):
                guard()
                futures = [pool.submit(scenario, repeat, index) for index in range(args.instances)]
                for future in futures:
                    future.result()
                guard()
    except Exception as error:
        result['error'] = str(error)
    finally:
        finished.set()
        sampler.join(timeout=60)
        result['finished_at'] = time.time()
        if any(hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != digest for name, digest in result['source_sha256'].items()):
            failures.append('Benchmark sources changed during execution')
        result['guard_failures'] = failures
        result['complete'] = not failures and not result.get('error') and not sampler.is_alive() and len(result['cases']) == args.instances * args.repeats and all(case.get('complete') for case in result['cases'])
        result['running_containers_after'] = command('docker', 'ps', '--format', '{{.Names}}').stdout.splitlines()
        result['complete'] = result['complete'] and not result['running_containers_after']
        (output / 'summary.json').write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps({'label': args.label, 'complete': result['complete'], 'errors': failures}), flush=True)
    assert result['complete'], 'Incomplete battery; inspect retained evidence'


if __name__ == '__main__':
    if sys.argv[1:2] == ['--report']:
        assert len(sys.argv) == 3, 'Use --report EVIDENCE_DIRECTORY'
        print(json.dumps(report(Path(sys.argv[2])), indent=2))
    else:
        main()
