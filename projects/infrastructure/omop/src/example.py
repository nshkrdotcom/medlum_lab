"""
OMOP CDM Example: Creating and Querying an OMOP Database

Demonstrates setting up an OMOP Common Data Model database
with DuckDB and running basic analytics queries.
"""

import os
import duckdb
import pandas as pd
from datetime import date, timedelta
import random


def create_omop_schema(con):
    """Create simplified OMOP CDM tables."""

    # PERSON table
    con.execute("""
        CREATE TABLE IF NOT EXISTS person (
            person_id INTEGER PRIMARY KEY,
            gender_concept_id INTEGER,
            year_of_birth INTEGER,
            month_of_birth INTEGER,
            day_of_birth INTEGER,
            race_concept_id INTEGER,
            ethnicity_concept_id INTEGER,
            location_id INTEGER,
            provider_id INTEGER,
            care_site_id INTEGER
        )
    """)

    # OBSERVATION_PERIOD table
    con.execute("""
        CREATE TABLE IF NOT EXISTS observation_period (
            observation_period_id INTEGER PRIMARY KEY,
            person_id INTEGER,
            observation_period_start_date DATE,
            observation_period_end_date DATE,
            period_type_concept_id INTEGER
        )
    """)

    # CONDITION_OCCURRENCE table
    con.execute("""
        CREATE TABLE IF NOT EXISTS condition_occurrence (
            condition_occurrence_id INTEGER PRIMARY KEY,
            person_id INTEGER,
            condition_concept_id INTEGER,
            condition_start_date DATE,
            condition_end_date DATE,
            condition_type_concept_id INTEGER,
            condition_source_value VARCHAR
        )
    """)

    # DRUG_EXPOSURE table
    con.execute("""
        CREATE TABLE IF NOT EXISTS drug_exposure (
            drug_exposure_id INTEGER PRIMARY KEY,
            person_id INTEGER,
            drug_concept_id INTEGER,
            drug_exposure_start_date DATE,
            drug_exposure_end_date DATE,
            drug_type_concept_id INTEGER,
            quantity FLOAT,
            drug_source_value VARCHAR
        )
    """)

    # MEASUREMENT table
    con.execute("""
        CREATE TABLE IF NOT EXISTS measurement (
            measurement_id INTEGER PRIMARY KEY,
            person_id INTEGER,
            measurement_concept_id INTEGER,
            measurement_date DATE,
            measurement_type_concept_id INTEGER,
            value_as_number FLOAT,
            unit_concept_id INTEGER,
            measurement_source_value VARCHAR
        )
    """)

    # CONCEPT table (vocabulary)
    con.execute("""
        CREATE TABLE IF NOT EXISTS concept (
            concept_id INTEGER PRIMARY KEY,
            concept_name VARCHAR,
            domain_id VARCHAR,
            vocabulary_id VARCHAR,
            concept_class_id VARCHAR,
            standard_concept VARCHAR,
            concept_code VARCHAR
        )
    """)


def load_sample_vocabulary(con):
    """Load sample concept vocabulary."""
    concepts = [
        # Gender
        (8507, "Male", "Gender", "Gender", "Gender", "S", "M"),
        (8532, "Female", "Gender", "Gender", "Gender", "S", "F"),

        # Conditions (SNOMED)
        (201826, "Type 2 diabetes mellitus", "Condition", "SNOMED", "Clinical Finding", "S", "44054006"),
        (316866, "Hypertensive disorder", "Condition", "SNOMED", "Clinical Finding", "S", "38341003"),
        (4229881, "Acute myocardial infarction", "Condition", "SNOMED", "Clinical Finding", "S", "22298006"),
        (255848, "Pneumonia", "Condition", "SNOMED", "Clinical Finding", "S", "233604007"),
        (192671, "Atrial fibrillation", "Condition", "SNOMED", "Clinical Finding", "S", "49436004"),

        # Drugs (RxNorm)
        (1308216, "Lisinopril 10 MG", "Drug", "RxNorm", "Clinical Drug", "S", "314076"),
        (1332418, "Metformin 500 MG", "Drug", "RxNorm", "Clinical Drug", "S", "316255"),
        (19078106, "Atorvastatin 20 MG", "Drug", "RxNorm", "Clinical Drug", "S", "617314"),
        (1110410, "Aspirin 81 MG", "Drug", "RxNorm", "Clinical Drug", "S", "243670"),

        # Measurements (LOINC)
        (3004249, "Systolic blood pressure", "Measurement", "LOINC", "Clinical Observation", "S", "8480-6"),
        (3012888, "Diastolic blood pressure", "Measurement", "LOINC", "Clinical Observation", "S", "8462-4"),
        (3004501, "Glucose [Mass/volume] in Blood", "Measurement", "LOINC", "Clinical Observation", "S", "2339-0"),
        (3027018, "Heart rate", "Measurement", "LOINC", "Clinical Observation", "S", "8867-4"),
    ]

    for concept in concepts:
        con.execute("""
            INSERT OR REPLACE INTO concept VALUES (?, ?, ?, ?, ?, ?, ?)
        """, concept)


def generate_synthetic_patients(con, n_patients: int = 100):
    """Generate synthetic patient data."""
    random.seed(42)

    # Generate persons
    for i in range(1, n_patients + 1):
        gender = random.choice([8507, 8532])
        year = random.randint(1940, 2000)
        month = random.randint(1, 12)
        day = random.randint(1, 28)

        con.execute("""
            INSERT INTO person VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (i, gender, year, month, day, 0, 0, 0, 0, 0))

        # Observation period
        start_date = date(2020, 1, 1)
        end_date = date(2024, 12, 31)
        con.execute("""
            INSERT INTO observation_period VALUES (?, ?, ?, ?, ?)
        """, (i, i, start_date, end_date, 44814724))

    # Generate conditions
    condition_concepts = [201826, 316866, 4229881, 255848, 192671]
    condition_id = 1
    for person_id in range(1, n_patients + 1):
        n_conditions = random.randint(0, 3)
        for _ in range(n_conditions):
            concept_id = random.choice(condition_concepts)
            start_date = date(2020, 1, 1) + timedelta(days=random.randint(0, 1500))
            con.execute("""
                INSERT INTO condition_occurrence VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (condition_id, person_id, concept_id, start_date, None, 32817, None))
            condition_id += 1

    # Generate drug exposures
    drug_concepts = [1308216, 1332418, 19078106, 1110410]
    drug_id = 1
    for person_id in range(1, n_patients + 1):
        n_drugs = random.randint(0, 4)
        for _ in range(n_drugs):
            concept_id = random.choice(drug_concepts)
            start_date = date(2020, 1, 1) + timedelta(days=random.randint(0, 1500))
            end_date = start_date + timedelta(days=random.randint(30, 365))
            quantity = random.randint(30, 90)
            con.execute("""
                INSERT INTO drug_exposure VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, (drug_id, person_id, concept_id, start_date, end_date, 32838, quantity, None))
            drug_id += 1

    # Generate measurements
    measurement_concepts = [3004249, 3012888, 3004501, 3027018]
    measurement_id = 1
    for person_id in range(1, n_patients + 1):
        n_measurements = random.randint(5, 20)
        for _ in range(n_measurements):
            concept_id = random.choice(measurement_concepts)
            measurement_date = date(2020, 1, 1) + timedelta(days=random.randint(0, 1500))

            # Generate realistic values
            if concept_id == 3004249:  # Systolic BP
                value = random.gauss(130, 20)
            elif concept_id == 3012888:  # Diastolic BP
                value = random.gauss(80, 12)
            elif concept_id == 3004501:  # Glucose
                value = random.gauss(100, 25)
            else:  # Heart rate
                value = random.gauss(75, 12)

            con.execute("""
                INSERT INTO measurement VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, (measurement_id, person_id, concept_id, measurement_date, 32856, value, 0, None))
            measurement_id += 1


def run_analytics_queries(con):
    """Run sample OHDSI-style analytics queries."""

    print("\n=== OMOP Analytics Queries ===\n")

    # 1. Patient demographics
    print("1. Patient Demographics:")
    result = con.execute("""
        SELECT
            c.concept_name as gender,
            COUNT(*) as patient_count,
            AVG(2024 - year_of_birth) as avg_age
        FROM person p
        JOIN concept c ON p.gender_concept_id = c.concept_id
        GROUP BY c.concept_name
    """).fetchdf()
    print(result.to_string(index=False))

    # 2. Top conditions
    print("\n2. Top 5 Conditions:")
    result = con.execute("""
        SELECT
            c.concept_name as condition,
            COUNT(*) as occurrence_count,
            COUNT(DISTINCT person_id) as patient_count
        FROM condition_occurrence co
        JOIN concept c ON co.condition_concept_id = c.concept_id
        GROUP BY c.concept_name
        ORDER BY occurrence_count DESC
        LIMIT 5
    """).fetchdf()
    print(result.to_string(index=False))

    # 3. Drug utilization
    print("\n3. Drug Utilization:")
    result = con.execute("""
        SELECT
            c.concept_name as drug,
            COUNT(*) as prescription_count,
            COUNT(DISTINCT person_id) as patient_count,
            AVG(quantity) as avg_quantity
        FROM drug_exposure de
        JOIN concept c ON de.drug_concept_id = c.concept_id
        GROUP BY c.concept_name
        ORDER BY prescription_count DESC
    """).fetchdf()
    print(result.to_string(index=False))

    # 4. Measurement statistics
    print("\n4. Measurement Statistics:")
    result = con.execute("""
        SELECT
            c.concept_name as measurement,
            COUNT(*) as n_measurements,
            ROUND(AVG(value_as_number), 1) as mean_value,
            ROUND(MIN(value_as_number), 1) as min_value,
            ROUND(MAX(value_as_number), 1) as max_value
        FROM measurement m
        JOIN concept c ON m.measurement_concept_id = c.concept_id
        GROUP BY c.concept_name
    """).fetchdf()
    print(result.to_string(index=False))

    # 5. Cohort: Diabetics on Metformin
    print("\n5. Cohort: Diabetics on Metformin:")
    result = con.execute("""
        SELECT COUNT(DISTINCT p.person_id) as cohort_size
        FROM person p
        JOIN condition_occurrence co ON p.person_id = co.person_id
        JOIN drug_exposure de ON p.person_id = de.person_id
        WHERE co.condition_concept_id = 201826  -- Type 2 DM
          AND de.drug_concept_id = 1332418      -- Metformin
    """).fetchdf()
    print(result.to_string(index=False))


def main():
    print("=== OMOP CDM Example with DuckDB ===\n")

    # Setup paths
    script_dir = os.path.dirname(os.path.abspath(__file__))
    data_dir = os.path.join(script_dir, '..', 'data')
    os.makedirs(data_dir, exist_ok=True)

    db_path = os.path.join(data_dir, 'omop_cdm.duckdb')

    # Create database
    print(f"Creating OMOP database: {db_path}")
    con = duckdb.connect(db_path)

    # Create schema
    print("Creating OMOP CDM schema...")
    create_omop_schema(con)

    # Load vocabulary
    print("Loading sample vocabulary...")
    load_sample_vocabulary(con)

    # Generate synthetic data
    print("Generating synthetic patient data (100 patients)...")
    generate_synthetic_patients(con, n_patients=100)

    # Verify data
    counts = con.execute("""
        SELECT
            (SELECT COUNT(*) FROM person) as persons,
            (SELECT COUNT(*) FROM condition_occurrence) as conditions,
            (SELECT COUNT(*) FROM drug_exposure) as drugs,
            (SELECT COUNT(*) FROM measurement) as measurements
    """).fetchone()
    print(f"\nData loaded: {counts[0]} persons, {counts[1]} conditions, {counts[2]} drugs, {counts[3]} measurements")

    # Run analytics
    run_analytics_queries(con)

    # Export to CSV for inspection
    print("\n=== Exporting tables to CSV ===")
    for table in ['person', 'condition_occurrence', 'drug_exposure', 'measurement', 'concept']:
        df = con.execute(f"SELECT * FROM {table}").fetchdf()
        csv_path = os.path.join(data_dir, f'{table}.csv')
        df.to_csv(csv_path, index=False)
        print(f"  {table}: {len(df)} rows -> {csv_path}")

    con.close()
    print("\nDone!")


if __name__ == "__main__":
    main()
