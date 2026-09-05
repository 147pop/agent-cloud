#!/usr/bin/env python3
"""Prove that live K3s-port listeners are reachable locally and blocked externally."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import selectors
import socket
import time

PORTS = [(socket.SOCK_STREAM, port) for port in (2379, 2380, 6443, 10250)] + [
    (socket.SOCK_DGRAM, port) for port in (8472, 51820, 51821)]
MARKER = b'E0_FIREWALL_PROBE'


def probe(host, kind, port):
    result = {'host': host, 'protocol': 'tcp' if kind == socket.SOCK_STREAM else 'udp', 'port': port, 'reachable': False}
    with socket.socket(socket.AF_INET, kind) as sock:
        sock.settimeout(3)
        try:
            sock.connect((host, port))
            if kind == socket.SOCK_STREAM:
                result['reachable'] = True
            else:
                sock.sendall(MARKER)
            result['marker_received'] = sock.recv(64) == MARKER
            result['reachable'] = True
        except OSError as error:
            result['error'] = str(error)
    return result


def serve(seconds):
    with selectors.DefaultSelector() as selector:
        try:
            for kind, port in PORTS:
                sock = socket.socket(socket.AF_INET, kind)
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                sock.bind(('0.0.0.0', port))
                if kind == socket.SOCK_STREAM:
                    sock.listen(8)
                sock.setblocking(False)
                selector.register(sock, selectors.EVENT_READ, kind)
            print(json.dumps({'event': 'listening', 'ports': [port for _, port in PORTS]}), flush=True)
            deadline = time.monotonic() + seconds
            while time.monotonic() < deadline:
                for key, _ in selector.select(timeout=1):
                    if key.data == socket.SOCK_STREAM:
                        connection, peer = key.fileobj.accept()
                        with connection:
                            connection.sendall(MARKER)
                    else:
                        data, peer = key.fileobj.recvfrom(64)
                        if data == MARKER:
                            key.fileobj.sendto(MARKER, peer)
                    print(json.dumps({'event': 'received', 'port': key.fileobj.getsockname()[1], 'peer': peer[0]}), flush=True)
        finally:
            for key in list(selector.get_map().values()):
                key.fileobj.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['serve', 'probe'])
    parser.add_argument('--seconds', type=int, default=120)
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--expect', choices=['open', 'blocked'], default='open')
    args = parser.parse_args()
    assert 1 <= args.seconds <= 600
    if args.mode == 'serve':
        serve(args.seconds)
    else:
        with ThreadPoolExecutor(max_workers=len(PORTS)) as pool:
            results = list(pool.map(lambda pair: probe(args.host, *pair), PORTS))
        print(json.dumps({'observed_at': time.time(), 'expect': args.expect, 'results': results}, indent=2))
        assert all(row['reachable'] == (args.expect == 'open') for row in results), 'Firewall expectation failed'
        if args.expect == 'open':
            assert all(row.get('marker_received') for row in results), 'Probe listener did not answer'
