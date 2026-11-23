# CheXpert Dataset

Large-scale chest X-ray dataset with uncertainty labels from Stanford.

## Overview

- **Source**: Stanford ML Group
- **Volume**: 224,316 chest radiographs from 65,240 patients
- **Modalities**: X-ray images + radiology reports
- **License**: Stanford Research Use Agreement

## Key Features

- 14 pathology labels extracted from radiology reports
- **Uncertainty labels**: Explicitly models diagnostic uncertainty (-1, 0, 1)
- Competition benchmark for automated radiology
- Frontal and lateral views

## Labels (14 observations)

| Label | Description |
|-------|-------------|
| No Finding | Normal study |
| Enlarged Cardiomediastinum | Heart/mediastinum enlarged |
| Cardiomegaly | Enlarged heart |
| Lung Opacity | Any lung opacity |
| Lung Lesion | Discrete lung lesion |
| Edema | Pulmonary edema |
| Consolidation | Lung consolidation |
| Pneumonia | Pneumonia |
| Atelectasis | Lung collapse |
| Pneumothorax | Collapsed lung |
| Pleural Effusion | Fluid around lung |
| Pleural Other | Other pleural abnormality |
| Fracture | Rib/clavicle fracture |
| Support Devices | Tubes, lines, pacemakers |

---

## Step 1: Get Stanford Access

**Different from PhysioNet** - requires Stanford-specific agreement.

### 1.1 Register for CheXpert

1. Go to https://stanfordmlgroup.github.io/competitions/chexpert/
2. Click **"Download Dataset"** or **"Access Dataset"**
3. Fill in the registration form:
   - Name
   - Email (institutional preferred)
   - Institution/Organization
   - Intended use description

### 1.2 Agree to Stanford Research Use Agreement

- Read the Stanford Research Use Agreement
- Check the agreement box
- Submit

### 1.3 Receive Download Links

- You'll receive an email with download links
- Links typically expire after some time, download promptly
- Save the email for re-requesting access if needed

---

## Step 2: Download Data

### Option A: Small Version (Recommended for starting)

**CheXpert-v1.0-small.zip** (~11GB)
- 320x320 downsampled images
- Good for initial experiments

### Option B: Full Version

**CheXpert-v1.0.zip** (~439GB)
- Original resolution images
- Required for production/publication

### Download Steps

1. Click the download link from your email
2. Save to `projects/datasets/chexpert/data/`
3. Extract:

```bash
cd projects/datasets/chexpert/data
unzip CheXpert-v1.0-small.zip
# or
unzip CheXpert-v1.0.zip
```

---

## Step 3: Verify Setup

```bash
cd projects/datasets/chexpert
source venv/bin/activate
python src/verify_setup.py
```

Expected output when data is present:
```
2. Checking CheXpert data...
   ✓ Found CheXpert data (224316 images)
```

---

## Data Structure After Download

```
chexpert/
├── data/
│   ├── CheXpert-v1.0-small/    # or CheXpert-v1.0/
│   │   ├── train/
│   │   │   ├── patient00001/
│   │   │   │   ├── study1/
│   │   │   │   │   ├── view1_frontal.jpg
│   │   │   │   │   └── view2_lateral.jpg
│   │   │   │   └── study2/
│   │   │   └── patient00002/
│   │   ├── valid/
│   │   ├── train.csv           # Labels for training set
│   │   └── valid.csv           # Labels for validation set
├── src/
│   └── verify_setup.py
├── setup.sh
└── requirements.txt
```

---

## Label Files Format

`train.csv` and `valid.csv` contain:

| Column | Description |
|--------|-------------|
| Path | Relative path to image |
| Sex | Patient sex |
| Age | Patient age |
| Frontal/Lateral | View type |
| AP/PA | Projection type |
| [14 labels] | -1 (uncertain), 0 (negative), 1 (positive), blank (not mentioned) |

---

## Alternative: MIMIC-CXR

If you can't get CheXpert access, **MIMIC-CXR** is a similar dataset available via PhysioNet:

- 377,110 chest X-rays
- Linked to MIMIC-IV clinical data
- PhysioNet credentialed access (same as MIMIC-IV)
- https://physionet.org/content/mimic-cxr/

---

## Directory Structure

```
chexpert/
├── data/                    # Downloaded images (gitignored)
│   └── CheXpert-v1.0-small/
├── src/
│   └── verify_setup.py
├── setup.sh
└── requirements.txt
```

## Resources

- **CheXpert Homepage**: https://stanfordmlgroup.github.io/competitions/chexpert/
- **Paper**: https://arxiv.org/abs/1901.07031
- **Leaderboard**: https://stanfordmlgroup.github.io/competitions/chexpert/
- **Alternative (MIMIC-CXR)**: https://physionet.org/content/mimic-cxr/
