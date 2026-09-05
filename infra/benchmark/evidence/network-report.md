# Network results, 2026-09-05

The Contabo to Oracle path has a **194 ms round trip** and an effective IPv4 MTU of 1500. E1 must account for that latency and verify the pod network.

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

## Method and limits

| Parameter | Value |
| --- | --- |
| Endpoints | Contabo `203.0.113.12`, Oracle `203.0.113.11` |
| Transfers | 20 seconds in each direction |
| TCP target | 50 Mbit/s |
| UDP target | 5 Mbit/s, 1200-byte datagrams |
| Pacing | iperf application pacing plus Linux socket pacing |
| Ping precision | 1 ms at this RTT |

These rates do not measure maximum link capacity. The first application-only pacing attempt exceeded the server's 60 Mbit/s guard. Adding `--fq-rate` completed all four transfers without changing that guard.

| Evidence | Record |
| --- | --- |
| Accepted transfers and Contabo probes | [Raw commands and output](network-paced-20260905/summary.json) |
| Failed pacing attempt | [Original output](network-20260905/summary.json) |
| Derived values and checksums | [Measurements](network-measurements.json) |
| Reverse ping | [Oracle to Contabo](ping-oracle-contabo-20260905.txt) |
| Reverse MTU failure | [1473-byte probe](mtu-oracle-contabo-1473-20260905.txt) |

## Implications for E1

| Finding | Next step |
| --- | --- |
| 1472-byte DF payload passed; 1473 failed | Use path MTU 1500, not Oracle's interface MTU 9000 |
| WireGuard tunnel | Target MTU 1420 and verify the resulting pod path |
| 194 ms RTT and reverse TCP retransmissions | Test K3s on this link; do not assume LAN latency or lossless transfer |
| R2 and world recovery | Test separately in E4; no recovery-time guarantee follows from these transfers |

[Flannel WireGuard options](https://github.com/flannel-io/flannel/blob/master/Documentation/backends.md#wireguard) · [K3s network options](https://docs.k3s.io/networking/basic-network-options)

## Firewall and cleanup

| Check | Result |
| --- | --- |
| TCP ports | 2379, 2380, 6443, 10250 blocked externally on both hosts |
| UDP ports | 8472, 51820, 51821 blocked externally on both hosts |
| Local listeners | Expected marker before and after the external Mac probes |
| WireGuard interfaces | Created and removed successfully on both hosts |
| Salta | 109 successful probes, slowest 0.946 s |
| Protected workloads | Same container identities, start times and restart counts; Caddy PID unchanged |
| Temporary access | Oracle ICMP and TCP/UDP 5201 allowances for Contabo removed |
| Temporary services | iperf and probe listeners stopped |

Dated `firewall-*-local`, `firewall-*-external` and `firewall-*-local-after` JSON records prove the tested IPv4 boundary with live listeners. Contabo received no new inbound allowance.

[Workload check](contabo-after-network-20260905.json) · [Oracle cleanup and SSH check](../../inventory/oracle-vps-2026-09-05.json)

K3s was not installed. E1 must restrict its required ingress to the inventoried peers. [K3s requirements](https://docs.k3s.io/installation/requirements)

## Reproduction

Prepare the temporary Oracle rules described in [the measurement README](../README.md), then start `iperf3 -4 -s --server-bitrate-limit 60M` on Oracle. From Contabo, run `python3 network.py 203.0.113.11 evidence/NEW_LABEL`. Labels must be new. Run these commands from Oracle for the reverse ICMP path:

```sh
ping -4 -n -D -i 0.2 -c 100 -W 2 203.0.113.12
ping -4 -n -M do -s 1472 -c 3 -W 2 203.0.113.12
ping -4 -n -M do -s 1473 -c 3 -W 2 203.0.113.12
```

The final MTU probe is expected to fail. Keep its error text. Stop iperf and remove the temporary ingress rules afterward. [Iperf's manual](https://software.es.net/iperf/invoking.html) documents reverse mode, JSON output and the pacing controls.
