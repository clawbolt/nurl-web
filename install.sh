#!/usr/bin/env bash
# install.sh — copy nurl_app.nu into a NURL checkout's stdlib/ext/.
#
# Usage:  ./install.sh [/path/to/nurl-checkout]
#
# If no path is given, tries $NURL_HOME, then ../nurl, then /opt/nurl.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve target NURL checkout
if [[ $# -ge 1 ]]; then
    NURL_ROOT="$1"
elif [[ -n "${NURL_HOME:-}" ]]; then
    NURL_ROOT="$NURL_HOME"
elif [[ -d "$SCRIPT_DIR/../nurl/stdlib/ext" ]]; then
    NURL_ROOT="$(cd "$SCRIPT_DIR/../nurl" && pwd)"
elif [[ -d "/opt/nurl/stdlib/ext" ]]; then
    NURL_ROOT="/opt/nurl"
else
    echo "ERROR: can't find a NURL checkout." >&2
    echo "Usage: $0 /path/to/nurl" >&2
    exit 1
fi

DEST="$NURL_ROOT/stdlib/ext"
if [[ ! -d "$DEST" ]]; then
    echo "ERROR: $DEST does not exist — is this a valid NURL checkout?" >&2
    exit 1
fi

# Copy framework
echo "Installing stdlib/ext/nurl_app.nu → $DEST/nurl_app.nu"
cp "$SCRIPT_DIR/stdlib/ext/nurl_app.nu" "$DEST/nurl_app.nu"

# Copy examples
EXAMPLE_DEST="$NURL_ROOT/examples"
if [[ -d "$EXAMPLE_DEST" ]]; then
    echo "Installing examples/web_app.nu     → $EXAMPLE_DEST/web_app.nu"
    cp "$SCRIPT_DIR/examples/web_app.nu" "$EXAMPLE_DEST/web_app.nu"
    echo "Installing examples/web_minimal.nu → $EXAMPLE_DEST/web_minimal.nu"
    cp "$SCRIPT_DIR/examples/web_minimal.nu" "$EXAMPLE_DEST/web_minimal.nu"
else
    echo "NOTE: $EXAMPLE_DEST not found, skipping example copy."
fi

echo ""
echo "Done. Try it:"
echo "  cd $NURL_ROOT && ./nurl.sh examples/web_minimal.nu"
