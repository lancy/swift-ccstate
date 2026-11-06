#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch_path="${CCSTATE_SCRATCH_PATH:-$repo_root/.build}"
module_path="$(swift build --scratch-path "$scratch_path" --show-bin-path)"
module_args=()
if [[ -d "$module_path/Modules" ]]; then
    module_args=(-I "$module_path/Modules")
else
    # Xcode-backed SwiftPM places modules in Products/Debug.
    module_args=(-I "$module_path")
fi
fixture_dir="$repo_root/Compatibility/negative"
diagnostic_dir="$(mktemp -d)"
trap 'rm -rf "$diagnostic_dir"' EXIT

# A broken import, compiler, deployment target, or actor annotation must fail here,
# rather than falsely satisfying the two negative checks below.
swiftc -typecheck -swift-version 6 "${module_args[@]}" "$fixture_dir/positive-control.swift"
swiftc -typecheck -swift-version 6 "${module_args[@]}" "$repo_root/Compatibility/positive/swiftui.swift"
for fixture in set-computed watch-command; do
    if swiftc -typecheck -swift-version 6 "${module_args[@]}" "$fixture_dir/$fixture.swift" \
        >"$diagnostic_dir/$fixture.log" 2>&1; then
        echo "Expected $fixture.swift to fail type checking" >&2
        exit 1
    fi
    if ! grep -Eq 'cannot convert value of type|no exact matches|requires that|cannot convert.*Computed|cannot convert.*Command' \
        "$diagnostic_dir/$fixture.log"; then
        cat "$diagnostic_dir/$fixture.log" >&2
        exit 1
    fi
    echo "Verified compile-time rejection: $fixture"
done
