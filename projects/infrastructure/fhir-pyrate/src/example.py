"""
FHIR-PYrate Example: Extracting patient data from a public FHIR server.
"""

import pandas as pd

# Note: fhir_pyrate may need configuration based on version
# This is a simplified example showing the concept

def fetch_from_hapi_fhir():
    """Fetch sample data from public HAPI FHIR server."""
    import requests

    base_url = "https://hapi.fhir.org/baseR4"

    # Fetch patients
    print("Fetching patients from HAPI FHIR...")
    response = requests.get(
        f"{base_url}/Patient",
        params={"_count": 10, "_format": "json"}
    )
    response.raise_for_status()
    bundle = response.json()

    # Parse into simple DataFrame
    patients = []
    for entry in bundle.get("entry", []):
        resource = entry.get("resource", {})
        patient = {
            "id": resource.get("id"),
            "gender": resource.get("gender"),
            "birthDate": resource.get("birthDate"),
        }
        # Get name if available
        names = resource.get("name", [])
        if names:
            patient["family"] = names[0].get("family", "")
            patient["given"] = " ".join(names[0].get("given", []))
        patients.append(patient)

    df = pd.DataFrame(patients)
    print(f"Retrieved {len(df)} patients")
    print(df.head())

    return df


def main():
    print("=== FHIR-PYrate Example ===\n")

    df = fetch_from_hapi_fhir()

    # Save to data directory
    import os
    script_dir = os.path.dirname(os.path.abspath(__file__))
    data_dir = os.path.join(script_dir, '..', 'data')
    os.makedirs(data_dir, exist_ok=True)

    output_path = os.path.join(data_dir, 'sample_patients.csv')
    df.to_csv(output_path, index=False)
    print(f"\nSaved to {output_path}")


if __name__ == "__main__":
    main()
