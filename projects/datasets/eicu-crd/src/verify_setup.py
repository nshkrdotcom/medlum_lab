"""
eICU-CRD Setup Verification

Verifies setup and provides instructions for downloading eICU data.
"""

import os
import sys
from pathlib import Path


def check_physionet_credentials():
    """Check for PhysioNet credentials."""
    home = Path.home()
    netrc_path = home / ".netrc"
    physionetrc_path = home / ".physionetrc"

    if netrc_path.exists():
        with open(netrc_path) as f:
            if "physionet.org" in f.read():
                return True, "Found credentials in ~/.netrc"

    if physionetrc_path.exists():
        return True, "Found credentials in ~/.physionetrc"

    if os.environ.get("PHYSIONET_USER") and os.environ.get("PHYSIONET_PASS"):
        return True, "Found credentials in environment variables"

    return False, "No PhysioNet credentials found"


def check_data_directory():
    """Check if data directory has eICU files."""
    script_dir = Path(__file__).parent
    data_dir = script_dir.parent / "data"

    if not data_dir.exists():
        return False, f"Data directory not found: {data_dir}"

    csv_files = list(data_dir.glob("*.csv")) + list(data_dir.glob("*.csv.gz"))
    if csv_files:
        return True, f"Found {len(csv_files)} data files"

    return False, "No eICU data found"


def main():
    print("=" * 60)
    print("eICU-CRD Setup Verification")
    print("=" * 60)

    # Check packages
    print("\n1. Checking Python packages...")
    required = ["pandas", "pyarrow", "polars", "tqdm"]
    for pkg in required:
        try:
            __import__(pkg)
            print(f"   ✓ {pkg}")
        except ImportError:
            print(f"   ✗ {pkg}")

    # Check credentials
    print("\n2. Checking PhysioNet credentials...")
    has_creds, msg = check_physionet_credentials()
    print(f"   {'✓' if has_creds else '✗'} {msg}")

    if not has_creds:
        print("""
   Same credentials as MIMIC-IV (PhysioNet account required).
   Request access at: https://physionet.org/content/eicu-crd/
""")

    # Check data
    print("\n3. Checking eICU data...")
    has_data, msg = check_data_directory()
    print(f"   {'✓' if has_data else '○'} {msg}")

    if has_creds and not has_data:
        print("""
   To download:
   wget -r -N -c -np --user $PHYSIONET_USER --ask-password \\
       https://physionet.org/files/eicu-crd/2.0/ -P ./data
""")

    print("\n" + "=" * 60)
    if has_creds and has_data:
        print("STATUS: ✓ eICU-CRD ready!")
    elif has_creds:
        print("STATUS: ○ Credentials OK, download data")
    else:
        print("STATUS: 🔐 Need PhysioNet credentials")
    print("=" * 60)

    return 0 if (has_creds and has_data) else 1


if __name__ == "__main__":
    sys.exit(main())
