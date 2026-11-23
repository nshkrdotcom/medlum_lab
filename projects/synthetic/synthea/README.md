# Synthea - Synthetic Patient Generator

Rule-based synthetic patient data generator developed by MITRE.

## Overview

- **Source**: MITRE Corporation
- **Type**: Rule-based state machine
- **Output**: FHIR, C-CDA, CSV formats
- **License**: Apache 2.0

## Key Features

- Generates complete longitudinal patient records
- Based on real clinical guidelines and disease prevalence
- **Medically logical**: Patients won't have impossible combinations
- Configurable demographics (geography, age distribution)
- Supports 90+ disease modules

## Use Cases

1. Software testing and interoperability (FHIR)
2. Population health dashboards
3. ML model pre-training (before fine-tuning on real data)
4. Education and training
5. Privacy-safe demos

## Installation

```bash
./setup.sh
```

Synthea requires Java 11+.

## Quick Start

```bash
# Generate 1000 patients in Massachusetts
cd synthea
./run_synthea -p 1000 Massachusetts

# Output in ./output/fhir/ and ./output/csv/
```

## Configuration

Key configuration files:
- `src/main/resources/synthea.properties` - Main settings
- `src/main/resources/modules/` - Disease modules

## Disease Modules

Synthea models diseases as state machines. Key modules include:
- Cardiovascular (heart disease, hypertension)
- Respiratory (asthma, COPD, lung cancer)
- Metabolic (diabetes, obesity)
- Neurological (Alzheimer's, epilepsy)
- Infectious (COVID-19, flu)

## Directory Structure

```
synthea/
├── data/                    # Generated patient data (gitignored)
│   ├── fhir/
│   └── csv/
├── synthea/                 # Cloned Synthea repo (gitignored)
├── configs/
│   └── custom_synthea.properties
├── setup.sh
└── generate.sh
```

## Resources

- GitHub: https://github.com/synthetichealth/synthea
- Wiki: https://github.com/synthetichealth/synthea/wiki
- Module Builder: https://synthetichealth.github.io/module-builder/
