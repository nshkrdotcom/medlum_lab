#!/usr/bin/env bash
set -euo pipefail

# FHIR-PYrate Setup Script

echo "=== FHIR-PYrate Setup ==="

mkdir -p data

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
echo ""
echo "Test with public FHIR server:"
echo "  python src/example.py"
