#!/usr/bin/env bash
set -euo pipefail

# MedCoder Setup Script

echo "=== MedCoder Setup ==="

mkdir -p data/icd10 models

if [[ ! -d "venv" ]]; then
    echo "Creating Python virtual environment..."
    python3 -m venv venv
fi

source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# Download spaCy model
python -m spacy download en_core_web_sm

echo ""
echo "=== Downloading ICD-10 codes ==="
echo ""

# Download ICD-10-CM codes from CMS (2024 version)
ICD10_URL="https://www.cms.gov/files/zip/2024-code-descriptions-tabular-order.zip"
if [[ ! -f "data/icd10/icd10cm_codes.txt" ]]; then
    echo "Downloading ICD-10-CM codes..."
    echo "Manual download required from: $ICD10_URL"
    echo "Extract and place in data/icd10/"
else
    echo "ICD-10 codes already present."
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Activate environment: source venv/bin/activate"
