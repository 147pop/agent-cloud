#!/usr/bin/env python3
"""Bounded, QD1 disk measurements for TES-51. Run on Linux with ionice -c3."""
import json
import mmap
import os
from pathlib import Path
import random
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
import urllib.request


def app_probe():
    start = time.monotonic()
    with urllib.request.urlopen('http://127.0.0.1:3000/', timeout=2) as response:
        assert response.status == 200, response.status
        response.read(1024)
    elapsed = time.monotonic() - start
    assert elapsed < 1, f'Protected app took {elapsed:.3f}s; stopping disk test'
    return elapsed


def percentile(values, fraction):
    return sorted(values)[max(0, int(len(values) * fraction + 0.999999) - 1)]


def main():
    destination = Path(sys.argv[1]).resolve()
    assert not destination.exists(), 'Do not overwrite evidence'
    assert shutil.disk_usage(destination.parent).free > 20 * 1024**3
    result = {'started_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
              'host': os.uname().nodename, 'command': 'ionice -c3 nice -n 19 python3 disk.py OUTPUT.json',
              'filesystem': subprocess.check_output(['findmnt', '-J', '-T', str(destination.parent)], text=True),
              'file_bytes': 256 * 1024**2, 'queue_depth': 1,
              'flags': ['O_DIRECT', 'O_DSYNC'], 'seed': 20260904,
              'free_bytes_before': shutil.disk_usage(destination.parent).free,
              'app_seconds': [app_probe() for _ in range(5)], 'phases': []}
    rng = random.Random(result['seed'])
    try:
        with tempfile.TemporaryDirectory(prefix='e0-disk-', dir=destination.parent) as directory:
            path = Path(directory) / 'probe.bin'
            fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_RDWR | os.O_DIRECT | os.O_DSYNC, 0o600)
            try:
                with mmap.mmap(-1, 1024**2) as buffer:
                    buffer[:] = rng.randbytes(len(buffer))
                    for name, size, count, pause in [('sequential_write', 1024**2, 256, .02),
                                                       ('sequential_read', 1024**2, 256, .02),
                                                       ('random_write', 4096, 256, .01),
                                                       ('random_read', 4096, 256, .01)]:
                        phase = {'name': name, 'block_bytes': size, 'operations': count,
                                 'pause_seconds': pause, 'latency_ms': []}
                        result['phases'].append(phase)
                        start = time.monotonic()
                        last_probe = start
                        for index in range(count):
                            offset = index * size if name.startswith('sequential') else rng.randrange(65536) * 4096
                            view = memoryview(buffer)[:size]
                            before = time.monotonic()
                            try:
                                method = os.pwritev if name.endswith('write') else os.preadv
                                assert method(fd, [view], offset) == size
                            finally:
                                view.release()
                            phase['latency_ms'].append((time.monotonic() - before) * 1000)
                            if time.monotonic() - last_probe >= 1:
                                result['app_seconds'].append(app_probe())
                                last_probe = time.monotonic()
                            time.sleep(pause)
                        phase['wall_seconds'] = time.monotonic() - start
                        phase['mib_per_second_including_pauses'] = count * size / 1024**2 / phase['wall_seconds']
                        phase['p50_ms'] = statistics.median(phase['latency_ms'])
                        phase['p95_ms'] = percentile(phase['latency_ms'], .95)
                        print(json.dumps({k: v for k, v in phase.items() if k != 'latency_ms'}), flush=True)
            finally:
                os.close(fd)
        result['app_seconds'].append(app_probe())
        result['free_bytes_after'] = shutil.disk_usage(destination.parent).free
        result['complete'] = True
    finally:
        destination.write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    if sys.argv[1:] == ['--self-test']:
        assert percentile([4, 1, 3, 2], .5) == 2
        assert percentile(list(range(1, 101)), .95) == 95
        print('disk percentile checks passed')
    else:
        main()
