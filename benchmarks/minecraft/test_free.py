"""Check the native metric contract and prevent incomplete evidence from passing."""
from datetime import datetime, timezone
from pathlib import Path
from tempfile import TemporaryDirectory
import zipfile
from qualify import game_ticks, measurements, native_ticks, simultaneous_play, jar_contents

response = ('The game is running normallyTarget tick rate: 20.0 per second.\n'
            '\x1b[0mAverage time per tick: 0.1ms (Target: 50.0ms)'
            'Percentiles: P50: 0.1ms P95: 0.1ms P99: 0.2ms. Sample: 100')
assert native_ticks(response)['tick_p95_ms'] == 0.1
assert game_ticks('The game time is 3381 tick(s)') == 3381
for invalid in [response.replace('20.0', '10.0'), response.replace('Sample: 100', 'Sample: 1'), response.replace('P95: 0.1', 'P95: 2.0')]:
    try:
        native_ticks(invalid)
    except AssertionError:
        pass
    else:
        raise AssertionError('Invalid native tick measurements must fail')

def timestamp(seconds):
    return datetime.fromtimestamp(seconds, timezone.utc).isoformat()

samples = [{'time': second, 'game_tick_time': second, 'game_ticks': second * 20,
            'game_tick_query_seconds': 0.02, 'tick_p95_ms': 20, 'tick_p99_ms': 30,
            'memory_bytes': 1024, 'cpu_stat': {'usage_usec': second * 500000}} for second in range(0, 121, 5)]
events = [{'time': timestamp(second), 'event': 'phase', 'name': name}
          for second, name in [(0, 'new_chunks'), (20, 'existing_chunks'), (40, 'combat'), (100, 'survival')]]
events += [{'time': timestamp(10), 'event': 'chunk_wait', 'seconds': 0.1}]
events += [{'time': timestamp(second), 'event': 'server_position_verified', 'seconds': 0.1} for second in [20, 40, 110]]
events += [{'time': timestamp(second), 'event': 'server_block_verified', 'seconds': 0.1} for second in [105, 106]]
events += [{'time': timestamp(120), 'event': 'complete', 'observations': [{
    'confirmed_hits': 1, 'survival': {'block_confirmed': True, 'walked_blocks': 5, 'vertical_change': 0}, 'bytes_read': 100, 'bytes_written': 10}]}]
assert measurements(samples, events)['performance_pass']
assert not measurements(samples[:10], events)['performance_pass'], 'A short pilot cannot pass without a full TPS window'
for changed in ['tick_p95_ms', 'game_tick_query_seconds']:
    bad = [{**sample, changed: 2000} for sample in samples]
    assert not measurements(bad, events)['performance_pass'], f'{changed} failure must not pass'
try:
    measurements(samples, events[:-1])
except AssertionError:
    pass
else:
    raise AssertionError('Missing action completion must fail')

# Separate short overlaps must not add up to a passing minute.
cases = [{'name': f'r{repeat}-i{index}', 'repeat': repeat} for repeat in (1, 2) for index in (1, 2)]
rows = [{'case': case['name'], 'phase': phase, 'started_at': 0, 'finished_at': 30}
        for case in cases for phase in ('fresh', 'populated')]
overlap = simultaneous_play(rows, cases, 2, 2)
assert sum(row['seconds'] for row in overlap) == 120
assert not all(row['seconds'] >= 60 for row in overlap)
assert all(row['seconds'] == 120 for row in simultaneous_play([{**row, 'finished_at': 120} for row in rows], cases, 2, 2))
assert simultaneous_play(rows[:-1], cases, 2, 2)[-1]['seconds'] == 0

with TemporaryDirectory() as temporary:
    a, b = [Path(temporary) / name for name in ('a.jar', 'b.jar')]
    for path, year in ((a, 2025), (b, 2026)):
        with zipfile.ZipFile(path, 'w') as jar:
            jar.writestr(zipfile.ZipInfo('META-INF/MANIFEST.MF', (year, 1, 1, 0, 0, 0)), 'same classpath')
    assert a.read_bytes() != b.read_bytes() and jar_contents(a) == jar_contents(b)
    with zipfile.ZipFile(b, 'w') as jar:
        jar.writestr('META-INF/MANIFEST.MF', 'different classpath')
    assert jar_contents(a) != jar_contents(b)
print('Free-profile metric and acceptance checks passed')
