# Medical Dataset Workflow Example
#
# This example demonstrates the complete workflow for loading,
# validating, and managing medical datasets with lineage tracking.
#
# Run with: mix run examples/medical_workflow.exs

alias MedlumLlm.Datasets.{Loaders, CVLTraining, Validators, Metadata}
alias DatasetsEx.Dataset

IO.puts("""
===========================================
Medical Dataset Workflow Example
===========================================
""")

# -------------------------------------------
# 1. List Available Medical Datasets
# -------------------------------------------
IO.puts("1. Available Medical Datasets")
IO.puts("-" |> String.duplicate(40))

datasets = Loaders.list_datasets()
IO.puts("Found #{length(datasets)} medical datasets:")

for dataset <- datasets do
  config = Loaders.get_config(dataset)
  IO.puts("  - #{dataset}: #{config.task} (#{config.clinical_area})")
end

IO.puts("")

# -------------------------------------------
# 2. List Datasets by Task Type
# -------------------------------------------
IO.puts("2. Datasets by Task Type")
IO.puts("-" |> String.duplicate(40))

for task <- [:mcq, :binary_qa, :ner, :reasoning] do
  task_datasets = Loaders.list_by_task(task)
  IO.puts("  #{task}: #{inspect(task_datasets)}")
end

IO.puts("")

# -------------------------------------------
# 3. Create Mock Medical Dataset for Demo
# -------------------------------------------
IO.puts("3. Creating Sample MCQ Dataset")
IO.puts("-" |> String.duplicate(40))

mcq_items = [
  %{
    id: "mcq_001",
    question: "What is the mechanism of action of metformin?",
    options: [
      "Increases insulin secretion from pancreatic beta cells",
      "Decreases hepatic gluconeogenesis",
      "Blocks intestinal glucose absorption",
      "Increases peripheral glucose uptake"
    ],
    correct_answer: "B",
    subject: "pharmacology"
  },
  %{
    id: "mcq_002",
    question: "Which medication is first-line for type 2 diabetes?",
    options: [
      "Glipizide",
      "Metformin",
      "Insulin glargine",
      "Pioglitazone"
    ],
    correct_answer: "B",
    subject: "pharmacology"
  },
  %{
    id: "mcq_003",
    question: "What is the primary concern with metformin in renal impairment?",
    options: [
      "Hypoglycemia",
      "Lactic acidosis",
      "Weight gain",
      "Hyperkalemia"
    ],
    correct_answer: "B",
    subject: "pharmacology"
  }
]

dataset = Dataset.new("sample_medqa",
  data: mcq_items,
  schema: :medical_mcq,
  metadata: Metadata.build(
    %{clinical_area: "pharmacology", task: :mcq, phi_status: :none, access_level: :public},
    %{hf_repo: "demo/medqa", hf_split: "test", loaded_at: DateTime.utc_now()}
  )
)

IO.puts("Created dataset: #{dataset.name}")
IO.puts("  Items: #{length(dataset.data)}")
IO.puts("  Schema: #{dataset.schema}")
IO.puts("  Clinical area: #{dataset.metadata.clinical_area}")

IO.puts("")

# -------------------------------------------
# 4. Validate MCQ Format
# -------------------------------------------
IO.puts("4. Validating MCQ Format")
IO.puts("-" |> String.duplicate(40))

{:ok, report} = Validators.validate_mcq(dataset)

IO.puts("Validation Report:")
IO.puts("  Valid: #{report.valid}")
IO.puts("  Total items: #{report.total_items}")
IO.puts("  Valid items: #{report.valid_items}")
IO.puts("  Invalid items: #{report.invalid_items}")

if length(report.errors) > 0 do
  IO.puts("  Errors: #{inspect(report.errors)}")
end

IO.puts("")

# -------------------------------------------
# 5. Full Quality Check
# -------------------------------------------
IO.puts("5. Full Quality Check")
IO.puts("-" |> String.duplicate(40))

{:ok, quality_report} = Validators.full_quality_check(dataset, :mcq)

IO.puts("Quality Report:")
IO.puts("  Format: #{quality_report.format}")
IO.puts("  Overall valid: #{quality_report.overall_valid}")
IO.puts("  Duplicate rate: #{Float.round(quality_report.duplicates.duplicate_rate * 100, 2)}%")

distribution = quality_report.distribution.distribution
IO.puts("  Answer distribution:")
for {answer, stats} <- distribution do
  IO.puts("    #{answer}: #{stats.count} (#{Float.round(stats.percentage, 1)}%)")
end

IO.puts("")

# -------------------------------------------
# 6. Create CVL Training Data
# -------------------------------------------
IO.puts("6. Creating CVL Training Data")
IO.puts("-" |> String.duplicate(40))

positive_samples = [
  %{
    premise: "Patient prescribed metformin 500mg twice daily.",
    hypothesis: "Patient takes metformin for diabetes management.",
    evidence: ["Metformin is a diabetes medication"]
  },
  %{
    premise: "Patient on lisinopril 10mg daily for hypertension.",
    hypothesis: "Patient is being treated for high blood pressure.",
    evidence: ["Lisinopril is an ACE inhibitor for hypertension"]
  }
]

negative_samples = [
  %{
    premise: "Patient prescribed metformin 500mg twice daily.",
    hypothesis: "Patient takes metformin 1000mg once daily.",
    evidence: ["Dose mismatch: 500mg BID vs 1000mg daily", "Total daily dose same but regimen differs"]
  },
  %{
    premise: "Lab shows HbA1c of 7.2%.",
    hypothesis: "Patient has well-controlled diabetes with HbA1c under 6.5%.",
    evidence: ["HbA1c 7.2% is above the 6.5% threshold"]
  }
]

neutral_samples = [
  %{
    premise: "Patient currently on metformin 500mg BID.",
    hypothesis: "Patient may need insulin in the future.",
    evidence: ["No direct relationship established"]
  }
]

{:ok, cvl_dataset} = CVLTraining.create(:medication, "v1.0.0",
  positive_samples: positive_samples,
  negative_samples: negative_samples,
  neutral_samples: neutral_samples,
  ontology_sources: ["RxNorm_2026AA"]
)

IO.puts("Created CVL training dataset: #{cvl_dataset.name}")
IO.puts("  Total samples: #{length(cvl_dataset.data)}")
IO.puts("  Agent type: #{cvl_dataset.metadata.agent_type}")
IO.puts("  Sample counts:")
IO.puts("    Entailment: #{cvl_dataset.metadata.sample_counts.entailment}")
IO.puts("    Contradiction: #{cvl_dataset.metadata.sample_counts.contradiction}")
IO.puts("    Neutral: #{cvl_dataset.metadata.sample_counts.neutral}")

IO.puts("")

# -------------------------------------------
# 7. Validate CVL Format
# -------------------------------------------
IO.puts("7. Validating CVL Format")
IO.puts("-" |> String.duplicate(40))

{:ok, cvl_report} = Validators.validate_cvl(cvl_dataset)

IO.puts("CVL Validation Report:")
IO.puts("  Valid: #{cvl_report.valid}")
IO.puts("  Total items: #{cvl_report.total_items}")
IO.puts("  Valid items: #{cvl_report.valid_items}")

IO.puts("")

# -------------------------------------------
# 8. Stratified Split
# -------------------------------------------
IO.puts("8. Stratified Split by Verdict")
IO.puts("-" |> String.duplicate(40))

# For demo, create larger dataset
larger_samples =
  for i <- 1..30 do
    verdict = Enum.at([:entailment, :contradiction, :neutral], rem(i, 3))
    %{
      id: "sample_#{i}",
      premise: "Premise #{i}",
      hypothesis: "Hypothesis #{i}",
      verdict: verdict,
      agent_type: :medication,
      evidence: [],
      ontology_codes: [],
      confidence: 1.0
    }
  end

large_cvl = Dataset.new("large_cvl",
  data: larger_samples,
  schema: :medical_cvl,
  metadata: %{agent_type: :medication}
)

{train, test} = CVLTraining.split(large_cvl, ratio: 0.8, seed: 42)

IO.puts("Split results:")
IO.puts("  Train size: #{length(train.data)}")
IO.puts("  Test size: #{length(test.data)}")

train_verdicts = Enum.frequencies_by(train.data, & &1.verdict)
test_verdicts = Enum.frequencies_by(test.data, & &1.verdict)

IO.puts("  Train verdict distribution: #{inspect(train_verdicts)}")
IO.puts("  Test verdict distribution: #{inspect(test_verdicts)}")

IO.puts("")

# -------------------------------------------
# 9. Create Lineage References
# -------------------------------------------
IO.puts("9. Lineage Tracking")
IO.puts("-" |> String.duplicate(40))

# Create artifact reference
ref = DatasetsEx.artifact_ref(dataset)

IO.puts("Artifact Reference:")
IO.puts("  ID: #{ref.artifact_id}")
IO.puts("  Type: #{ref.type}")
IO.puts("  URI: #{ref.uri}")
IO.puts("  Checksum: #{ref.checksum |> String.slice(0..15)}...")

# CVL artifact reference
cvl_ref = CVLTraining.artifact_ref(cvl_dataset)

IO.puts("")
IO.puts("CVL Artifact Reference:")
IO.puts("  ID: #{cvl_ref.artifact_id}")
IO.puts("  Type: #{cvl_ref.type}")

# Create lineage edge
edge = DatasetsEx.lineage_edge(ref, cvl_ref,
  relationship: "derived_from",
  metadata: %{operation: "cvl_training_extraction"}
)

IO.puts("")
IO.puts("Lineage Edge:")
IO.puts("  Source: #{edge.source_id |> String.slice(0..7)}...")
IO.puts("  Target: #{edge.target_id |> String.slice(0..7)}...")
IO.puts("  Relationship: #{edge.relationship}")

IO.puts("")

# -------------------------------------------
# 10. Sample Validation
# -------------------------------------------
IO.puts("10. Individual Sample Validation")
IO.puts("-" |> String.duplicate(40))

valid_sample = %{
  premise: "Patient is on aspirin 81mg daily.",
  hypothesis: "Patient takes aspirin for cardiovascular protection.",
  verdict: :entailment
}

case CVLTraining.validate_sample(valid_sample) do
  {:ok, _} -> IO.puts("Valid sample: PASSED")
  {:error, errors} -> IO.puts("Valid sample: FAILED - #{inspect(errors)}")
end

invalid_sample = %{
  premise: "Patient is on aspirin.",
  # Missing hypothesis and verdict
}

case CVLTraining.validate_sample(invalid_sample) do
  {:ok, _} -> IO.puts("Invalid sample: Unexpectedly passed")
  {:error, errors} -> IO.puts("Invalid sample: Correctly rejected - #{Enum.join(errors, ", ")}")
end

IO.puts("")

# -------------------------------------------
# Summary
# -------------------------------------------
IO.puts("""
===========================================
Workflow Complete!
===========================================

Key capabilities demonstrated:
1. Listing and querying medical datasets
2. Creating datasets with medical metadata
3. MCQ format validation
4. Full quality checks with profiling
5. CVL training data creation
6. CVL format validation
7. Stratified splitting by verdict
8. Lineage tracking with artifact references
9. Individual sample validation

For more information, see:
- guides/medical_datasets.md
- guides/cvl_training.md
""")
