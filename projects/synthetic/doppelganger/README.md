# DoppelGANger - Time-Series Synthesis

Generative model for realistic time-series and sequential data.

## Overview

- **Type**: GAN-based time-series generator
- **Implementation**: Custom LSTM-GAN (inspired by DoppelGANger architecture)
- **License**: MIT

## Key Features

- **Temporal dependencies**: Captures realistic time-series patterns
- **Mixed data types**: Handles both attributes and features over time
- **Auto-correlation**: Preserves statistical properties of sequences
- Suitable for vitals, sensor data, longitudinal records

## Use Cases

1. Synthetic ICU vital signs (heart rate, BP over time)
2. Wearable device data simulation
3. Longitudinal patient trajectories
4. Time-series model training augmentation

## Architecture

DoppelGANger uses a dual-generator approach:
1. **Attribute Generator**: Generates static patient attributes
2. **Feature Generator**: Generates time-series conditioned on attributes

This captures the relationship between patient demographics and their physiological patterns.

## Installation

```bash
./setup.sh
source venv/bin/activate
```

## Quick Start

```python
from gretel_synthetics.timeseries_dgan.dgan import DGAN
from gretel_synthetics.timeseries_dgan.config import DGANConfig

# Configure model
config = DGANConfig(
    max_sequence_len=24,  # 24 hours of data
    sample_len=4,
    batch_size=100,
    epochs=300
)

# Train
model = DGAN(config)
model.train_numpy(
    attributes=patient_attributes,  # Shape: (n_patients, n_attrs)
    features=vitals_sequences       # Shape: (n_patients, seq_len, n_features)
)

# Generate
syn_attrs, syn_features = model.generate_numpy(num_samples=100)
```

## Directory Structure

```
doppelganger/
├── data/                    # Generated data (gitignored)
├── models/                  # Trained models (gitignored)
├── src/
│   ├── train.py
│   └── generate.py
├── setup.sh
└── requirements.txt
```

## Alternative: TimeGAN

If DoppelGANger doesn't fit your needs, consider TimeGAN:
- Paper: "Time-series Generative Adversarial Networks" (NeurIPS 2019)
- Implementation: https://github.com/jsyoon0823/TimeGAN

## Resources

- Paper: "Using GANs for Sharing Networked Time Series Data" (IMC 2020)
- Gretel Synthetics: https://github.com/gretelai/gretel-synthetics
- NetShare: https://github.com/netsharecmu/NetShare
