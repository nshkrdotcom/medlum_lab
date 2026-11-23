#!/usr/bin/env bash
set -euo pipefail

# CheXpert Setup Script

DATA_DIR="./data"

echo "=== CheXpert Setup ==="
echo ""
echo "CheXpert requires manual download from Stanford:"
echo "  https://stanfordmlgroup.github.io/competitions/chexpert/"
echo ""
echo "1. Register for access"
echo "2. Download CheXpert-v1.0-small.zip (11GB) or full version (439GB)"
echo "3. Extract to $DATA_DIR/"
echo ""

mkdir -p "$DATA_DIR"

# Check if data exists
if [[ -d "$DATA_DIR/train" ]]; then
    echo "Data found in $DATA_DIR"
    echo "Train images: $(find $DATA_DIR/train -name '*.jpg' | wc -l)"
else
    echo "No data found. Please download manually."
fi

echo ""
echo "Alternative: MIMIC-CXR (PhysioNet access)"
echo "  https://physionet.org/content/mimic-cxr/"
echo ""

if [[ ! -d "venv" ]]; then
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
fi

echo "Setup complete."
