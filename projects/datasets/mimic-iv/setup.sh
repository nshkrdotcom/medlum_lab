#!/usr/bin/env bash
set -euo pipefail

# MIMIC-IV Setup Script
# Requires PhysioNet credentialed access

MIMIC_VERSION="2.2"
DATA_DIR="./data"

echo "=== MIMIC-IV Setup ==="
echo ""
echo "Prerequisites:"
echo "  1. PhysioNet account with credentialed access"
echo "  2. Completed CITI training"
echo "  3. Signed MIMIC-IV data use agreement"
echo ""

# Check for wget
if ! command -v wget &> /dev/null; then
    echo "Error: wget is required. Install with: apt install wget"
    exit 1
fi

# Check for credentials file
if [[ ! -f ~/.physionetrc ]] && [[ ! -f ./.physionet_credentials ]]; then
    echo "PhysioNet credentials not found."
    echo ""
    echo "Option 1: Create ~/.physionetrc with:"
    echo "  machine physionet.org"
    echo "  login YOUR_USERNAME"
    echo "  password YOUR_PASSWORD"
    echo ""
    echo "Option 2: Set environment variables:"
    echo "  export PHYSIONET_USER=your_username"
    echo "  export PHYSIONET_PASS=your_password"
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

mkdir -p "$DATA_DIR"/{hosp,icu,note}

echo ""
echo "To download MIMIC-IV, run:"
echo ""
echo "  wget -r -N -c -np --user \$PHYSIONET_USER --ask-password \\"
echo "    https://physionet.org/files/mimiciv/${MIMIC_VERSION}/ \\"
echo "    -P $DATA_DIR"
echo ""
echo "Or use the physionet-build tool:"
echo "  pip install wfdb"
echo "  wfdb-client download --all mimiciv/${MIMIC_VERSION}"
echo ""

# Create Python environment
if [[ ! -d "venv" ]]; then
    echo "Creating Python virtual environment..."
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
    echo "Virtual environment created. Activate with: source venv/bin/activate"
fi

echo ""
echo "Setup complete. See README.md for next steps."
