#!/usr/bin/env python3
"""Measure Contabo to Oracle at bounded rates while guarding the existing app."""
import argparse
import hashlib
import ipaddress
import json
from pathlib import Path
import subprocess
import time

from run import app_probe


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('peer', type=ipaddress.IPv4Address)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    peer = str(args.peer)
    args.output.mkdir(parents=True, exist_ok=False)
    result = {'started_at': time.time(), 'peer': peer, 'commands': [], 'app_probes': [],
              'source_sha256': {name: hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest()
                                for name in ['network.py', 'run.py']}}

    def run(name, command, check=True):
        record = {'name': name, 'command': command, 'started_at': time.time()}
        result['commands'].append(record)
        with (args.output / f'{name}.txt').open('w') as stream:
            process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT)
            try:
                while process.poll() is None:
                    result['app_probes'].append({'time': time.time(), 'seconds': app_probe()})
                    assert time.time() - record['started_at'] < 120, f'{name} timed out'
                    time.sleep(1)
            finally:
                if process.poll() is None:
                    process.terminate()
                record['returncode'] = process.wait(timeout=10)
                record['finished_at'] = time.time()
        if check:
            assert record['returncode'] == 0, f'{name} failed'
        print(json.dumps(record), flush=True)
        return (args.output / f'{name}.txt').read_text()

    try:
        run('iperf-version', ['iperf3', '--version'])
        run('ping-contabo-oracle', ['ping', '-4', '-n', '-D', '-i', '0.2', '-c', '100', '-W', '2', peer])
        for payload in (1472, 1473):
            run(f'mtu-contabo-oracle-{payload}', ['ping', '-4', '-n', '-M', 'do', '-s', str(payload), '-c', '3', '-W', '2', peer], check=False)
        for protocol, rate in [('tcp', '50M'), ('udp', '5M')]:
            for reverse in (False, True):
                direction = 'oracle-contabo' if reverse else 'contabo-oracle'
                command = ['iperf3', '-4', '-c', peer, '-t', '20', '-b', rate, '-J', '--get-server-output', '--connect-timeout', '5000']
                if protocol == 'udp':
                    command += ['-u', '-l', '1200']
                if reverse:
                    command += ['-R']
                output = json.loads(run(f'{protocol}-{direction}', command))
                assert 'error' not in output and 'end' in output, output.get('error')
        result['complete'] = True
    except Exception as error:
        result['error'] = str(error)
        raise
    finally:
        result['finished_at'] = time.time()
        (args.output / 'summary.json').write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
