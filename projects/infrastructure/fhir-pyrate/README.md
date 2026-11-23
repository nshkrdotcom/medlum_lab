# FHIR-PYrate

Python library for extracting FHIR data for machine learning.

## Overview

- **Source**: SMITH Consortium
- **Type**: Data extraction library
- **License**: MIT

## Key Features

- Query FHIR servers with simple Python API
- Flatten nested FHIR JSON into Pandas DataFrames
- Handle pagination automatically
- Support for common FHIR resources (Patient, Observation, Condition, etc.)

## Use Cases

1. Extract patient cohorts for ML training
2. Build feature matrices from EHR data
3. Research data extraction
4. FHIR server analytics

## Installation

```bash
./setup.sh
source venv/bin/activate
```

## Quick Start

```python
from fhir_pyrate import Pirate
from fhir_pyrate.util import FHIRServer

# Connect to FHIR server
server = FHIRServer(
    base_url="https://hapi.fhir.org/baseR4",  # Public test server
    auth=None  # Add auth for protected servers
)

# Initialize Pirate
pirate = Pirate(server)

# Search for patients
patients_df = pirate.sail(
    resource="Patient",
    search_params={"_count": 100}
)

# Get observations for specific patients
observations_df = pirate.sail(
    resource="Observation",
    search_params={
        "patient": patient_ids,
        "code": "http://loinc.org|8867-4"  # Heart rate
    }
)
```

## Directory Structure

```
fhir-pyrate/
├── data/                    # Extracted data (gitignored)
├── src/
│   ├── extract_cohort.py
│   └── build_features.py
├── configs/
│   └── fhir_servers.yaml
├── setup.sh
└── requirements.txt
```

## Common FHIR Resources

| Resource | Use Case |
|----------|----------|
| Patient | Demographics, identifiers |
| Observation | Lab results, vitals |
| Condition | Diagnoses |
| MedicationRequest | Prescriptions |
| Procedure | Surgeries, interventions |
| Encounter | Visits, admissions |

## Public FHIR Servers (for testing)

- HAPI FHIR: https://hapi.fhir.org/baseR4
- Synthea FHIR: Various (from Synthea project)
- SMART Health IT: https://launch.smarthealthit.org

## Related Tools

- **NeuroFHIR**: Graph-based FHIR analysis
- **FHIRBoard**: Analytics dashboard

## Resources

- Docs: https://fhir-pyrate.readthedocs.io/
- GitHub: https://github.com/UMEssen/FHIR-PYrate
- FHIR Spec: https://hl7.org/fhir/
