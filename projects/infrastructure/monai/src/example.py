"""
MONAI Example: Medical Image Segmentation Pipeline

Demonstrates MONAI's core functionality with synthetic 3D medical images.
"""

import os
import numpy as np
import torch
from monai.networks.nets import UNet
from monai.losses import DiceLoss
from monai.metrics import DiceMetric
from monai.transforms import (
    Compose, EnsureChannelFirst, ScaleIntensity,
    RandRotate90, RandFlip, ToTensor
)
from monai.data import DataLoader, Dataset
from tqdm import tqdm


def generate_synthetic_data(n_samples: int = 20, size: int = 64):
    """
    Generate synthetic 3D medical images with simple geometric labels.
    Simulates organ segmentation task.
    """
    images = []
    labels = []

    for _ in range(n_samples):
        # Create 3D volume with noise
        img = np.random.randn(size, size, size).astype(np.float32) * 0.1

        # Add a "tumor" (sphere) at random location
        label = np.zeros((size, size, size), dtype=np.float32)

        cx, cy, cz = np.random.randint(20, size - 20, 3)
        radius = np.random.randint(8, 15)

        for x in range(size):
            for y in range(size):
                for z in range(size):
                    if (x - cx) ** 2 + (y - cy) ** 2 + (z - cz) ** 2 < radius ** 2:
                        img[x, y, z] += 0.5  # Brighter region
                        label[x, y, z] = 1.0

        images.append(img)
        labels.append(label)

    return images, labels


class SyntheticDataset(Dataset):
    """Simple dataset for synthetic medical images."""

    def __init__(self, images, labels, transform=None):
        self.images = images
        self.labels = labels
        self.transform = transform

    def __len__(self):
        return len(self.images)

    def __getitem__(self, idx):
        image = self.images[idx]
        label = self.labels[idx]

        # Add channel dimension
        image = np.expand_dims(image, 0)
        label = np.expand_dims(label, 0)

        if self.transform:
            data = {"image": image, "label": label}
            # Apply transforms if needed
            image = data["image"]
            label = data["label"]

        return torch.FloatTensor(image), torch.FloatTensor(label)


def train_model(model, train_loader, optimizer, loss_fn, device, epochs=10):
    """Train the segmentation model."""
    model.train()

    for epoch in range(epochs):
        epoch_loss = 0
        for images, labels in tqdm(train_loader, desc=f"Epoch {epoch + 1}/{epochs}"):
            images, labels = images.to(device), labels.to(device)

            optimizer.zero_grad()
            outputs = model(images)
            loss = loss_fn(outputs, labels)
            loss.backward()
            optimizer.step()

            epoch_loss += loss.item()

        avg_loss = epoch_loss / len(train_loader)
        print(f"  Epoch {epoch + 1} - Loss: {avg_loss:.4f}")

    return model


def evaluate_model(model, val_loader, device):
    """Evaluate model with Dice metric."""
    model.eval()
    dice_metric = DiceMetric(include_background=False, reduction="mean")

    with torch.no_grad():
        for images, labels in val_loader:
            images, labels = images.to(device), labels.to(device)
            outputs = model(images)

            # Threshold predictions
            preds = (torch.sigmoid(outputs) > 0.5).float()
            dice_metric(preds, labels)

    dice_score = dice_metric.aggregate().item()
    dice_metric.reset()
    return dice_score


def main():
    print("=== MONAI Medical Imaging Example ===\n")

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Using device: {device}")

    # Generate synthetic data
    print("\nGenerating synthetic 3D medical images...")
    train_images, train_labels = generate_synthetic_data(n_samples=30, size=48)
    val_images, val_labels = generate_synthetic_data(n_samples=10, size=48)

    print(f"Training samples: {len(train_images)}")
    print(f"Validation samples: {len(val_images)}")
    print(f"Image shape: {train_images[0].shape}")

    # Create datasets and loaders
    train_dataset = SyntheticDataset(train_images, train_labels)
    val_dataset = SyntheticDataset(val_images, val_labels)

    train_loader = DataLoader(train_dataset, batch_size=4, shuffle=True)
    val_loader = DataLoader(val_dataset, batch_size=4)

    # Create UNet model
    print("\nInitializing UNet model...")
    model = UNet(
        spatial_dims=3,
        in_channels=1,
        out_channels=1,
        channels=(16, 32, 64),
        strides=(2, 2),
        num_res_units=2,
    ).to(device)

    # Loss and optimizer
    loss_fn = DiceLoss(sigmoid=True)
    optimizer = torch.optim.Adam(model.parameters(), lr=1e-3)

    # Train
    print("\nTraining...")
    model = train_model(model, train_loader, optimizer, loss_fn, device, epochs=5)

    # Evaluate
    print("\nEvaluating...")
    dice_score = evaluate_model(model, val_loader, device)
    print(f"Validation Dice Score: {dice_score:.4f}")

    # Save model
    script_dir = os.path.dirname(os.path.abspath(__file__))
    models_dir = os.path.join(script_dir, '..', 'models')
    os.makedirs(models_dir, exist_ok=True)

    model_path = os.path.join(models_dir, 'unet_segmentation.pt')
    torch.save(model.state_dict(), model_path)
    print(f"\nModel saved to {model_path}")

    # Save sample data for inspection
    data_dir = os.path.join(script_dir, '..', 'data')
    os.makedirs(data_dir, exist_ok=True)

    np.save(os.path.join(data_dir, 'sample_image.npy'), train_images[0])
    np.save(os.path.join(data_dir, 'sample_label.npy'), train_labels[0])
    print(f"Sample data saved to {data_dir}/")

    print("\nDone!")


if __name__ == "__main__":
    main()
