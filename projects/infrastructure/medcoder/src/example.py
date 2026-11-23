"""
MedCoder Example: Medical Entity Extraction and ICD-10 Code Suggestion

Demonstrates basic medical NLP for clinical coding assistance.
"""

import os
import re
import spacy
import pandas as pd
from typing import List, Dict, Tuple


# Simple ICD-10 code mapping (subset for demonstration)
ICD10_CODES = {
    # Respiratory
    "pneumonia": ("J18.9", "Pneumonia, unspecified organism"),
    "copd": ("J44.9", "Chronic obstructive pulmonary disease, unspecified"),
    "asthma": ("J45.909", "Unspecified asthma, uncomplicated"),
    "bronchitis": ("J40", "Bronchitis, not specified as acute or chronic"),
    "shortness of breath": ("R06.02", "Shortness of breath"),
    "dyspnea": ("R06.00", "Dyspnea, unspecified"),

    # Cardiovascular
    "chest pain": ("R07.9", "Chest pain, unspecified"),
    "hypertension": ("I10", "Essential (primary) hypertension"),
    "heart failure": ("I50.9", "Heart failure, unspecified"),
    "chf": ("I50.9", "Heart failure, unspecified"),
    "atrial fibrillation": ("I48.91", "Unspecified atrial fibrillation"),
    "myocardial infarction": ("I21.9", "Acute myocardial infarction, unspecified"),

    # Metabolic
    "diabetes": ("E11.9", "Type 2 diabetes mellitus without complications"),
    "type 2 diabetes": ("E11.9", "Type 2 diabetes mellitus without complications"),
    "hyperlipidemia": ("E78.5", "Hyperlipidemia, unspecified"),
    "obesity": ("E66.9", "Obesity, unspecified"),

    # Infections
    "urinary tract infection": ("N39.0", "Urinary tract infection, site not specified"),
    "uti": ("N39.0", "Urinary tract infection, site not specified"),
    "sepsis": ("A41.9", "Sepsis, unspecified organism"),

    # Symptoms
    "fever": ("R50.9", "Fever, unspecified"),
    "cough": ("R05.9", "Cough, unspecified"),
    "fatigue": ("R53.83", "Other fatigue"),
    "headache": ("R51.9", "Headache, unspecified"),
    "nausea": ("R11.0", "Nausea"),
    "vomiting": ("R11.10", "Vomiting, unspecified"),
    "abdominal pain": ("R10.9", "Unspecified abdominal pain"),
    "back pain": ("M54.9", "Dorsalgia, unspecified"),
    "edema": ("R60.9", "Edema, unspecified"),
}

# Common medical abbreviations
ABBREVIATIONS = {
    "sob": "shortness of breath",
    "htn": "hypertension",
    "dm": "diabetes",
    "dm2": "type 2 diabetes",
    "cad": "coronary artery disease",
    "afib": "atrial fibrillation",
    "mi": "myocardial infarction",
    "n/v": "nausea and vomiting",
    "ha": "headache",
    "cp": "chest pain",
}


def expand_abbreviations(text: str) -> str:
    """Expand common medical abbreviations."""
    text_lower = text.lower()
    for abbrev, expansion in ABBREVIATIONS.items():
        # Match whole words only
        pattern = r'\b' + re.escape(abbrev) + r'\b'
        text_lower = re.sub(pattern, expansion, text_lower)
    return text_lower


def extract_medical_entities(text: str, nlp) -> List[str]:
    """Extract potential medical entities from clinical text."""
    # Expand abbreviations
    expanded_text = expand_abbreviations(text)

    # Use spaCy for basic NLP
    doc = nlp(expanded_text)

    entities = []

    # Extract noun phrases
    for chunk in doc.noun_chunks:
        entities.append(chunk.text.lower())

    # Also check for known terms directly
    for term in ICD10_CODES.keys():
        if term in expanded_text.lower():
            if term not in entities:
                entities.append(term)

    return list(set(entities))


def match_icd10_codes(entities: List[str]) -> List[Tuple[str, str, str]]:
    """Match extracted entities to ICD-10 codes."""
    matches = []

    for entity in entities:
        entity_lower = entity.lower().strip()

        # Direct match
        if entity_lower in ICD10_CODES:
            code, description = ICD10_CODES[entity_lower]
            matches.append((entity, code, description))
            continue

        # Partial match
        for term, (code, description) in ICD10_CODES.items():
            if term in entity_lower or entity_lower in term:
                matches.append((entity, code, description))
                break

    return matches


def code_clinical_note(note: str, nlp) -> Dict:
    """Process a clinical note and suggest ICD-10 codes."""
    entities = extract_medical_entities(note, nlp)
    codes = match_icd10_codes(entities)

    return {
        "original_note": note,
        "expanded_note": expand_abbreviations(note),
        "extracted_entities": entities,
        "suggested_codes": codes,
    }


def main():
    print("=== MedCoder: Clinical Coding Assistant ===\n")

    # Load spaCy model
    print("Loading NLP model...")
    nlp = spacy.load("en_core_web_sm")

    # Sample clinical notes
    notes = [
        "Patient presents with SOB and CP. History of HTN and DM2. Started on supplemental O2.",
        "72 y/o male with acute exacerbation of COPD. Fever and productive cough x 3 days. Chest X-ray shows pneumonia.",
        "Chief complaint: N/V and abdominal pain. R/O UTI. Patient also reports fatigue and headache.",
        "Follow-up for CHF. Patient has peripheral edema. Increased Lasix dose. Also managing afib.",
    ]

    results = []

    print("\nProcessing clinical notes...\n")
    print("=" * 80)

    for i, note in enumerate(notes, 1):
        print(f"\n--- Note {i} ---")
        print(f"Original: {note}")

        result = code_clinical_note(note, nlp)

        print(f"Expanded: {result['expanded_note']}")
        print(f"\nExtracted entities: {', '.join(result['extracted_entities'][:10])}")
        print(f"\nSuggested ICD-10 codes:")

        for entity, code, description in result['suggested_codes']:
            print(f"  {code}: {description}")
            print(f"         (matched: '{entity}')")

        results.append({
            "note_id": i,
            "original": note,
            "codes": "; ".join([f"{c[1]}" for c in result['suggested_codes']]),
        })

        print("-" * 80)

    # Save results
    script_dir = os.path.dirname(os.path.abspath(__file__))
    data_dir = os.path.join(script_dir, '..', 'data')
    os.makedirs(data_dir, exist_ok=True)

    df = pd.DataFrame(results)
    output_path = os.path.join(data_dir, 'coded_notes.csv')
    df.to_csv(output_path, index=False)
    print(f"\nResults saved to {output_path}")

    # Save ICD-10 reference
    icd_df = pd.DataFrame([
        {"code": code, "description": desc, "term": term}
        for term, (code, desc) in ICD10_CODES.items()
    ])
    icd_path = os.path.join(data_dir, 'icd10_reference.csv')
    icd_df.to_csv(icd_path, index=False)
    print(f"ICD-10 reference saved to {icd_path}")

    print("\nDone!")


if __name__ == "__main__":
    main()
