#!/bin/bash
# Run all eleven tests. Exits non-zero if any test fails.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ELEVEN="$REPO_ROOT/core/eleven"

fail=0
pass=0
failed_names=()

run_one() {
    local test="$1"
    local name="$(basename "$test" .py)"
    printf "• %-30s " "$name"
    # Tests with a python3 shebang on line 1 run as CPython (they shell
    # out to `eleven` themselves). Everything else runs through `eleven
    # test` (MicroPython driving an app via the test host).
    local output
    if head -n1 "$test" | grep -q "python3"; then
        output=$(python3 "$test" 2>&1)
    else
        output=$("$ELEVEN" test "$test" 2>&1)
    fi
    if [[ $? -eq 0 ]]; then
        echo "PASS"
        pass=$((pass+1))
    else
        echo "FAIL"
        echo "$output" | sed 's/^/    /'
        fail=$((fail+1))
        failed_names+=("$name")
    fi
}

for test in "$SCRIPT_DIR"/test_*.py; do
    run_one "$test"
done

echo
echo "$pass passed, $fail failed"
if [[ $fail -gt 0 ]]; then
    echo "failed:"
    printf '  %s\n' "${failed_names[@]}"
    exit 1
fi
