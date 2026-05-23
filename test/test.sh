#!/usr/bin/env bash
# test/test.sh — test runner for nurl_app.nu
#
# Usage:
#   ./test/test.sh                    # run all pure-logic tests
#   NURL_NET_TESTS=1 ./test/test.sh   # run all tests including network tests
#
# Each test file is a standalone NURL program that returns 0 (pass) or 1 (fail).
# Network tests (test_net_*.nu) are skipped unless NURL_NET_TESTS=1 is set.

set -euo pipefail

cd "$(dirname "$0")/.."

PASS=0
FAIL=0
SKIP=0
FAILED_FILES=()

# Determine how to compile and run NURL test files.
# Options: nurlc directly, or ./nurl.sh wrapper.
if command -v nurlc &>/dev/null; then
    RUN_TEST() {
        local src="$1"
        local tmpdir
        tmpdir=$(mktemp -d)
        local bin="$tmpdir/test_bin"
        nurlc "$src" -o "$bin" 2>&1
        "$bin"
        local rc=$?
        rm -rf "$tmpdir"
        return $rc
    }
elif [ -x ./nurl.sh ]; then
    RUN_TEST() {
        local src="$1"
        local tmpdir
        tmpdir=$(mktemp -d)
        local bin="$tmpdir/test_bin"
        ./nurl.sh "$src" "$bin" 2>&1
        "$bin"
        local rc=$?
        rm -rf "$tmpdir"
        return $rc
    }
else
    echo "ERROR: No NURL compiler found. Install nurlc or provide ./nurl.sh"
    exit 1
fi

run_file() {
    local f="$1"
    local name
    name=$(basename "$f" .nu)
    
    if RUN_TEST "$f"; then
        echo "  PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $name"
        FAIL=$((FAIL + 1))
        FAILED_FILES+=("$name")
    fi
}

echo "=== nurl_app test suite ==="

# Pure-logic tests (always run)
for f in test/test_*.nu; do
    [ -f "$f" ] || continue
    # Skip network tests unless enabled
    case "$(basename "$f")" in
        test_net_*) continue ;;
    esac
    run_file "$f"
done

# Network tests (gated)
if [ "${NURL_NET_TESTS:-0}" = "1" ]; then
    echo ""
    echo "--- Network tests (NURL_NET_TESTS=1) ---"
    for f in test/test_net_*.nu; do
        [ -f "$f" ] || continue
        run_file "$f"
    done
else
    for f in test/test_net_*.nu; do
        [ -f "$f" ] || continue
        echo "  SKIP: $(basename "$f" .nu) (set NURL_NET_TESTS=1 to enable)"
        SKIP=$((SKIP + 1))
    done
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed, $SKIP skipped ==="

if [ "$FAIL" -gt 0 ]; then
    echo "Failed: ${FAILED_FILES[*]}"
    exit 1
fi
exit 0
