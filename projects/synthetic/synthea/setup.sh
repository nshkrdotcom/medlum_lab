#!/usr/bin/env bash
set -euo pipefail

# Synthea Setup Script - Uses pre-built JAR

echo "=== Synthea Setup ==="

# Check Java version
if ! command -v java &> /dev/null; then
    echo "Error: Java is required. Install Java 11+ (JRE is sufficient for running)"
    exit 1
fi

JAVA_VERSION=$(java -version 2>&1 | head -1 | cut -d'"' -f2 | cut -d'.' -f1)
echo "Java version: $JAVA_VERSION (OK)"

JAR_URL="https://github.com/synthetichealth/synthea/releases/download/master-branch-latest/synthea-with-dependencies.jar"
JAR_FILE="synthea/synthea-with-dependencies.jar"

mkdir -p synthea data

# Download pre-built JAR if not present
if [[ ! -f "$JAR_FILE" ]]; then
    echo "Downloading pre-built Synthea JAR..."
    curl -L -o "$JAR_FILE" "$JAR_URL"
    echo "Downloaded: $JAR_FILE"
else
    echo "Synthea JAR already present: $JAR_FILE"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Generate patients with:"
echo "  ./generate.sh 100 Massachusetts"
echo ""
echo "Or directly:"
echo "  java -jar synthea/synthea-with-dependencies.jar -p 100 Massachusetts"
