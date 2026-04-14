#!/bin/bash
# Run all eleven tests. Exits non-zero if any test fails.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ELEVEN="$REPO_ROOT/core/eleven"

fail=0
pass=0
failed_names=()

for test in "$SCRIPT_DIR"/test_*.py; do
    name="$(basename "$test" .py)"
    printf "• %-30s " "$name"
    if output=$("$ELEVEN" test "$test" 2>&1); then
        echo "PASS"
        pass=$((pass+1))
    else
        echo "FAIL"
        echo "$output" | sed 's/^/    /'
        fail=$((fail+1))
        failed_names+=("$name")
    fi
done

echo
echo "$pass passed, $fail failed"
if [[ $fail -gt 0 ]]; then
    echo "failed:"
    printf '  %s\n' "${failed_names[@]}"
    exit 1
fi
