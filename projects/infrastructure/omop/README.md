# OMOP Common Data Model

Standardized data model for observational health data.

## Overview

- **Source**: OHDSI (Observational Health Data Sciences and Informatics)
- **Type**: Data model standard
- **License**: Apache 2.0

## Why OMOP?

Different hospitals store data differently. OMOP provides:
- **Standardized schema**: Same tables across institutions
- **Standardized vocabularies**: SNOMED-CT, RxNorm, LOINC mapped consistently
- **Network studies**: Run same analysis across multiple sites

## Key Tables

| Table | Purpose |
|-------|---------|
| PERSON | Patient demographics |
| OBSERVATION_PERIOD | When patient was observed |
| CONDITION_OCCURRENCE | Diagnoses |
| DRUG_EXPOSURE | Medications |
| PROCEDURE_OCCURRENCE | Procedures |
| MEASUREMENT | Labs, vitals |
| OBSERVATION | Other clinical observations |
| VISIT_OCCURRENCE | Encounters |

## OHDSI Tools Ecosystem

| Tool | Purpose |
|------|---------|
| **WhiteRabbit** | Source data profiling |
| **Rabbit-in-a-Hat** | ETL design |
| **Usagi** | Vocabulary mapping |
| **Achilles** | Data quality assessment |
| **Atlas** | Cohort definition, analytics |
| **HADES** | R analytics packages |

## Installation

```bash
./setup.sh
```

## Directory Structure

```
omop/
├── ddl/                     # Database schemas
│   ├── postgresql/
│   └── sqlite/
├── vocab/                   # Vocabulary files (gitignored)
├── etl/
│   └── synthea_to_omop.py  # Example ETL
├── src/
│   └── cohort_builder.py
├── setup.sh
└── requirements.txt
```

## Quick Start: Synthea to OMOP

Synthea can output OMOP-formatted data directly:

```bash
# In synthea directory
./run_synthea -p 1000 --exporter.cdm.export=true
```

Or use the ETL-Synthea tool:
https://github.com/OHDSI/ETL-Synthea

## Setting Up OMOP Database

```bash
# PostgreSQL
createdb omop_cdm
psql omop_cdm < ddl/postgresql/OMOPCDM_postgresql_5.4_ddl.sql

# Load vocabularies (download from Athena)
# https://athena.ohdsi.org/
```

## Vocabulary Download

1. Go to https://athena.ohdsi.org/
2. Create account
3. Select vocabularies (SNOMED, RxNorm, LOINC, ICD10, etc.)
4. Download and extract to vocab/

## Resources

- OMOP CDM: https://ohdsi.github.io/CommonDataModel/
- The Book of OHDSI: https://ohdsi.github.io/TheBookOfOhdsi/
- Athena (vocabularies): https://athena.ohdsi.org/
- Atlas: https://atlas.ohdsi.org/
