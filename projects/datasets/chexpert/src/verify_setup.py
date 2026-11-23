"""
CheXpert Setup Verification

Verifies setup and provides instructions for downloading CheXpert data.
"""

import os
import sys
from pathlib import Path


def check_data_directory():
    """Check if data directory has CheXpert files."""
    script_dir = Path(__file__).parent
    data_dir = script_dir.parent / "data"

    if not data_dir.exists():
        return False, f"Data directory not found: {data_dir}"

    # Check for train/valid directories
    train_dir = data_dir / "train"
    valid_dir = data_dir / "valid"

    if train_dir.exists() or valid_dir.exists():
        img_count = len(list(data_dir.rglob("*.jpg")))
        return True, f"Found CheXpert data ({img_count} images)"

    # Check for CSV labels
    csv_files = list(data_dir.glob("*.csv"))
    if csv_files:
        return True, f"Found label files: {[f.name for f in csv_files]}"

    return False, "No CheXpert data found"


def main():
    print("=" * 60)
    print("CheXpert Setup Verification")
    print("=" * 60)

    # Check packages
    print("\n1. Checking Python packages...")
    required = ["pandas", "numpy", "torch", "torchvision", "PIL", "cv2", "pydicom"]
    for pkg in required:
        pkg_import = "PIL" if pkg == "PIL" else ("cv2" if pkg == "cv2" else pkg)
        try:
            if pkg == "PIL":
                from PIL import Image
            elif pkg == "cv2":
                import cv2
            else:
                __import__(pkg)
            print(f"   ✓ {pkg}")
        except ImportError:
            print(f"   ✗ {pkg}")

    # Check data
    print("\n2. Checking CheXpert data...")
    has_data, msg = check_data_directory()
    print(f"   {'✓' if has_data else '○'} {msg}")

    if not has_data:
        print("""
   CheXpert requires Stanford research agreement:

   1. Go to: https://stanfordmlgroup.github.io/competitions/chexpert/
   2. Register and agree to Stanford Research Use Agreement
   3. Download CheXpert-v1.0-small.zip (11GB) or full version (439GB)
   4. Extract to ./data/

   Alternative: Use MIMIC-CXR (via PhysioNet) which is similar:
   https://physionet.org/content/mimic-cxr/
""")

    print("\n" + "=" * 60)
    if has_data:
        print("STATUS: ✓ CheXpert ready!")
    else:
        print("STATUS: 🔐 Need Stanford agreement (see instructions)")
    print("=" * 60)

    return 0 if has_data else 1


if __name__ == "__main__":
    sys.exit(main())
