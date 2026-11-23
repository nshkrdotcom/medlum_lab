#!/usr/bin/env bash
set -euo pipefail

# eICU-CRD Setup Script

EICU_VERSION="2.0"
DATA_DIR="./data"

echo "=== eICU-CRD Setup ==="
echo ""
echo "Prerequisites: Same as MIMIC-IV (PhysioNet credentialed access)"
echo ""

mkdir -p "$DATA_DIR"

echo "To download eICU-CRD, run:"
echo ""
echo "  wget -r -N -c -np --user \$PHYSIONET_USER --ask-password \\"
echo "    https://physionet.org/files/eicu-crd/${EICU_VERSION}/ \\"
echo "    -P $DATA_DIR"
echo ""

if [[ ! -d "venv" ]]; then
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
fi

echo "Setup complete."
