# MIMIC-IV Dataset

The "ImageNet" of clinical NLP - a freely accessible critical care database.

## Overview

- **Source**: Beth Israel Deaconess Medical Center / MIT
- **Volume**: 40,000+ ICU patients (2008-2019)
- **Modalities**: EHR (structured + free-text)
- **License**: PhysioNet Credentialed Access

## Key Features

- Discharge summaries and nursing notes (unstructured text)
- Granular ICU vitals and lab results
- Medication administration records
- ICD-9/10 diagnosis and procedure codes

---

## Step 1: Get PhysioNet Credentials

### 1.1 Create PhysioNet Account

1. Go to https://physionet.org/register/
2. Fill in your details (use institutional email if possible)
3. Verify your email

### 1.2 Complete CITI Training

1. Go to https://about.citiprogram.org/
2. Create account (affiliate with your institution if possible)
3. Complete the course: **"Data or Specimens Only Research"**
4. Download your completion certificate/report

### 1.3 Request MIMIC-IV Access

1. Go to https://physionet.org/content/mimiciv/
2. Click "Request Access"
3. Upload your CITI training certificate
4. Sign the Data Use Agreement
5. Wait for approval (usually 1-3 days)

---

## Step 2: Configure Credentials

Once approved, configure your credentials using ONE of these methods:

### Option A: ~/.netrc file (Recommended)

Create or edit `~/.netrc`:

```bash
cat >> ~/.netrc << 'EOF'
machine physionet.org
login YOUR_PHYSIONET_USERNAME
password YOUR_PHYSIONET_PASSWORD
EOF
chmod 600 ~/.netrc
```

### Option B: Environment Variables

Add to your `~/.bashrc` or `~/.zshrc`:

```bash
export PHYSIONET_USER="your_username"
export PHYSIONET_PASS="your_password"
```

Then reload: `source ~/.bashrc`

### Option C: Project-specific .env file

Create `projects/datasets/mimic-iv/.env`:

```
PHYSIONET_USER=your_username
PHYSIONET_PASS=your_password
```

**Note**: The `.env` file is gitignored and won't be committed.

---

## Step 3: Verify Setup

```bash
cd projects/datasets/mimic-iv
source venv/bin/activate
python src/verify_setup.py
```

Expected output when credentials are configured:
```
2. Checking PhysioNet credentials...
   ✓ Found credentials in ~/.netrc
```

---

## Step 4: Download Data

### Full Download (~7GB compressed)

```bash
wget -r -N -c -np \
    --user $PHYSIONET_USER --ask-password \
    https://physionet.org/files/mimiciv/2.2/ \
    -P ./data
```

### Download Specific Modules

```bash
# Hospital module only (~2GB)
wget -r -N -c -np \
    --user $PHYSIONET_USER --ask-password \
    https://physionet.org/files/mimiciv/2.2/hosp/ \
    -P ./data

# ICU module only (~1GB)
wget -r -N -c -np \
    --user $PHYSIONET_USER --ask-password \
    https://physionet.org/files/mimiciv/2.2/icu/ \
    -P ./data
```

---

## Directory Structure

```
mimic-iv/
├── data/                    # Downloaded data (gitignored)
│   ├── hosp/               # Hospital module (admissions, diagnoses, etc.)
│   ├── icu/                # ICU module (chartevents, vitals, etc.)
│   └── note/               # Clinical notes module
├── src/
│   └── verify_setup.py     # Credential/data verification
├── setup.sh                # Environment setup
├── requirements.txt
└── .env                    # Your credentials (gitignored)
```

## Resources

- **Documentation**: https://mimic.mit.edu/docs/iv/
- **Schema**: https://mimic.mit.edu/docs/iv/modules/
- **PhysioNet**: https://physionet.org/content/mimiciv/
- **CITI Training**: https://about.citiprogram.org/
