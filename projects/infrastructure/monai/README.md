# MONAI - Medical Open Network for AI

The PyTorch-based framework for deep learning in healthcare imaging.

## Overview

- **Source**: NVIDIA & King's College London
- **Type**: Deep learning framework
- **License**: Apache 2.0

## Components

| Component | Purpose |
|-----------|---------|
| **MONAI Core** | Transforms, losses, networks for medical imaging |
| **MONAI Label** | Interactive annotation with active learning |
| **MONAI Deploy** | Production deployment to PACS/clinical systems |
| **MONAI Model Zoo** | Pre-trained models for common tasks |

## Key Features

- Medical-specific transforms (elastic deformation, intensity normalization)
- Specialized loss functions (Dice, Focal, Tversky)
- State-of-the-art architectures (UNet, UNETR, SwinUNETR)
- DICOM/NIfTI native support
- Multi-GPU and distributed training

## Use Cases

1. Organ/tumor segmentation
2. Disease classification from imaging
3. Image registration
4. Anomaly detection

## Installation

```bash
./setup.sh
source venv/bin/activate
```

## Quick Start

```python
import monai
from monai.networks.nets import UNet
from monai.losses import DiceLoss
from monai.transforms import (
    Compose, LoadImaged, EnsureChannelFirstd,
    ScaleIntensityd, RandRotate90d
)

# Define transforms
train_transforms = Compose([
    LoadImaged(keys=["image", "label"]),
    EnsureChannelFirstd(keys=["image", "label"]),
    ScaleIntensityd(keys="image"),
    RandRotate90d(keys=["image", "label"], prob=0.5),
])

# Create model
model = UNet(
    spatial_dims=3,
    in_channels=1,
    out_channels=2,
    channels=(16, 32, 64, 128, 256),
    strides=(2, 2, 2, 2),
)

# Loss function
loss = DiceLoss(to_onehot_y=True, softmax=True)
```

## Directory Structure

```
monai/
├── data/                    # Downloaded datasets (gitignored)
├── models/                  # Trained models (gitignored)
├── src/
│   ├── train_segmentation.py
│   └── inference.py
├── configs/
│   └── train_config.yaml
├── setup.sh
└── requirements.txt
```

## MONAI Label (Interactive Annotation)

```bash
# Start annotation server
monailabel start_server \
    --app apps/radiology \
    --studies datasets/Task09_Spleen/imagesTr \
    --conf models segmentation
```

Connect with 3D Slicer or OHIF Viewer for interactive labeling.

## Model Zoo

Pre-trained models available at:
https://github.com/Project-MONAI/model-zoo

Examples:
- Spleen segmentation (CT)
- Lung nodule detection
- Cardiac MRI segmentation
- Brain tumor segmentation

## Resources

- Docs: https://docs.monai.io/
- GitHub: https://github.com/Project-MONAI/MONAI
- Tutorials: https://github.com/Project-MONAI/tutorials
- Model Zoo: https://github.com/Project-MONAI/model-zoo
