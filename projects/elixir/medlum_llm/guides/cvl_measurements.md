# CVL Measurements Guide

This guide documents the CVL (Clinical Verification Layer) measurement modules and their implementation details.

## Overview

CVL uses a multi-agent verification system where specialized agents verify different aspects of medical claims. Each agent is implemented as a `Forge.Measurement` module with independent caching and dependency management.

## Measurement Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Measurement Dependency Graph                     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Level 0 (Independent)                                                  │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐      │
│  │Medication│ │   Lab    │ │ Ontology │ │ Temporal │ │Differential│     │
│  │  Agent   │ │  Agent   │ │  Agent   │ │  Agent   │ │  Agent   │      │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘      │
│       │            │            │            │            │             │
│       └────────────┴────────────┴────────────┴────────────┘             │
│                                 │                                       │
│                                 ▼                                       │
│  Level 1 (Depends on Level 0)                                          │
│                        ┌────────────────┐                               │
│                        │ AgentConsensus │                               │
│                        └───────┬────────┘                               │
│                                │                                        │
│                                ▼                                        │
│  Level 2 (Depends on Level 1)                                          │
│                        ┌────────────────┐                               │
│                        │  Confidence    │                               │
│                        └────────────────┘                               │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Measurement Behaviour

All CVL measurements implement the `Forge.Measurement` behaviour:

```elixir
@callback compute([Forge.Sample.t()]) :: {:ok, map()} | {:error, term()}
@callback key() :: String.t()
@callback version() :: pos_integer()
@callback dependencies() :: [module()]
```

### Caching Strategy

Measurements are cached by `(sample_id, key, version)`:

```elixir
def key do
  config_hash = :crypto.hash(:md5, inspect(config()))
  |> Base.encode16(case: :lower)
  |> String.slice(0, 8)

  "medication_agent_#{config_hash}"
end

def version, do: 1
```

**Cache Invalidation**:
- Change `version/0` to invalidate all cached results
- Change `config/0` to change the key hash

## Individual Agent Measurements

### MedicationAgent

**Purpose**: Validates medication claims against RxNorm vocabulary.

**Verifies**:
- Drug names (against known drug list)
- Dose reasonableness (typical ranges)
- Frequency patterns (daily, BID, TID, etc.)
- Route of administration

**Example**:
```elixir
# Input claim
"Patient takes metformin 500mg twice daily"

# Output
%{
  verdict: :entailment,
  confidence: 0.9,
  reasoning: "Medication claim verified against RxNorm",
  evidence: [
    %{
      claim_text: "Patient takes metformin 500mg twice daily",
      medication_info: %{
        drug_name: "metformin",
        dose: %{amount: 500.0, unit: "mg"},
        frequency: :twice_daily,
        route: nil
      },
      drug_valid: :valid,
      dose_valid: :valid
    }
  ],
  medications_found: [%{drug_name: "metformin", ...}]
}
```

**Configuration**:
```elixir
%{
  ontology_version: "rxnorm_2024_01",
  confidence_threshold: 0.8,
  verify_doses: true,
  verify_frequencies: true
}
```

### LabAgent

**Purpose**: Validates lab results against LOINC reference ranges.

**Verifies**:
- Test names (glucose, hemoglobin, etc.)
- Value ranges (normal, abnormal, critical)
- Unit consistency
- Interpretation labels

**Reference Ranges**:
```elixir
%{
  "glucose" => %{
    "mg/dl" => %{low: 70, high: 100, critical_low: 40, critical_high: 400}
  },
  "hemoglobin" => %{
    "g/dl" => %{low: 12.0, high: 17.0, critical_low: 7.0, critical_high: 20.0}
  }
}
```

**Output**:
```elixir
%{
  verdict: :entailment,
  confidence: 0.85,
  reasoning: "Lab value verified against reference ranges",
  lab_values_found: [
    %{test_name: "glucose", value: 95.0, unit: "mg/dl"}
  ]
}
```

### OntologyAgent

**Purpose**: Validates diagnoses against SNOMED-CT and ICD-10 ontologies.

**Verifies**:
- Diagnosis terms (known conditions)
- Hierarchical relationships (parent-child)
- Semantic consistency (e.g., not both T1DM and T2DM)
- ICD-10 codes if present

**Knowledge Base Example**:
```elixir
%{
  "diabetes" => %{
    synonyms: ["diabetes mellitus", "dm"],
    subtypes: ["type 1 diabetes", "type 2 diabetes"],
    complications: ["diabetic neuropathy", "diabetic retinopathy"]
  },
  "type 2 diabetes" => %{
    synonyms: ["t2dm", "type ii diabetes"],
    parent: "diabetes",
    risk_factors: ["obesity", "metabolic syndrome"]
  }
}
```

**Semantic Consistency Check**:
```elixir
# Detects mutual exclusion
has_t1dm and has_t2dm -> :contradiction
# "Patient cannot have both Type 1 and Type 2 diabetes"
```

### TemporalAgent

**Purpose**: Validates timeline consistency in clinical claims.

**Verifies**:
- Chronological ordering of events
- Disease progression timelines
- Temporal impossibilities (future dates, negative durations)
- Age plausibility

**Extracted Events**:
```elixir
# Absolute dates
%{type: :absolute_date, date: ~D[2025-01-15], format: :us}

# Relative times
%{type: :relative_time, amount: 3, unit: :weeks, direction: :past}

# Durations
%{type: :duration, amount: 5, unit: :days}

# Ages
%{type: :age, age: 45}
```

**Inconsistency Detection**:
- Future dates in medical history
- Negative durations
- Ages > 120 years
- Contradictory relative times

### DifferentialAgent

**Purpose**: Validates symptom-diagnosis relationships.

**Verifies**:
- Symptoms support stated diagnoses
- Key symptoms present for diagnosis
- No contradicting symptoms
- Clinical presentation consistency

**Knowledge Base**:
```elixir
%{
  "myocardial infarction" => %{
    key_symptoms: ["chest pain", "shortness of breath"],
    supporting_symptoms: ["radiating pain", "sweating", "nausea"],
    contradicting_symptoms: [],
    risk_factors: ["hypertension", "diabetes", "smoking"]
  }
}
```

**Match Scoring**:
```elixir
match_score = key_match_ratio * 0.7 + supporting_match_ratio * 0.3

# Verdict determination
cond do
  contradicting_symptoms_found -> {:contradiction, 0.85}
  key_match_ratio >= 0.5 and match_score >= 0.3 -> {:entailment, 0.8}
  key_match_ratio > 0 -> {:neutral, 0.6}
  true -> {:neutral, 0.5}
end
```

## Consensus Measurement

### AgentConsensus

**Purpose**: Aggregates verdicts from all five agents using weighted voting.

**Weights**:
```elixir
%{
  medication: 1.2,    # Medications often hallucinated
  lab: 1.1,           # Lab values important
  ontology: 1.3,      # Diagnoses most critical
  temporal: 0.9,      # Timeline less critical
  differential: 1.0   # Symptom mapping standard
}
```

**Voting Algorithm**:
```elixir
# For each agent verdict
weighted_vote = weight * confidence

# Aggregate by verdict type
votes = %{
  entailment: sum of entailment weighted votes,
  contradiction: sum of contradiction weighted votes,
  neutral: sum of neutral weighted votes
}

# Select winning verdict
winning_verdict = max(votes)
```

**Veto Rule**:
```elixir
if contradiction_count >= 2 do
  {:contradiction, "Multiple agents detected contradictions (veto applied)"}
end
```

**Output**:
```elixir
%{
  verdict: :entailment,
  confidence: 0.87,
  agreement: 0.8,
  agent_verdicts: %{
    medication: %{verdict: :entailment, confidence: 0.9},
    lab: %{verdict: :entailment, confidence: 0.85},
    ...
  },
  weighted_votes: %{entailment: 4.2, contradiction: 0.0, neutral: 0.8},
  reasoning: "Consensus entailment from 5 agents..."
}
```

## Confidence Measurement

### Confidence

**Purpose**: Computes calibrated confidence score for sample quality assessment.

**Components**:
```elixir
# Agreement score (60% weight)
# How well agents agree on verdict
agreement_score = winning_votes / total_votes

# Strength score (40% weight)
# Average confidence of winning verdict agents
strength_score = weighted_avg(matching_agent_confidences)

# Raw confidence
raw_score = 0.6 * agreement_score + 0.4 * strength_score
```

**Entropy Adjustment**:
```elixir
# High disagreement reduces confidence
entropy = -sum(p * log2(p)) for p in vote_distribution
normalized_entropy = entropy / log2(3)  # Max entropy for 3 classes

adjusted_score = raw_score * (1.0 - 0.2 * normalized_entropy)
```

**Platt Calibration**:
```elixir
# Calibrated via sigmoid transformation
logit = A * (score - 0.5) + B
calibrated_score = 1 / (1 + exp(-logit))
```

**Confidence Levels**:
```elixir
cond do
  calibrated_score >= 0.85 -> :high     # Auto-accept
  calibrated_score >= 0.50 -> :medium   # May need review
  true -> :low                           # Requires human review
end
```

**Output**:
```elixir
%{
  score: 0.78,
  calibrated_score: 0.82,
  components: %{
    agreement_score: 0.8,
    strength_score: 0.9,
    entropy_adjustment: -0.02,
    verdict: :entailment
  },
  confidence_level: :medium,
  reasoning: "Confidence 82.0% (medium): entailment with 80.0% agreement..."
}
```

## Usage Examples

### Computing Measurements

```elixir
alias MedlumLlm.CVL.Measurements.{MedicationAgent, AgentConsensus, Confidence}

# Compute single measurement
{:ok, results} = MedicationAgent.compute([sample])
medication_result = results[sample.id]

# Compute with dependencies (automatic via Forge.Measurement.Orchestrator)
{:ok, results} = Forge.Measurement.Orchestrator.measure_with_dependencies(
  sample.id,
  Confidence,
  []
)
```

### Inspecting Results

```elixir
sample = get_processed_sample("cvl_medqa_openbio_0")

# Check consensus
consensus = sample.measurements.consensus
IO.puts("Verdict: #{consensus.verdict}")
IO.puts("Agreement: #{consensus.agreement}")

# Check individual agents
for {agent, result} <- consensus.agent_verdicts do
  IO.puts("#{agent}: #{result.verdict} (#{result.confidence})")
end

# Check confidence
confidence = sample.measurements.confidence
IO.puts("Confidence: #{confidence.calibrated_score}")
IO.puts("Level: #{confidence.confidence_level}")
```

### Custom Measurements

To create a custom measurement:

```elixir
defmodule MedlumLlm.CVL.Measurements.CustomAgent do
  @behaviour Forge.Measurement

  @impl true
  def compute(samples) do
    results = Enum.map(samples, fn sample ->
      verdict = analyze_sample(sample)
      {sample.id, verdict}
    end)
    |> Map.new()

    {:ok, results}
  end

  @impl true
  def key do
    "custom_agent_v1"
  end

  @impl true
  def version, do: 1

  @impl true
  def dependencies, do: []  # Or list of dependent measurements

  defp analyze_sample(sample) do
    %{
      verdict: :entailment,
      confidence: 0.85,
      reasoning: "Custom analysis result"
    }
  end
end
```

## Performance Considerations

### Caching

- Measurements are cached by `(sample_id, key, version)`
- Same sample + same key/version = cached result
- Increment version to invalidate cache

### Batching

- Measurements process samples in batches
- Configure batch size via `batch_size/0` callback
- Default batch processing improves throughput

### Async Execution

- Measurements can run asynchronously
- Override `async?/0` to return `true`
- Use for I/O-bound operations (API calls, etc.)

```elixir
@impl true
def async?, do: true

@impl true
def timeout, do: 60_000  # 60 seconds
```

## Extending the CVL System

### Adding New Agents

1. Create measurement module implementing `Forge.Measurement`
2. Add to `AgentConsensus.@agent_modules` list
3. Add weight to `AgentConsensus.@agent_weights`
4. Add to pipeline definition

### Customizing Consensus

Override `AgentConsensus` configuration:

```elixir
# In config/config.exs
config :medlum_llm, MedlumLlm.CVL.Measurements.AgentConsensus,
  agent_weights: %{
    medication: 1.5,  # Increase medication weight
    lab: 1.0,
    ontology: 1.2,
    temporal: 0.8,
    differential: 1.0
  },
  min_agents_required: 3,
  contradiction_veto: true
```

## See Also

- [CVL Training Pipeline Guide](cvl_training_pipeline.md)
- [Forge Measurement Documentation](https://hexdocs.pm/forge)
- [Medical Ontology Resources](https://www.nlm.nih.gov/research/umls/)
