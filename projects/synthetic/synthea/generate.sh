#!/usr/bin/env bash
set -euo pipefail

# Synthea Patient Generation Script

POPULATION=${1:-10}
STATE=${2:-"Massachusetts"}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JAR_FILE="$SCRIPT_DIR/synthea/synthea-with-dependencies.jar"
OUTPUT_DIR="$SCRIPT_DIR/data"

echo "=== Generating $POPULATION patients in $STATE ==="

if [[ ! -f "$JAR_FILE" ]]; then
    echo "Error: Synthea JAR not found. Run ./setup.sh first."
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Run Synthea
cd "$SCRIPT_DIR"
java -jar "$JAR_FILE" \
    -p "$POPULATION" \
    --exporter.baseDirectory "$OUTPUT_DIR" \
    "$STATE"

echo ""
echo "Generated data in $OUTPUT_DIR/"
ls -la "$OUTPUT_DIR/"
