#!/usr/bin/env python3
"""Verify the complete pinned React reference and the native counterpart matrix."""
import argparse
import json
from pathlib import Path
import re

parser = argparse.ArgumentParser()
parser.add_argument('--upstream-report', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
manifest = json.loads((root / 'Compatibility/react-tests.json').read_text())
assert manifest['commit'] == '86f95f2841c15474f08fcfc8e040c078dd2ab093'
tests = manifest['tests']
assert len(tests) == len({case['id'] for case in tests}) == 68
generated = (root / 'Tests/CCStateSwiftUITests/ReactInventory.swift').read_text()
assert re.findall(r'id: "([a-z-]+\.[0-9]+)"', generated) == [case['id'] for case in tests]
case_sources = '\n'.join(p.read_text() for p in (root / 'Tests/CCStateSwiftUITests').glob('*ReferenceCases.swift'))
implemented = set(re.findall(r'"([a-z-]+\.[0-9]+)"', case_sources))
assert {case['id'] for case in tests} <= implemented, 'A reference case has no native implementation'
if args.upstream_report:
    report = json.loads(args.upstream_report.read_text())
    assert report['success'] and report['numFailedTests'] == 0 and report['numPendingTests'] == 0
    actual = set()
    for suite in report['testResults']:
        if '/packages/react/src/' not in suite['name']:
            continue
        path = 'packages/react/src/' + suite['name'].split('/src/', 1)[1]
        for case in suite['assertionResults']:
            assert case['status'] == 'passed'
            actual.add((path, case['fullName']))
    assert actual == {(case['file'], case['name']) for case in tests}, 'React reference cases drifted'
print('Verified all 68 pinned React cases and their SwiftUI counterpart IDs')
