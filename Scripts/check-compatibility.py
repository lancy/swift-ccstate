#!/usr/bin/env python3
"""Check the pinned test inventory; optionally compare an actual upstream run."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re

parser = argparse.ArgumentParser()
parser.add_argument('--upstream-report', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
manifest = json.loads((root / 'Compatibility/upstream-tests.json').read_text())
tests = manifest['tests']
assert manifest['commit'] == '86f95f2841c15474f08fcfc8e040c078dd2ab093'
assert len(tests) == len({t['id'] for t in tests}) == 211
counts = Counter(t['kind'] for t in tests)
assert counts == {'behavioral-port': 205, 'compile-time-enforcement': 2,
                  'native-task-adaptation': 3, 'javascript-toolchain-only': 1}, counts
generated = (root / 'Tests/CCStateTests/UpstreamInventory.swift').read_text()
actual_ids = re.findall(r'id: "([a-z-]+\.[0-9]+)"', generated)
expected_ids = [t['id'] for t in tests if t['kind'] != 'javascript-toolchain-only']
assert actual_ids == expected_ids, 'The generated Swift matrix differs from the pinned inventory'
for fixture in ('set-computed', 'watch-command', 'positive-control'):
    assert (root / f'Compatibility/negative/{fixture}.swift').is_file()
if args.upstream_report:
    report = json.loads(args.upstream_report.read_text())
    assert report['success'] and report['numFailedTests'] == 0 and report['numPendingTests'] == 0
    actual = set()
    for suite in report['testResults']:
        path = 'packages/ccstate/src/' + suite['name'].split('/src/', 1)[1]
        for case in suite['assertionResults']:
            assert case['status'] == 'passed'
            actual.add((path, case['fullName']))
    assert actual == {(t['file'], t['name']) for t in tests}, 'Upstream tests drifted'
print(f'Pinned inventory verified: {dict(sorted(counts.items()))}')
