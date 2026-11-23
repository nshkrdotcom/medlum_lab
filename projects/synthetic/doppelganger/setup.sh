#!/usr/bin/env bash
set -euo pipefail

# DoppelGANger Setup Script

echo "=== DoppelGANger Setup ==="

mkdir -p data models

if [[ ! -d "venv" ]]; then
    echo "Creating Python virtual environment..."
    python3 -m venv venv
fi

source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Activate environment: source venv/bin/activate"
echo "Run example: python src/example.py"
