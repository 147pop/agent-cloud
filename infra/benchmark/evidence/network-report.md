# E0 network measurements

Measured on 2026-09-05 between Contabo `203.0.113.12` and Oracle Santiago `203.0.113.11`. The [derived values](network-measurements.json) retain the source checksums. [Raw output and exact commands](network-paced-20260905/summary.json) cover every transfer and the Contabo-side probes. Oracle's [reverse ping](ping-oracle-contabo-20260905.txt) and [MTU probes](mtu-oracle-contabo-1473-20260905.txt) complete the opposite path.

| Measurement | Contabo to Oracle | Oracle to Contabo |
| --- | ---: | ---: |
| ICMP samples | 100 | 100 |
| RTT p50 / p95 | 194 / 194 ms | 194 / 194 ms |
| Maximum RTT | 202 ms | 202 ms |
| ICMP loss | 0% | 0% |
| Effective IPv4 MTU | 1500 | 1500 |
| TCP received over 20 seconds | 38.88 Mbit/s | 49.96 Mbit/s |
| TCP retransmissions | 0 | 4914 |
| UDP received over 20 seconds | 4.948 Mbit/s | 4.997 Mbit/s |
| UDP jitter reported by receiver | 0.058 ms | 0.744 ms |
| UDP loss reported by receiver | 0 | 7 datagrams, 0.0665% |

Per-packet ping output has 1 ms precision at this RTT. TCP used a 50 Mbit/s target and UDP a 5 Mbit/s target with 1200-byte datagrams. Both used iperf's application pacing and Linux socket pacing. These are bounded transfer measurements, not maximum link capacity.

The first [attempt](network-20260905/summary.json) used application pacing alone. TCP caught up after slow start with a short burst that exceeded the server's 60 Mbit/s guard. The server stopped that transfer. Adding `--fq-rate` completed all four transfers with the same server guard and the same one-second protected-app limit. The failed output and both server logs remain alongside the accepted run.

The accepted run recorded 109 protected-app probes, all successful, with a maximum of 0.946 seconds. The [post-test check](contabo-after-network-20260905.json) verified unchanged identities, start times and restart counts for Salta's containers and the original E0 Paper container. Caddy retained its PID. The network test process exited; the original E0 Paper container remains running.

## Path assessment

Both directions passed 1472-byte ICMP payloads with the Don't Fragment bit. Payloads of 1473 bytes failed with MTU 1500 feedback. Oracle's interface MTU of 9000 must therefore not be copied into the inter-VPS tunnel configuration. Use 1420 as the E1 tunnel MTU target and verify the resulting pod path. Flannel supports an explicit WireGuard backend MTU, and K3s supports a custom Flannel configuration. See the [Flannel backend options](https://github.com/flannel-io/flannel/blob/master/Documentation/backends.md#wireguard) and [K3s network options](https://docs.k3s.io/networking/basic-network-options).

The observed path supports proceeding to the two-node K3s test. It is unsuitable for an assumption of local-network latency or lossless transfer: the round trip is about 194 ms and Oracle-to-Contabo TCP retransmitted packets. Recovery estimates must use the measured transfer rates and include disk and restore work. This test did not measure R2 access or demonstrate world recovery.

## Firewall proof and cleanup

For each host, `firewall.py` created live listeners on TCP 2379, 2380, 6443 and 10250, plus UDP 8472, 51820 and 51821. Local probes received the expected marker before and after the Mac's external probe. All seven external probes timed out on both hosts. The dated `firewall-*-local`, `firewall-*-external` and `firewall-*-local-after` JSON files preserve the ordering. This proves the tested IPv4 boundary, without relying on a closed port with no listener.

Both hosts also created and removed a temporary WireGuard interface successfully. K3s was not installed. Its peer allowances belong to E1 and remain closed now. The [K3s requirements](https://docs.k3s.io/installation/requirements) identify TCP 6443 for the server and UDP 51820 for the IPv4 WireGuard path; any future allowances must name only the inventoried peer addresses.

Iperf was stopped after the measurements. Oracle's temporary ICMP and TCP/UDP 5201 allowances for Contabo were removed from the NSG, runtime INPUT chain and persisted rules. The [Oracle inventory](../../inventory/oracle-vps-2026-09-05.json) records the cleanup and a new successful SSH connection. Contabo received no new inbound allowance.

## Reproduction

Prepare the temporary Oracle rules described in [the measurement README](../README.md), then start `iperf3 -4 -s --server-bitrate-limit 60M` on Oracle. From Contabo, run `python3 network.py 203.0.113.11 evidence/NEW_LABEL`. Labels must be new. Run these commands from Oracle for the reverse ICMP path:

```sh
ping -4 -n -D -i 0.2 -c 100 -W 2 203.0.113.12
ping -4 -n -M do -s 1472 -c 3 -W 2 203.0.113.12
ping -4 -n -M do -s 1473 -c 3 -W 2 203.0.113.12
```

The final MTU probe is expected to fail. Keep its error text. Stop iperf and remove the temporary ingress rules afterward. [Iperf's manual](https://software.es.net/iperf/invoking.html) documents reverse mode, JSON output and the pacing controls.
