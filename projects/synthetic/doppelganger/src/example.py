"""
Time-Series Synthesis Example

Demonstrates synthetic vital signs generation using a simple GAN architecture.
This is a minimal implementation showing the concept of DoppelGANger-style synthesis.
"""

import os
import numpy as np
import pandas as pd
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset
from tqdm import tqdm
import matplotlib.pyplot as plt


class Generator(nn.Module):
    """Simple LSTM-based generator for time-series."""

    def __init__(self, latent_dim: int, hidden_dim: int, seq_len: int, n_features: int):
        super().__init__()
        self.seq_len = seq_len
        self.n_features = n_features

        self.lstm = nn.LSTM(latent_dim, hidden_dim, batch_first=True, num_layers=2)
        self.fc = nn.Linear(hidden_dim, n_features)

    def forward(self, z):
        # z: (batch, seq_len, latent_dim)
        out, _ = self.lstm(z)
        out = self.fc(out)
        return out


class Discriminator(nn.Module):
    """Simple LSTM-based discriminator for time-series."""

    def __init__(self, n_features: int, hidden_dim: int):
        super().__init__()
        self.lstm = nn.LSTM(n_features, hidden_dim, batch_first=True, num_layers=2)
        self.fc = nn.Linear(hidden_dim, 1)

    def forward(self, x):
        # x: (batch, seq_len, n_features)
        out, _ = self.lstm(x)
        out = self.fc(out[:, -1, :])  # Use last timestep
        return torch.sigmoid(out)


def generate_synthetic_vitals(n_patients: int = 100, seq_len: int = 24) -> np.ndarray:
    """
    Generate synthetic vital signs data.

    Returns array of shape (n_patients, seq_len, n_features)
    Features: heart_rate, systolic_bp, diastolic_bp, spo2, temperature
    """
    np.random.seed(42)
    n_features = 5

    data = np.zeros((n_patients, seq_len, n_features))

    for i in range(n_patients):
        # Base values with patient-specific variation
        base_hr = np.random.normal(75, 10)
        base_sbp = np.random.normal(120, 15)
        base_dbp = np.random.normal(80, 10)
        base_spo2 = np.random.normal(97, 1.5)
        base_temp = np.random.normal(37.0, 0.3)

        for t in range(seq_len):
            # Add temporal correlation (random walk)
            if t > 0:
                hr_delta = np.random.normal(0, 2)
                sbp_delta = np.random.normal(0, 3)
                dbp_delta = np.random.normal(0, 2)
                spo2_delta = np.random.normal(0, 0.3)
                temp_delta = np.random.normal(0, 0.05)
            else:
                hr_delta = sbp_delta = dbp_delta = spo2_delta = temp_delta = 0

            data[i, t, 0] = np.clip(base_hr + hr_delta + np.random.normal(0, 3), 50, 120)
            data[i, t, 1] = np.clip(base_sbp + sbp_delta + np.random.normal(0, 5), 90, 180)
            data[i, t, 2] = np.clip(base_dbp + dbp_delta + np.random.normal(0, 3), 50, 110)
            data[i, t, 3] = np.clip(base_spo2 + spo2_delta + np.random.normal(0, 0.5), 88, 100)
            data[i, t, 4] = np.clip(base_temp + temp_delta + np.random.normal(0, 0.1), 35.5, 39.0)

            # Update base for temporal correlation
            base_hr = data[i, t, 0]
            base_sbp = data[i, t, 1]
            base_dbp = data[i, t, 2]
            base_spo2 = data[i, t, 3]
            base_temp = data[i, t, 4]

    return data


def train_gan(real_data: np.ndarray, epochs: int = 100, batch_size: int = 32):
    """Train a simple GAN on time-series data."""
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f"Using device: {device}")

    n_samples, seq_len, n_features = real_data.shape
    latent_dim = 32
    hidden_dim = 64

    # Normalize data
    data_mean = real_data.mean(axis=(0, 1))
    data_std = real_data.std(axis=(0, 1))
    normalized_data = (real_data - data_mean) / data_std

    # Create dataloader
    dataset = TensorDataset(torch.FloatTensor(normalized_data))
    dataloader = DataLoader(dataset, batch_size=batch_size, shuffle=True)

    # Initialize models
    generator = Generator(latent_dim, hidden_dim, seq_len, n_features).to(device)
    discriminator = Discriminator(n_features, hidden_dim).to(device)

    # Optimizers
    g_optimizer = torch.optim.Adam(generator.parameters(), lr=0.0002, betas=(0.5, 0.999))
    d_optimizer = torch.optim.Adam(discriminator.parameters(), lr=0.0002, betas=(0.5, 0.999))

    criterion = nn.BCELoss()

    # Training loop
    for epoch in tqdm(range(epochs), desc="Training GAN"):
        for real_batch, in dataloader:
            real_batch = real_batch.to(device)
            batch_size_actual = real_batch.size(0)

            # Labels
            real_labels = torch.ones(batch_size_actual, 1).to(device)
            fake_labels = torch.zeros(batch_size_actual, 1).to(device)

            # Train Discriminator
            d_optimizer.zero_grad()
            z = torch.randn(batch_size_actual, seq_len, latent_dim).to(device)
            fake_batch = generator(z)

            d_real = discriminator(real_batch)
            d_fake = discriminator(fake_batch.detach())

            d_loss = criterion(d_real, real_labels) + criterion(d_fake, fake_labels)
            d_loss.backward()
            d_optimizer.step()

            # Train Generator
            g_optimizer.zero_grad()
            d_fake = discriminator(fake_batch)
            g_loss = criterion(d_fake, real_labels)
            g_loss.backward()
            g_optimizer.step()

    return generator, data_mean, data_std, device


def generate_samples(generator, n_samples: int, seq_len: int, latent_dim: int,
                    data_mean: np.ndarray, data_std: np.ndarray, device) -> np.ndarray:
    """Generate synthetic samples using trained generator."""
    generator.eval()
    with torch.no_grad():
        z = torch.randn(n_samples, seq_len, latent_dim).to(device)
        synthetic = generator(z).cpu().numpy()

    # Denormalize
    synthetic = synthetic * data_std + data_mean
    return synthetic


def main():
    print("=== Time-Series Synthesis Example ===\n")

    # Generate sample data (simulating real vitals)
    print("Generating sample vital signs data...")
    real_data = generate_synthetic_vitals(n_patients=200, seq_len=24)
    print(f"Real data shape: {real_data.shape}")
    print(f"  (patients, hours, features)")

    feature_names = ['Heart Rate', 'Systolic BP', 'Diastolic BP', 'SpO2', 'Temperature']

    # Train GAN
    print("\nTraining GAN...")
    generator, data_mean, data_std, device = train_gan(real_data, epochs=50, batch_size=32)

    # Generate synthetic samples
    print("\nGenerating synthetic vitals...")
    synthetic_data = generate_samples(generator, n_samples=100, seq_len=24,
                                      latent_dim=32, data_mean=data_mean,
                                      data_std=data_std, device=device)
    print(f"Synthetic data shape: {synthetic_data.shape}")

    # Compare statistics
    print("\n=== Statistical Comparison ===")
    print(f"{'Feature':<15} {'Real Mean':>12} {'Synth Mean':>12} {'Real Std':>12} {'Synth Std':>12}")
    print("-" * 65)
    for i, name in enumerate(feature_names):
        real_mean = real_data[:, :, i].mean()
        synth_mean = synthetic_data[:, :, i].mean()
        real_std = real_data[:, :, i].std()
        synth_std = synthetic_data[:, :, i].std()
        print(f"{name:<15} {real_mean:>12.2f} {synth_mean:>12.2f} {real_std:>12.2f} {synth_std:>12.2f}")

    # Save outputs
    script_dir = os.path.dirname(os.path.abspath(__file__))
    data_dir = os.path.join(script_dir, '..', 'data')
    os.makedirs(data_dir, exist_ok=True)

    # Save as flattened CSV for inspection
    print("\nSaving outputs...")
    for name, data in [('real', real_data), ('synthetic', synthetic_data)]:
        rows = []
        for patient_idx in range(data.shape[0]):
            for hour in range(data.shape[1]):
                row = {
                    'patient_id': patient_idx,
                    'hour': hour,
                    'heart_rate': data[patient_idx, hour, 0],
                    'systolic_bp': data[patient_idx, hour, 1],
                    'diastolic_bp': data[patient_idx, hour, 2],
                    'spo2': data[patient_idx, hour, 3],
                    'temperature': data[patient_idx, hour, 4],
                }
                rows.append(row)
        df = pd.DataFrame(rows)
        df.to_csv(os.path.join(data_dir, f'{name}_vitals.csv'), index=False)

    # Save model
    models_dir = os.path.join(script_dir, '..', 'models')
    os.makedirs(models_dir, exist_ok=True)
    torch.save({
        'generator_state': generator.state_dict(),
        'data_mean': data_mean,
        'data_std': data_std,
    }, os.path.join(models_dir, 'vitals_generator.pt'))

    print(f"\nDone! Outputs saved to {data_dir}/")


if __name__ == '__main__':
    main()
