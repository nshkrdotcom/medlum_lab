# Clinical Verification Layer (CVL)

The CVL is a multi-agent verification system for detecting hallucinations
in LLM-generated clinical summaries.

## Architecture

Five specialized agents achieve consensus through weighted voting:

| Agent | Domain | Ontology | Weight | Purpose |
|-------|--------|----------|--------|---------|
| **Medication Agent** | Drug verification | RxNorm | 1.5 | Verify drug names, doses, frequencies, interactions |
| **Lab Agent** | Lab values | LOINC | 1.2 | Verify test names, values, units, reference ranges |
| **Ontology Agent** | Clinical terminology | SNOMED-CT, ICD-10 | 1.0 | Verify diagnosis codes, hierarchical relationships |
| **Temporal Agent** | Timeline | (internal) | 0.8 | Verify chronological consistency, disease progression |
| **Differential Agent** | Clinical reasoning | DifferentialDB | 1.0 | Verify symptom-diagnosis mapping, red flags |

## Verdicts

CVL uses 3-way NLI (Natural Language Inference) semantics:

| Verdict | Meaning | Medlum Action |
|---------|---------|--------------|
| **ENTAILMENT** | Claim is supported by source documents | Show normally |
| **CONTRADICTION** | Claim conflicts with evidence or is clearly invalid | Flag as potential hallucination |
| **NEUTRAL** | Claim cannot be verified from available evidence | Show with uncertainty + route to review |

## Source Grounding

CVL's purpose is hallucination detection, so verification must be **source-grounded**:

- Claims are extracted from the generated summary
- Agents verify each claim against source documents
- Ontology lookups (RxNorm/LOINC) are supporting signals, not sufficient on their own
- A clinically plausible claim can still be a hallucination if absent from source documents

## Using the Medication Agent

```elixir
alias MedlumLlm.CVL.MedicationAgent

claim = "Patient started on metformin 500mg twice daily"

context = %{
  conditions: [:diabetes],
  current_medications: [],
  source_index: %{
    medications: [%{text: "metformin 500 mg BID", doc_id: "note-1"}]
  }
}

result = MedicationAgent.verify(claim, context)
# => %{
#   verdict: :entailment,
#   confidence: 0.95,
#   explanations: ["Medication 'metformin' supported by source documents"],
#   evidence: [%{doc_id: "note-1", snippet: "metformin 500 mg BID", ...}],
#   sub_verdicts: [{:entailment, "Medication 'metformin' supported by source documents"}]
# }
```

### Context Shape

The `context` map should include:

```elixir
%{
  # Required for source grounding
  source_index: %{
    medications: [
      %{doc_id: "doc-1", text: "metformin 500 mg", attributes: %{dose: 500, unit: "mg"}}
    ],
    labs: [...],
    diagnoses: [...]
  },

  # Optional: for interaction/contraindication checks
  current_medications: [%{name: "warfarin"}],
  conditions: [:diabetes, :hypertension],

  # Optional: raw documents (for full verification pipeline)
  documents: [
    %{id: "doc-1", text: "...", date: ~D[2026-01-25], type: :note}
  ]
}
```

## Medication Agent Capabilities

### Drug Name Verification

The agent verifies drug names against RxNorm:

```elixir
# Valid medication
MedicationAgent.verify("Started on metformin", %{source_index: %{medications: [...]}})
# => %{verdict: :entailment, ...}

# Unknown medication (hallucination)
MedicationAgent.verify("Started on madeupdrugxyz", %{})
# => %{verdict: :contradiction, explanations: ["Unknown medication: 'madeupdrugxyz' not found in RxNorm"]}
```

### Dose Validation

Validates doses against therapeutic ranges:

```elixir
# Valid dose
MedicationAgent.verify("metformin 500mg daily", context)
# => %{verdict: :entailment, ...}

# Unsafe dose
MedicationAgent.verify("metformin 5000mg daily", context)
# => %{verdict: :contradiction, explanations: ["Invalid dose for 'metformin': 5000mg outside therapeutic range 500-2550mg"]}
```

### Interaction Detection

Checks for drug-drug interactions:

```elixir
context = %{
  current_medications: [%{name: "warfarin"}],
  source_index: %{medications: [%{text: "aspirin 81mg", doc_id: "note-1"}]}
}

MedicationAgent.verify("Started on aspirin", context)
# => %{verdict: :neutral, explanations: ["Potential interaction: 'aspirin' with [\"warfarin\"]"]}
```

### Contraindication Detection

Checks for medication-condition contraindications:

```elixir
context = %{
  conditions: ["renal_failure"],
  source_index: %{medications: [%{text: "metformin 500mg", doc_id: "note-1"}]}
}

MedicationAgent.verify("Started on metformin", context)
# => %{verdict: :contradiction, explanations: ["Contraindication: 'metformin' with renal_failure"]}
```

## Implementing Custom Agents

Implement the `MedlumLlm.CVL.Agent` behaviour:

```elixir
defmodule MedlumLlm.CVL.MyCustomAgent do
  @behaviour MedlumLlm.CVL.Agent

  @impl true
  def name, do: :my_custom_agent

  @impl true
  def weight, do: 1.0

  @impl true
  def verify(claim, context) do
    # Your verification logic here
    %{
      verdict: :entailment,
      confidence: 0.9,
      explanations: ["Claim verified"],
      evidence: [],
      sub_verdicts: [{:entailment, "Verified against source"}]
    }
  end
end
```

## Aggregating Verdicts

Use the helper function to aggregate sub-verdicts:

```elixir
alias MedlumLlm.CVL.Agent

verdicts = [
  {:entailment, "Drug name verified"},
  {:entailment, "Dose within range"},
  {:neutral, "Frequency not in typical list"}
]

result = Agent.aggregate_verdicts(verdicts)
# => %{verdict: :entailment, confidence: 0.67, ...}
```

Aggregation rules:
- **CONTRADICTION** if any sub-verdict is contradiction
- **ENTAILMENT** if majority are entailment
- **NEUTRAL** otherwise (conservative default)

## Lab Agent

The Lab Agent (weight: 1.2) verifies lab values against LOINC.

### Usage

```elixir
alias MedlumLlm.CVL.LabAgent

claim = "Patient's HbA1c is 7.2%"
context = %{
  demographics: %{age: 55},
  source_index: %{
    labs: [%{text: "HbA1c 7.2%", doc_id: "lab-1"}]
  }
}

result = LabAgent.verify(claim, context)
# => %{
#   verdict: :entailment,
#   confidence: 1.0,
#   explanations: ["Hemoglobin A1c: 7.2 % (high, ref: 4.0-5.6)"],
#   evidence: [%{doc_id: "lab-1", snippet: "HbA1c 7.2%", ...}]
# }
```

### Lab Value Classification

The Lab Agent classifies values against reference ranges:

| Classification | Meaning |
|---------------|---------|
| `normal` | Within reference range |
| `low` | Below reference range |
| `high` | Above reference range |
| `critical_low` | Below critical threshold (urgent) |
| `critical_high` | Above critical threshold (urgent) |

### Physiological Validation

The Lab Agent flags impossible values:

```elixir
# Impossible hemoglobin value
LabAgent.verify("Hemoglobin is 50 g/dL", %{})
# => %{verdict: :contradiction, explanations: ["Impossible value for hemoglobin: 50 outside physiological range 3.0-25.0"]}
```

### Supported Lab Tests

- **Diabetes**: HbA1c, Glucose
- **Hematology**: Hemoglobin, WBC, Platelets
- **Kidney Function**: Creatinine, BUN, eGFR
- **Electrolytes**: Potassium, Sodium
- **Coagulation**: INR
- **Lipids**: Total Cholesterol, LDL, HDL
- **Thyroid**: TSH

## RxNorm Integration

By default, MedlumLlm uses `RxNormStub` for testing. In production, configure
the real RxNorm module:

```elixir
# config/prod.exs
config :medlum_llm,
  rxnorm_module: MedOntologyEx.RxNorm
```

The stub supports common medications for testing:
- metformin, lisinopril, aspirin, atorvastatin
- omeprazole, amlodipine, warfarin, insulin

## LOINC Integration

By default, MedlumLlm uses `LOINCStub` for testing. In production, configure
the real LOINC module:

```elixir
# config/prod.exs
config :medlum_llm,
  loinc_module: MedOntologyEx.LOINC
```

The stub supports common lab tests for testing:
- HbA1c, Glucose (diabetes)
- Hemoglobin, WBC, Platelets (hematology)
- Creatinine, BUN, eGFR (kidney function)
- Potassium, Sodium (electrolytes)
- INR (coagulation)
- Total Cholesterol, LDL, HDL (lipids)
- TSH (thyroid)

## Ontology Agent

The Ontology Agent (weight: 1.0) verifies clinical terminology against SNOMED-CT and ICD-10.

### Usage

```elixir
alias MedlumLlm.CVL.OntologyAgent

claim = "Patient diagnosed with type 2 diabetes mellitus"
context = %{
  chief_complaint: "increased thirst and urination",
  source_index: %{
    diagnoses: [%{text: "type 2 diabetes mellitus", doc_id: "note-1"}]
  }
}

result = OntologyAgent.verify(claim, context)
# => %{
#   verdict: :entailment,
#   confidence: 1.0,
#   explanations: ["Diagnosis 'type 2 diabetes mellitus' validated (SNOMED: 44054006, ICD-10: E11.9)"],
#   evidence: [%{doc_id: "note-1", snippet: "type 2 diabetes mellitus", entity_type: :diagnosis}]
# }
```

### Entity Types

The Ontology Agent verifies three types of clinical entities:

| Entity Type | Description | Examples |
|------------|-------------|----------|
| **diagnosis** | Medical conditions/diseases | Type 2 diabetes, hypertension, MI |
| **finding** | Signs and symptoms | Chest pain, dyspnea, fever |
| **procedure** | Medical procedures | CABG, angioplasty, appendectomy |

### Diagnosis Validation

```elixir
# Valid diagnosis with SNOMED-CT mapping
OntologyAgent.verify("Patient diagnosed with hypertension", %{
  source_index: %{diagnoses: [%{text: "hypertension", doc_id: "note-1"}]}
})
# => %{verdict: :entailment, explanations: ["Diagnosis 'hypertension' validated (SNOMED: 38341003, ICD-10: I10)"]}

# Unknown diagnosis (hallucination risk)
OntologyAgent.verify("Patient diagnosed with madeupitis", %{})
# => %{verdict: :neutral, explanations: ["Entity 'madeupitis' not found in source documents"]}
```

### Finding-Diagnosis Relationships

The agent verifies that clinical findings support stated diagnoses:

```elixir
# Chest pain supports myocardial infarction
OntologyAgent.verify("Patient with chest pain diagnosed with myocardial infarction", %{
  source_index: %{
    diagnoses: [
      %{text: "chest pain", doc_id: "note-1"},
      %{text: "myocardial infarction", doc_id: "note-1"}
    ]
  }
})
# => %{verdict: :entailment, explanations: [..., "chest pain supports myocardial infarction"]}
```

### Semantic Fit Validation

When a `chief_complaint` is provided, the agent checks semantic relevance:

```elixir
# Diagnosis fits chief complaint
OntologyAgent.verify("Patient diagnosed with type 2 diabetes mellitus", %{
  chief_complaint: "increased thirst and polyuria",
  source_index: %{diagnoses: [%{text: "type 2 diabetes mellitus", doc_id: "note-1"}]}
})
# => High semantic relevance score, returns :entailment
```

### Supported Diagnoses

Common diagnoses with SNOMED-CT and ICD-10 mappings:

- **Metabolic**: Type 1/2 diabetes mellitus
- **Cardiovascular**: Hypertension, MI, CHF, atrial fibrillation, stroke
- **Respiratory**: Pneumonia, asthma, COPD
- **Renal**: Chronic kidney disease

### Abbreviations

The stub recognizes common clinical abbreviations:

| Abbreviation | Full Term | SNOMED ID |
|--------------|-----------|-----------|
| MI | Myocardial infarction | 22298006 |
| CHF | Congestive heart failure | 42343007 |
| CKD | Chronic kidney disease | 709044004 |
| COPD | Chronic obstructive pulmonary disease | 13645005 |
| CVA | Cerebrovascular accident (stroke) | 230690007 |
| CABG | Coronary artery bypass graft | 232717009 |
| PCI | Percutaneous coronary intervention | 415070008 |

## SNOMED-CT Integration

By default, MedlumLlm uses `SNOMEDStub` for testing. In production, configure
the real SNOMED module:

```elixir
# config/prod.exs
config :medlum_llm,
  snomed_module: MedOntologyEx.SNOMED
```

The stub provides:
- Diagnosis lookup with SNOMED concept IDs
- Finding lookup (signs and symptoms)
- Procedure lookup
- SNOMED to ICD-10 mapping
- Finding-diagnosis association checking
- Semantic relevance scoring

## ICD-10 Integration

By default, MedlumLlm uses `ICD10Stub` for testing. In production, configure
the real ICD-10 module:

```elixir
# config/prod.exs
config :medlum_llm,
  icd10_module: MedOntologyEx.ICD10
```

The stub provides:
- Term-to-code lookup
- Code validation
- Description retrieval
- Chapter and category information
- Category comparison (for code grouping)

## Temporal Agent

The Temporal Agent (weight: 0.8) verifies timeline consistency and temporal plausibility.
It has a lower weight because temporal information in clinical text is often ambiguous.

### Usage

```elixir
alias MedlumLlm.CVL.TemporalAgent

claim = "Patient was diagnosed 2 days ago and has had symptoms for 3 weeks"
context = %{document_dates: [~D[2026-01-25]]}

result = TemporalAgent.verify(claim, context)
# => %{
#   verdict: :entailment,
#   confidence: 1.0,
#   explanations: ["Duration 'for 3 weeks' is plausible"],
#   evidence: [],
#   sub_verdicts: [{:entailment, "Duration 'for 3 weeks' is plausible"}]
# }
```

### Temporal Entity Extraction

The agent extracts various temporal entities from text:

```elixir
# Relative dates
TemporalAgent.extract_temporal_entities("Started 2 days ago")
# => [%{type: :relative_past, parsed: %{offset_days: -2, reference: :document_date}, ...}]

# Durations
TemporalAgent.extract_temporal_entities("Symptoms for 3 weeks")
# => [%{type: :duration, parsed: %{duration_days: 21}, ...}]

# Absolute dates
TemporalAgent.extract_temporal_entities("Seen on January 15, 2026")
# => [%{type: :absolute_date, parsed: %{date: ~D[2026-01-15]}, ...}]

# Sequence indicators
TemporalAgent.extract_temporal_entities("Then developed fever")
# => [%{type: :sequence, parsed: %{sequence: "then"}, ...}]
```

### Supported Temporal Patterns

| Pattern Type | Examples | Extraction |
|-------------|----------|------------|
| Relative past | "2 days ago", "yesterday", "last week" | Offset in days from document date |
| Relative present | "today" | Same as document date |
| Duration | "for 3 weeks", "over 2 months" | Duration in days |
| Absolute date | "January 15, 2026", "01/15/2026" | Parsed Date struct |
| Sequence | "then", "after", "before", "following" | Sequence indicator |
| Event start | "started", "began", "commenced" | Event start marker |
| Event end | "ended", "stopped", "discontinued" | Event end marker |
| Age reference | "at age 45", "since childhood" | Age in years or reference |

### Verification Checks

The Temporal Agent performs three types of verification:

**1. Chronological Consistency**

Checks that events appear in logical temporal order:

```elixir
# Consistent timeline
TemporalAgent.verify("Diagnosed 1 week ago, started treatment 3 days ago", %{})
# => %{verdict: :entailment, ...}

# Timeline would flag issues if events were inconsistent
```

**2. Duration Plausibility**

Validates that durations are within reasonable bounds:

```elixir
# Plausible duration
TemporalAgent.verify("Symptoms for 2 weeks", %{})
# => %{verdict: :entailment, explanations: ["Duration 'for 2 weeks' is plausible"]}

# Implausible duration (>50 years)
TemporalAgent.verify("Symptoms for 100 years", %{})
# => %{verdict: :contradiction, explanations: ["Implausibly long duration: for 100 years"]}
```

**3. Treatment Timing**

Verifies that treatment events occur in logical order:

```elixir
# Valid timing: started before ended
TemporalAgent.verify("Started medication 2 weeks ago, ended treatment yesterday", %{
  document_dates: [~D[2026-01-25]]
})
# => %{verdict: :entailment, explanations: ["Treatment timing valid: started before ended"]}
```

### Context Shape

The `context` map can include:

```elixir
%{
  # Reference dates for resolving relative times (uses first date)
  document_dates: [~D[2026-01-25], ~D[2026-01-20]],

  # Optional: diagnoses for progression validation
  diagnoses: [%{name: "diabetes", onset: ~D[2025-01-01]}],

  # Optional: treatments for timing validation
  treatments: [%{name: "metformin", start_date: ~D[2025-06-01]}]
}
```

### Duration Limits

The agent flags durations exceeding physiologically plausible bounds:

| Duration | Limit | Verdict |
|----------|-------|---------|
| Days | 0-18,250 (50 years) | :entailment |
| Weeks | 0-2,607 (50 years) | :entailment |
| Months | 0-600 (50 years) | :entailment |
| Years | 0-50 | :entailment |
| > 50 years | Any | :contradiction |

## Differential Agent

The Differential Agent (weight: 1.0) verifies symptom-diagnosis mapping and detects red flags.
It checks that stated symptoms support given diagnoses and flags potential missed diagnoses.

### Usage

```elixir
alias MedlumLlm.CVL.DifferentialAgent

claim = "Patient with chest pain and dyspnea diagnosed with myocardial infarction"
context = %{
  source_index: %{
    diagnoses: [%{text: "myocardial infarction", doc_id: "note-1"}],
    findings: [
      %{text: "chest pain", doc_id: "note-1"},
      %{text: "dyspnea", doc_id: "note-1"}
    ]
  }
}

result = DifferentialAgent.verify(claim, context)
# => %{
#   verdict: :entailment,
#   confidence: 1.0,
#   explanations: ["Supporting symptoms present for myocardial infarction: chest pain, dyspnea"],
#   evidence: [%{doc_id: "note-1", snippet: "myocardial infarction", entity_type: :diagnosis}, ...]
# }
```

### Symptom Extraction

The agent extracts symptoms from text using pattern matching:

```elixir
# Extract symptoms from claim
DifferentialAgent.extract_symptoms("Patient has chest pain, dyspnea, and nausea")
# => [
#   %{name: "chest pain", raw_text: "chest pain"},
#   %{name: "dyspnea", raw_text: "dyspnea"},
#   %{name: "nausea", raw_text: "nausea"}
# ]

# Normalizes abbreviations
DifferentialAgent.extract_symptoms("SOB and tiredness")
# => [%{name: "dyspnea", raw_text: "dyspnea"}, %{name: "fatigue", raw_text: "fatigue"}]
```

### Supported Symptoms

Common symptoms recognized by the agent:

| Category | Symptoms |
|----------|----------|
| Cardiac | chest pain, palpitations, syncope, diaphoresis |
| Respiratory | dyspnea (SOB), cough |
| Neurological | headache, dizziness, weakness, confusion |
| Gastrointestinal | nausea, vomiting, abdominal pain |
| Constitutional | fever, fatigue, weight loss/gain |
| Musculoskeletal | back pain, joint pain, leg pain |
| Other | edema, rash, blurred vision, polyuria, polydipsia |

### Diagnosis Extraction

The agent extracts diagnoses using common patterns:

```elixir
# Extracts from "diagnosed with" pattern
DifferentialAgent.extract_diagnoses("Patient diagnosed with pneumonia")
# => [%{name: "pneumonia", raw_text: "pneumonia"}]

# Recognizes abbreviations
DifferentialAgent.extract_diagnoses("Assessment: MI, CHF")
# => [%{name: "myocardial infarction", ...}, %{name: "heart failure", ...}]
```

### Supported Diagnoses

The DifferentialDB stub includes mappings for common diagnoses:

| Category | Diagnoses |
|----------|-----------|
| Cardiac | Myocardial infarction (MI), heart failure (CHF), hypertension |
| Respiratory | Pneumonia, COPD, asthma, pulmonary embolism (PE) |
| Neurological | Stroke (CVA), meningitis |
| Metabolic | Diabetes |
| Vascular | Deep vein thrombosis (DVT) |
| Infectious | Sepsis |
| Surgical | Appendicitis |

### Symptom-Diagnosis Verification

The agent verifies that stated symptoms support the diagnosis:

```elixir
# Symptoms match diagnosis
DifferentialAgent.verify("Patient with fever and cough diagnosed with pneumonia", %{
  source_index: %{
    diagnoses: [%{text: "pneumonia", doc_id: "note-1"}],
    findings: [%{text: "fever", doc_id: "note-1"}, %{text: "cough", doc_id: "note-1"}]
  }
})
# => %{verdict: :entailment, explanations: ["Supporting symptoms present for pneumonia: cough, fever"]}

# No matching symptoms
DifferentialAgent.verify("Patient with headache diagnosed with appendicitis", %{
  source_index: %{
    diagnoses: [%{text: "appendicitis", doc_id: "note-1"}],
    findings: [%{text: "headache", doc_id: "note-1"}]
  }
})
# => %{verdict: :neutral, explanations: ["No matching symptoms found for appendicitis"]}
```

### Red Flag Detection

The agent identifies red flag symptom combinations that require workup:

| Red Flag Symptom | Requires Workup For |
|-----------------|---------------------|
| Chest pain | MI, pulmonary embolism |
| Syncope | Arrhythmia, stroke |
| Fever (with headache) | Meningitis, sepsis |
| Weakness (sudden) | Stroke |

Red flags are addressed when the corresponding workup diagnoses are included:

```elixir
# Red flag addressed by diagnosis
DifferentialAgent.verify("Patient with chest pain diagnosed with myocardial infarction", %{
  source_index: %{
    diagnoses: [%{text: "myocardial infarction", doc_id: "note-1"}],
    findings: [%{text: "chest pain", doc_id: "note-1"}]
  }
})
# => Red flag for chest pain is satisfied since MI is in the workup
```

### Context Shape

The `context` map for the Differential Agent should include:

```elixir
%{
  source_index: %{
    # Diagnoses from source documents
    diagnoses: [
      %{doc_id: "doc-1", text: "myocardial infarction"}
    ],
    # Clinical findings (symptoms) from source documents
    findings: [
      %{doc_id: "doc-1", text: "chest pain"},
      %{doc_id: "doc-1", text: "dyspnea"}
    ]
  }
}
```

### Source Grounding

The Differential Agent follows source-grounded verification:

- **ENTAILMENT**: Symptoms support diagnosis AND both found in source documents
- **CONTRADICTION**: Symptoms contradict diagnosis OR red flags not addressed
- **NEUTRAL**: Cannot verify (diagnosis or symptoms not in source, no mapping data)

## DifferentialDB Integration

By default, MedlumLlm uses `DifferentialDB` stub for testing. In production, configure
the real DifferentialDB module:

```elixir
# config/prod.exs
config :medlum_llm,
  differential_db_module: MedOntologyEx.DifferentialDB
```

The stub provides:
- Symptom-diagnosis mappings for 13 common diagnoses
- Supporting symptom lists for each diagnosis
- Red flag detection for 4 critical symptoms
- Contradicting symptom detection (extensible)

## Performance Targets

| Metric | Target | Notes |
|--------|--------|-------|
| Hallucination Detection | >95% | Recall on known hallucinations |
| Precision | >85% | Avoid alert fatigue |
| Latency | <2s | 95th percentile verification time |
| Throughput | >10 claims/sec | Batch verification rate |

## Related Documentation

- [CVL Design](../docs/02_cvl_design.md) - Full architecture
- [CVL Measurements](./cvl_measurements.md) - Forge measurement integration
- [ADR-003: CVL Multi-Agent Architecture](../docs/adrs/ADR-003-cvl-agents.md)
