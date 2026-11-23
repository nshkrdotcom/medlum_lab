"""
SDV Example: Synthesizing medical tabular data

This example demonstrates generating synthetic patient demographics
using different SDV synthesizers.
"""

import pandas as pd
import numpy as np
from sdv.single_table import GaussianCopulaSynthesizer, CTGANSynthesizer
from sdv.metadata import SingleTableMetadata
from sdv.evaluation.single_table import evaluate_quality


def create_sample_medical_data(n_patients: int = 500) -> pd.DataFrame:
    """Create sample patient data for demonstration."""
    np.random.seed(42)

    data = pd.DataFrame({
        'patient_id': range(1, n_patients + 1),
        'age': np.random.normal(55, 18, n_patients).clip(18, 95).astype(int),
        'gender': np.random.choice(['M', 'F'], n_patients, p=[0.48, 0.52]),
        'bmi': np.random.normal(27, 5, n_patients).clip(15, 50).round(1),
        'systolic_bp': np.random.normal(130, 20, n_patients).clip(90, 200).astype(int),
        'diastolic_bp': np.random.normal(80, 12, n_patients).clip(50, 120).astype(int),
        'cholesterol': np.random.normal(200, 40, n_patients).clip(100, 350).astype(int),
        'diabetes': np.random.choice([0, 1], n_patients, p=[0.85, 0.15]),
        'smoker': np.random.choice([0, 1], n_patients, p=[0.75, 0.25]),
    })

    # Add correlation: older patients more likely to have higher BP
    data.loc[data['age'] > 65, 'systolic_bp'] += 15

    return data


def main():
    print("=== SDV Medical Data Synthesis Example ===\n")

    # Create sample data
    print("Creating sample patient data...")
    real_data = create_sample_medical_data(500)
    print(f"Real data shape: {real_data.shape}")
    print(real_data.head())

    # Create metadata
    print("\nDetecting metadata...")
    metadata = SingleTableMetadata()
    metadata.detect_from_dataframe(real_data)
    metadata.update_column('patient_id', sdtype='id')

    # Train GaussianCopula (fast)
    print("\nTraining GaussianCopula synthesizer...")
    gc_synth = GaussianCopulaSynthesizer(metadata)
    gc_synth.fit(real_data)

    # Generate synthetic data
    print("Generating 1000 synthetic patients...")
    synthetic_data = gc_synth.sample(num_rows=1000)
    print(f"Synthetic data shape: {synthetic_data.shape}")
    print(synthetic_data.head())

    # Evaluate quality
    print("\nEvaluating synthetic data quality...")
    quality_report = evaluate_quality(real_data, synthetic_data, metadata)
    print(f"Overall Quality Score: {quality_report.get_score():.2%}")

    # Save outputs
    print("\nSaving outputs...")
    import os
    script_dir = os.path.dirname(os.path.abspath(__file__))
    data_dir = os.path.join(script_dir, '..', 'data')
    models_dir = os.path.join(script_dir, '..', 'models')
    os.makedirs(data_dir, exist_ok=True)
    os.makedirs(models_dir, exist_ok=True)

    real_data.to_csv(os.path.join(data_dir, 'real_sample.csv'), index=False)
    synthetic_data.to_csv(os.path.join(data_dir, 'synthetic_sample.csv'), index=False)
    gc_synth.save(os.path.join(models_dir, 'gaussian_copula.pkl'))

    print("\nDone! Check ../data/ for outputs.")


if __name__ == '__main__':
    main()
