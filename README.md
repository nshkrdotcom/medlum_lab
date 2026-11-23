<p align="center">
  <img src="assets/medlum_lab.svg" width="200" height="200" alt="Medlum Lab logo" />
</p>

<h1 align="center">Medlum Lab</h1>

<p align="center">
  <a href="https://github.com/nshkrdotcom/medlum_lab"><img alt="GitHub: medlum_lab" src="https://img.shields.io/badge/GitHub-medlum__lab-0b192c?logo=github" /></a>
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-0e7490.svg" /></a>
</p>

Open-source medical AI libraries, synthetic clinical data pipelines, and healthcare data infrastructure for **Medlum** — an edge-deployed clinical document processing and verification platform built with privacy-by-architecture.

## Overview

Medlum inverts centralized cloud clinical AI by running inference locally inside clinical environments so patient data (PHI) never leaves the care site. This repository brings together the core building blocks:

- **Elixir Clinical NLP & Verification Stack** — OTP-native libraries for medical LLM inference, clinical embeddings, named entity recognition, offline medical ontology lookups, and multi-agent hallucination verification.
- **Synthetic Clinical Data** — Rule-based and generative pipelines for privacy-safe tabular, patient, and time-series healthcare data.
- **Healthcare Data Infrastructure** — Reference workspaces for FHIR extraction, OMOP CDM, automated ICD-10 coding, and medical imaging.
- **Clinical Benchmark Datasets** — Reproducible setup guides and evaluation scaffolding for credentialed clinical corpora.

## Architecture

| Layer | Components |
| --- | --- |
| **Inference Runtime** | Elixir / Phoenix / OTP -> `MedlumLlm` -> `Ollixir` -> `Ollama` (local 7B–8B medical models on 16GB VRAM) |
| **Clinical Verification Layer (CVL)** | 5-agent verification across medications (RxNorm), labs (LOINC), ontologies (SNOMED-CT / ICD-10), temporal logic, and differential diagnoses |
| **Data Movement** | Federated local inference and storage with encrypted peer-to-peer transfer; coordination layer handles signaling only (no PHI) |

## Repository Layout

```text
medlum_lab/
├── assets/                  # Branding and SVG assets
└── projects/
    ├── elixir/              # Elixir/OTP medical AI and clinical NLP libraries
    ├── synthetic/           # Synthetic clinical data generators
    ├── infrastructure/      # FHIR, OMOP, medical coding, and imaging workspaces
    └── datasets/            # Credentialed clinical dataset integration guides
```

## Elixir Libraries

Located under [`projects/elixir/`](projects/elixir/):

| Project | Purpose |
| --- | --- |
| [`medlum_llm`](projects/elixir/medlum_llm/README.md) | Medical LLM chat, clinical embeddings, smart task routing, evaluation datasets, and the 5-agent Clinical Verification Layer (CVL) |
| [`clinical_ner_ex`](projects/elixir/clinical_ner_ex/README.md) | Clinical Named Entity Recognition for medications, labs, diagnoses, procedures, and temporal expressions with ontology linking |
| [`med_ontology_ex`](projects/elixir/med_ontology_ex/README.md) | Unified offline-capable lookup service for SNOMED-CT, ICD-10-CM, RxNorm, and LOINC with ETS/DETS caching |
| [`elixir_bio_clinicalbert`](projects/elixir/elixir_bio_clinicalbert/README.md) | Clinical text embeddings and cosine similarity via Bio_ClinicalBERT and Ollama/Ollixir |

## Subprojects

Full checklist and conventions are maintained in [`projects/README.md`](projects/README.md).

### Synthetic Data (`projects/synthetic/`)

| Project | Status | Description |
| --- | --- | --- |
| [`sdv`](projects/synthetic/sdv/README.md) | Ready | ML-based synthetic tabular data generation (Synthetic Data Vault) |
| [`synthea`](projects/synthetic/synthea/README.md) | Ready | Rule-based synthetic patient generator (MITRE, requires Java 11+) |
| [`doppelganger`](projects/synthetic/doppelganger/README.md) | Ready | Generative time-series and sequential clinical data synthesis |

### Healthcare Infrastructure (`projects/infrastructure/`)

| Project | Status | Description |
| --- | --- | --- |
| [`fhir-pyrate`](projects/infrastructure/fhir-pyrate/README.md) | Ready | Python tooling for extracting HL7 FHIR resources for ML pipelines |
| [`monai`](projects/infrastructure/monai/README.md) | Ready | PyTorch-based deep learning framework for medical imaging |
| [`medcoder`](projects/infrastructure/medcoder/README.md) | Ready | Automated ICD-10 medical coding from clinical notes |
| [`omop`](projects/infrastructure/omop/README.md) | Ready | OMOP Common Data Model setup and vocabulary workflows |

### Clinical Datasets (`projects/datasets/`)

| Project | Status | Description |
| --- | --- | --- |
| [`mimic-iv`](projects/datasets/mimic-iv/README.md) | Credentialed | Critical care clinical NLP benchmark (requires PhysioNet access) |
| [`eicu-crd`](projects/datasets/eicu-crd/README.md) | Credentialed | Multi-center critical care database (requires PhysioNet access) |
| [`chexpert`](projects/datasets/chexpert/README.md) | Credentialed | Chest X-ray dataset with uncertainty labels (requires Stanford agreement) |

## Quick Start

### Elixir Libraries

Requires Elixir, Erlang/OTP, and a local [Ollama](https://ollama.ai) instance for LLM/embedding calls:

```bash
cd projects/elixir/medlum_llm
mix deps.get
mix test
```

### Python & Infrastructure Subprojects

Each project under `projects/synthetic/`, `projects/infrastructure/`, and `projects/datasets/` follows a uniform layout with a self-contained `setup.sh`. Generated `data/`, `models/`, `outputs/`, and downloaded runtimes (such as the Synthea JAR) are gitignored and reproduced locally via `./setup.sh`; credentialed datasets (`mimic-iv`, `eicu-crd`, `chexpert`) require PhysioNet or Stanford access as documented in their respective READMEs.

```bash
cd projects/synthetic/sdv
./setup.sh
source venv/bin/activate
python src/example.py
```

## Documentation

- [`projects/README.md`](projects/README.md) — Subproject checklist, priority order, and directory conventions
- [`CLAUDE.md`](CLAUDE.md) — Platform thesis, architecture overview, and research priorities
