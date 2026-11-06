#!/usr/bin/env python3
"""Record the expanded, unchanged ccstate-react reference cases."""
import json
from pathlib import Path
import sys

report = json.loads(Path(sys.argv[1]).read_text())
assert report['success'] and report['numFailedTests'] == 0
root = Path(__file__).resolve().parent.parent
cases = []
for suite in report['testResults']:
    if '/packages/react/src/' not in suite['name']:
        continue
    path = 'packages/react/src/' + suite['name'].split('/src/', 1)[1]
    group = Path(path).name.removesuffix('.test.tsx')
    for index, case in enumerate(suite['assertionResults'], 1):
        cases.append(dict(id=f'{group}.{index:02}', file=path, name=case['fullName']))
cases.sort(key=lambda c: c['id'])
manifest = dict(repository='https://github.com/e7h4n/ccstate',
                commit='86f95f2841c15474f08fcfc8e040c078dd2ab093', version='6.1.0', tests=cases)
(root / 'Compatibility/react-tests.json').write_text(json.dumps(manifest, indent=2) + '\n')
lines = ['// Generated from the pinned, unchanged ccstate-react test report.',
         'let reactReferenceCases: [ReactReferenceCase] = [']
for case in cases:
    lines.append(f'    ReactReferenceCase(id: {json.dumps(case["id"])}, name: {json.dumps(case["name"])}),')
lines.append(']')
(root / 'Tests/CCStateSwiftUITests/ReactInventory.swift').write_text('\n'.join(lines) + '\n')
print(f'Imported {len(cases)} passing React reference cases')
