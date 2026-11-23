"""
MIMIC-IV Setup Verification

This script verifies that the MIMIC-IV setup is ready and provides
instructions for downloading the data once you have PhysioNet credentials.
"""

import os
import sys
from pathlib import Path


def check_physionet_credentials():
    """Check for PhysioNet credentials."""
    home = Path.home()

    # Check for .netrc or physionetrc
    netrc_path = home / ".netrc"
    physionetrc_path = home / ".physionetrc"

    if netrc_path.exists():
        with open(netrc_path) as f:
            content = f.read()
            if "physionet.org" in content:
                return True, "Found credentials in ~/.netrc"

    if physionetrc_path.exists():
        return True, "Found credentials in ~/.physionetrc"

    # Check environment variables
    if os.environ.get("PHYSIONET_USER") and os.environ.get("PHYSIONET_PASS"):
        return True, "Found credentials in environment variables"

    return False, "No PhysioNet credentials found"


def check_data_directory():
    """Check if data directory has MIMIC-IV files."""
    script_dir = Path(__file__).parent
    data_dir = script_dir.parent / "data"

    if not data_dir.exists():
        return False, f"Data directory not found: {data_dir}"

    # Look for MIMIC-IV subdirectories
    expected_dirs = ["hosp", "icu"]
    found = []
    for d in expected_dirs:
        if (data_dir / d).exists():
            found.append(d)

    if found:
        return True, f"Found MIMIC-IV modules: {', '.join(found)}"

    return False, "No MIMIC-IV data found (run download after getting credentials)"


def main():
    print("=" * 60)
    print("MIMIC-IV Setup Verification")
    print("=" * 60)

    # Check Python packages
    print("\n1. Checking Python packages...")
    required = ["pandas", "pyarrow", "sqlalchemy", "nltk", "spacy", "polars"]
    missing = []
    for pkg in required:
        try:
            __import__(pkg)
            print(f"   ✓ {pkg}")
        except ImportError:
            print(f"   ✗ {pkg} (missing)")
            missing.append(pkg)

    # Check wfdb separately (may have compatibility issues)
    try:
        import importlib.util
        if importlib.util.find_spec("wfdb"):
            print(f"   ✓ wfdb (installed)")
        else:
            print(f"   ○ wfdb (optional)")
    except Exception:
        print(f"   ○ wfdb (optional, compatibility issue)")

    if missing:
        print(f"\n   Install missing: pip install {' '.join(missing)}")

    # Check credentials
    print("\n2. Checking PhysioNet credentials...")
    has_creds, creds_msg = check_physionet_credentials()
    print(f"   {'✓' if has_creds else '✗'} {creds_msg}")

    if not has_creds:
        print("""
   To set up PhysioNet credentials:

   Option 1: Create ~/.netrc with:
       machine physionet.org
       login YOUR_USERNAME
       password YOUR_PASSWORD

   Option 2: Set environment variables:
       export PHYSIONET_USER=your_username
       export PHYSIONET_PASS=your_password

   First, you need to:
   1. Create account at https://physionet.org
   2. Complete CITI training
   3. Request access to MIMIC-IV at:
      https://physionet.org/content/mimiciv/
""")

    # Check data
    print("\n3. Checking MIMIC-IV data...")
    has_data, data_msg = check_data_directory()
    print(f"   {'✓' if has_data else '○'} {data_msg}")

    if has_creds and not has_data:
        print("""
   To download MIMIC-IV data:

   wget -r -N -c -np --user $PHYSIONET_USER --ask-password \\
       https://physionet.org/files/mimiciv/2.2/ \\
       -P ./data

   Or use the wfdb client:
       pip install wfdb
       python -c "import wfdb; wfdb.dl_database('mimiciv/2.2', './data')"
""")

    # Summary
    print("\n" + "=" * 60)
    if has_creds and has_data:
        print("STATUS: ✓ MIMIC-IV is ready to use!")
    elif has_creds:
        print("STATUS: ○ Credentials OK, need to download data")
    else:
        print("STATUS: ✗ Need PhysioNet credentials (see instructions above)")
    print("=" * 60)

    return 0 if (has_creds and has_data) else 1


if __name__ == "__main__":
    sys.exit(main())
