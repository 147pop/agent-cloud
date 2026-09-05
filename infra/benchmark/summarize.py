#!/usr/bin/env python3
"""Validate a complete E0 battery and print its measurements as JSON."""
from datetime import datetime
import json
from pathlib import Path
import re
import statistics
import sys


def numbers(text):
    plain = re.sub(r'\x1b\[[0-9;]*m', '', text)
    return [float(value) for value in re.findall(r'\d+(?:\.\d+)?', plain.rsplit(':', 1)[-1])]


def p95(values):
    return sorted(values)[max(0, (len(values) * 95 + 99) // 100 - 1)]


def summarize(directory):
    summary = json.loads((directory / 'summary.json').read_text())
    assert summary['complete'] and not summary['guard_failures']
    assert summary['protected_before'] == summary['protected_after']
    assert summary['parameters']['players'] == [1, 2, 4, 8]
    assert summary['parameters']['repeats'] == 2 and summary['parameters']['seconds'] == 60
    assert len(summary['cases']) == 8
    assert sorted((case['repeat'], case['players']) for case in summary['cases']) == [
        (repeat, count) for repeat in (1, 2) for count in (1, 2, 4, 8)]
    samples = [json.loads(line) for line in (directory / 'metrics.jsonl').read_text().splitlines()]
    assert all('error' not in sample for sample in samples)
    rows = []
    for case in summary['cases']:
        events = [json.loads(line) for line in (directory / f"{case['name']}-players.jsonl").read_text().splitlines() if line.startswith('{')]
        assert not any(event['event'] in ('failed', 'bot_error', 'bot_kicked') for event in events)
        complete = [event for event in events if event['event'] == 'complete']
        assert len(complete) == 1
        players = complete[0]['observations']
        assert len(players) == case['players']
        assert all(player['confirmed_hits'] > 0 and player['explored_blocks'] >= 478 and player['revisited_blocks'] >= 478 for player in players)
        confirmations = [event for event in events if event['event'] == 'server_position_verified']
        assert {(event['username'], event['stage']) for event in confirmations} == {
            (player['username'], stage) for player in players for stage in ('out', 'back')}
        assert case['world_bytes_after'] > case['world_bytes_before']
        assert 'Test passed' in case['marker_restore']
        phases = [(datetime.fromisoformat(event['time']).timestamp(), event['name']) for event in events if event['event'] == 'phase']
        assert [phase for _, phase in phases] == ['new_chunks', 'existing_chunks', 'combat']
        end = datetime.fromisoformat(complete[0]['time']).timestamp()
        selected = [sample for sample in samples if sample['case'] == case['name'] and phases[0][0] <= sample['time'] < end and 'tps' in sample]
        assert len(selected) >= 15, f"Insufficient action samples for {case['name']}"
        tps = [numbers(sample['tps'])[0] for sample in selected]
        mspt = [numbers(sample['mspt'])[0] for sample in selected]
        peak_ticks = [numbers(sample['mspt'])[2] for sample in selected]
        cpu = []
        for previous, current in zip(selected, selected[1:]):
            delta = int(current['cpu_stat']['usage_usec']) - int(previous['cpu_stat']['usage_usec'])
            assert delta >= 0
            cpu.append(delta / 1_000_000 / (current['time'] - previous['time']))
        case_samples = [sample for sample in samples if sample['case'] == case['name']]
        heap_text = [sample['heap'] for sample in case_samples if 'heap' in sample] + [case['heap_after_players']]
        heap_used = [int(re.search(r'heap\s+total reserved \d+K, committed \d+K, used (\d+)K', text).group(1)) * 1024 for text in heap_text]
        row = {'case': case['name'], 'players': case['players'],
               'cold_ready_seconds': case['cold_ready_seconds'], 'warm_ready_seconds': case['warm_ready_seconds'],
               'save_seconds': case['save_seconds'], 'stop_seconds': case['stop_seconds'],
               'action_samples': len(selected), 'minimum_tps_1m': min(tps),
               'p95_mean_mspt_5s': p95(mspt), 'maximum_tick_ms': max(peak_ticks),
               'mean_cpu_cores': statistics.mean(cpu), 'peak_cpu_cores': max(cpu),
               'peak_container_gib': max(sample.get('memory_bytes', 0) for sample in case_samples) / 1024**3,
               'peak_java_rss_gib': max(sample.get('java_rss_bytes', 0) for sample in case_samples) / 1024**3,
               'peak_sampled_heap_gib': max(heap_used) / 1024**3,
               'world_growth_mib': (case['world_bytes_after'] - case['world_bytes_before']) / 1024**2,
               'mib_per_player_hour': sum(player['bytes_read'] + player['bytes_written'] for player in players) / sum(player['active_seconds'] for player in players) * 3600 / 1024**2,
               'confirmed_hits': sum(player['confirmed_hits'] for player in players),
               'performance_pass': min(tps) >= 19 and p95(mspt) <= 50}
        row['phases'] = {}
        waits = [event['seconds'] for event in events if event['event'] == 'chunk_wait'
                 and phases[0][0] <= datetime.fromisoformat(event['time']).timestamp() < end]
        row['action_chunk_wait_player_seconds'] = sum(waits)
        row['longest_action_chunk_wait_seconds'] = max(waits, default=0)
        for index, (start, name) in enumerate(phases):
            stop = phases[index + 1][0] if index + 1 < len(phases) else end
            phase_samples = [sample for sample in selected if start <= sample['time'] < stop]
            assert len(phase_samples) >= 3, f'Insufficient samples for {name}'
            row['phases'][name] = {'seconds': stop - start, 'samples': len(phase_samples),
                'minimum_tps_1m': min(numbers(sample['tps'])[0] for sample in phase_samples),
                'p95_mean_mspt_5s': p95([numbers(sample['mspt'])[0] for sample in phase_samples])}
        rows.append(row)
    qualified = [count for count in (1, 2, 4, 8) if all(row['performance_pass'] for row in rows if row['players'] == count)]
    return {'cases': rows, 'qualified_player_counts': qualified,
            'app_samples': len(samples), 'maximum_app_seconds': max(sample['app_seconds'] for sample in samples),
            'minimum_available_gib': min(sample['available_bytes'] for sample in samples) / 1024**3,
            'elapsed_minutes': (summary['finished_at'] - summary['started_at']) / 60}


if __name__ == '__main__':
    if sys.argv[1:] == ['--self-test']:
        assert numbers('\x1b[33mTPS from last 1m, 5m, 15m: \x1b[32m*20.0, 19.9, 19.8') == [20, 19.9, 19.8]
        assert numbers('Server tick times (avg/min/max) from last 5s, 10s, 1m:\n◴ 23.3/0.2/825.1, 13.7/0.2/825.1, 9.9/0.2/825.1')[2] == 825.1
        assert p95(list(range(1, 101))) == 95
        print('Metric parsing checks passed')
    else:
        print(json.dumps(summarize(Path(sys.argv[1])), indent=2))
