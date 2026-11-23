# eICU Collaborative Research Database

Multi-center critical care database providing geographic diversity.

## Overview

- **Source**: Philips Healthcare / MIT
- **Volume**: 200,000+ ICU stays from 200+ hospitals across the US
- **Years**: 2014-2015
- **License**: PhysioNet Credentialed Access

## Key Features

- **Multi-center**: 200+ hospitals (vs MIMIC's single center)
- Reduces site-specific bias in ML models
- High-resolution physiological data
- Nurse charting and physician notes

## Comparison with MIMIC-IV

| Aspect | MIMIC-IV | eICU-CRD |
|--------|----------|----------|
| Centers | 1 (BIDMC) | 200+ |
| Patients | 40k+ | 200k+ |
| Text richness | High | Moderate |
| Geographic diversity | Low | High |

---

## Step 1: Get PhysioNet Credentials

**Same process as MIMIC-IV** - if you already have MIMIC access, you can use the same account.

### If you don't have PhysioNet access yet:

1. **Create account**: https://physionet.org/register/
2. **Complete CITI Training**: https://about.citiprogram.org/
   - Course: "Data or Specimens Only Research"
3. **Request eICU access**: https://physionet.org/content/eicu-crd/
   - Upload CITI certificate
   - Sign Data Use Agreement
   - Wait 1-3 days for approval

---

## Step 2: Configure Credentials

Use ONE of these methods (same as MIMIC-IV):

### Option A: ~/.netrc file (Recommended)

```bash
cat >> ~/.netrc << 'EOF'
machine physionet.org
login YOUR_PHYSIONET_USERNAME
password YOUR_PHYSIONET_PASSWORD
EOF
chmod 600 ~/.netrc
```

### Option B: Environment Variables

```bash
# Add to ~/.bashrc or ~/.zshrc
export PHYSIONET_USER="your_username"
export PHYSIONET_PASS="your_password"
```

### Option C: Project .env file

Create `projects/datasets/eicu-crd/.env`:
```
PHYSIONET_USER=your_username
PHYSIONET_PASS=your_password
```

---

## Step 3: Verify Setup

```bash
cd projects/datasets/eicu-crd
source venv/bin/activate
python src/verify_setup.py
```

---

## Step 4: Download Data

### Full Download (~6GB compressed)

```bash
wget -r -N -c -np \
    --user $PHYSIONET_USER --ask-password \
    https://physionet.org/files/eicu-crd/2.0/ \
    -P ./data
```

### Key Tables

After download, you'll have CSV files including:
- `patient.csv` - Patient demographics
- `admissiondx.csv` - Admission diagnoses
- `diagnosis.csv` - ICD codes
- `medication.csv` - Medications
- `lab.csv` - Lab results
- `vitalperiodic.csv` - Vital signs (high frequency)
- `nursecharting.csv` - Nurse assessments

---

## Directory Structure

```
eicu-crd/
├── data/                    # Downloaded data (gitignored)
│   ├── patient.csv
│   ├── admissiondx.csv
│   ├── diagnosis.csv
│   └── ...
├── src/
│   └── verify_setup.py
├── setup.sh
├── requirements.txt
└── .env                    # Your credentials (gitignored)
```

## Resources

- **Documentation**: https://eicu-crd.mit.edu/
- **Schema**: https://eicu-crd.mit.edu/eicutables/
- **PhysioNet**: https://physionet.org/content/eicu-crd/
