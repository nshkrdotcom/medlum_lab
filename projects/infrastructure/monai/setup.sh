#!/usr/bin/env bash
set -euo pipefail

# MONAI Setup Script

echo "=== MONAI Setup ==="

# Check for CUDA
if command -v nvidia-smi &> /dev/null; then
    echo "CUDA detected:"
    nvidia-smi --query-gpu=name,memory.total --format=csv
    CUDA_AVAILABLE=1
else
    echo "No CUDA detected, will use CPU"
    CUDA_AVAILABLE=0
fi

mkdir -p data models

if [[ ! -d "venv" ]]; then
    echo "Creating Python virtual environment..."
    python3 -m venv venv
fi

source venv/bin/activate
pip install --upgrade pip

# Install PyTorch (CUDA or CPU)
if [[ "$CUDA_AVAILABLE" -eq 1 ]]; then
    pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121
else
    pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
fi

pip install -r requirements.txt

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Activate environment: source venv/bin/activate"
echo ""
echo "Download sample dataset:"
echo "  python -c \"from monai.apps import download_and_extract; download_and_extract('https://msd-for-monai.s3-us-west-2.amazonaws.com/Task09_Spleen.tar', 'data/')\""
