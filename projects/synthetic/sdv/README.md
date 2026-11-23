# Synthetic Data Vault (SDV)

Machine learning-based synthetic data generation for tabular data.

## Overview

- **Source**: DataCebo / MIT
- **Type**: Generative ML (Gaussian Copulas, CTGAN, TVAE)
- **License**: MIT

## Key Features

- **Learns from real data**: Captures statistical properties and correlations
- **Multiple synthesizers**: Copulas for simple data, CTGAN for complex
- **Relational data**: Can model multi-table databases
- **Privacy metrics**: Built-in evaluation of re-identification risk

## Synthesizers

| Synthesizer | Best For | Speed |
|-------------|----------|-------|
| GaussianCopula | Simple distributions, fast | Fast |
| CTGAN | Complex, multi-modal data | Slow |
| TVAE | Similar to CTGAN, sometimes better | Medium |
| CopulaGAN | Hybrid approach | Medium |

## Use Cases

1. Training ML models when real data is limited
2. Sharing data without privacy concerns
3. Augmenting imbalanced datasets
4. Testing and development

## Installation

```bash
./setup.sh
source venv/bin/activate
```

## Quick Start

```python
from sdv.single_table import CTGANSynthesizer
from sdv.metadata import SingleTableMetadata
import pandas as pd

# Load your real data
real_data = pd.read_csv('patients.csv')

# Create metadata
metadata = SingleTableMetadata()
metadata.detect_from_dataframe(real_data)

# Train synthesizer
synthesizer = CTGANSynthesizer(metadata)
synthesizer.fit(real_data)

# Generate synthetic data
synthetic_data = synthesizer.sample(num_rows=1000)
```

## Directory Structure

```
sdv/
├── data/                    # Generated data (gitignored)
├── models/                  # Trained synthesizers (gitignored)
├── src/
│   ├── train.py            # Training pipeline
│   └── evaluate.py         # Quality metrics
├── configs/
│   └── metadata.json
├── setup.sh
└── requirements.txt
```

## Quality Evaluation

SDV provides built-in quality metrics:

```python
from sdv.evaluation.single_table import evaluate_quality

quality_report = evaluate_quality(
    real_data,
    synthetic_data,
    metadata
)
print(quality_report.get_score())
```

## Resources

- Docs: https://docs.sdv.dev/sdv
- GitHub: https://github.com/sdv-dev/SDV
- Tutorials: https://docs.sdv.dev/sdv/single-table-data/tutorials
