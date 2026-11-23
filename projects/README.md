# Medlum Lab Projects

This directory contains subprojects for building open-source medical AI infrastructure.

## Project Checklist

| # | Project | Category | Status | Notes |
|---|---------|----------|--------|-------|
| 1 | [sdv](synthetic/sdv/) | Synthetic | ✅ Ready | ML-based synthetic tabular data |
| 2 | [synthea](synthetic/synthea/) | Synthetic | ✅ Ready | Rule-based patient generator (needs Java) |
| 3 | [doppelganger](synthetic/doppelganger/) | Synthetic | ✅ Ready | Time-series synthesis |
| 4 | [fhir-pyrate](infrastructure/fhir-pyrate/) | Infrastructure | ✅ Ready | FHIR data extraction |
| 5 | [monai](infrastructure/monai/) | Infrastructure | ✅ Ready | Medical imaging DL framework |
| 6 | [medcoder](infrastructure/medcoder/) | Infrastructure | ✅ Ready | ICD-10 coding automation |
| 7 | [omop](infrastructure/omop/) | Infrastructure | ✅ Ready | OMOP Common Data Model |
| 8 | [mimic-iv](datasets/mimic-iv/) | Datasets | 🔐 Blocked | Requires PhysioNet credentials |
| 9 | [eicu-crd](datasets/eicu-crd/) | Datasets | 🔐 Blocked | Requires PhysioNet credentials |
| 10 | [chexpert](datasets/chexpert/) | Datasets | 🔐 Blocked | Requires Stanford agreement |

### Status Legend
- ⬜ Pending - Not started
- 🔄 In Progress - Setup incomplete
- ✅ Ready - Fully working, tested
- 🔐 Blocked - Requires external credentials/access

## Priority Order

Projects are ordered by achievability (no external credentials first):

1. **sdv** - Can run immediately with pip install
2. **synthea** - Needs Java 11+, then self-contained
3. **doppelganger** - Can run immediately with pip install
4. **fhir-pyrate** - Can test against public FHIR servers
5. **monai** - Needs GPU for full use, but CPU works
6. **medcoder** - Needs NLP models downloaded
7. **omop** - Needs vocabulary download from Athena
8. **mimic-iv** - Requires PhysioNet credentialed access
9. **eicu-crd** - Requires PhysioNet credentialed access
10. **chexpert** - Requires Stanford research agreement

## Quick Start

```bash
# Pick a project
cd projects/synthetic/sdv

# Run setup
./setup.sh

# Activate and use
source venv/bin/activate
python src/example.py
```

## Structure Convention

Each project follows the same pattern:
```
project/
├── README.md           # Documentation
├── .gitignore          # Excludes data/models
├── setup.sh            # Installation script
├── requirements.txt    # Python dependencies
├── src/                # Source code
├── configs/            # Configuration files
├── data/               # Downloaded/generated (gitignored)
├── models/             # Trained models (gitignored)
└── outputs/            # Results (gitignored)
```
