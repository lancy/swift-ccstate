#!/usr/bin/env bash
set -euo pipefail

reference_root="${1:?Pass a checkout of e7h4n/ccstate}"
report_path="${2:?Pass an absolute output JSON report path}"
expected_revision=86f95f2841c15474f08fcfc8e040c078dd2ab093
actual_revision="$(git -C "$reference_root" rev-parse HEAD)"
if [[ "$actual_revision" != "$expected_revision" ]]; then
    echo "Expected upstream $expected_revision, found $actual_revision" >&2
    exit 1
fi
workspace_dir="$(mktemp -d)"
workspace_file="$workspace_dir/ccstate.workspace.json"
trap 'rm -rf "$workspace_dir"' EXIT
python3 - "$workspace_file" "$reference_root" <<'PY'
import json
from pathlib import Path
import sys
Path(sys.argv[1]).write_text(json.dumps([str(Path(sys.argv[2]).resolve() / 'packages/ccstate')]))
PY
cd "$reference_root"
pnpm install --frozen-lockfile --ignore-scripts
pnpm -F ccstate build
pnpm exec vitest run --workspace "$workspace_file" --maxWorkers=4 --minWorkers=1 \
    --reporter=json --outputFile="$report_path"
