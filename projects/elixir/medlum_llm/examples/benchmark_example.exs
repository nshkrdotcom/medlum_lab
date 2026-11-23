#!/usr/bin/env elixir
# Benchmark Examples for MedlumLlm
#
# Run with: mix run examples/benchmark_example.exs

alias MedlumLlm.Eval.{Benchmarks, Baselines, Prompts}

IO.puts("=== MedlumLlm Benchmark Example ===\n")

# -----------------------------------------------------------------------------
# 1. List Available Benchmarks
# -----------------------------------------------------------------------------

IO.puts("1. Available Benchmarks:")
for name <- Benchmarks.list() do
  {:ok, config} = Benchmarks.get(name)
  IO.puts("   #{name}")
  IO.puts("     #{config.description}")
end
IO.puts("")

# -----------------------------------------------------------------------------
# 2. Get Benchmark Configuration
# -----------------------------------------------------------------------------

IO.puts("2. MedQA Zero-Shot Configuration:")
{:ok, config} = Benchmarks.get(:medqa_zero_shot)
IO.puts("   Name: #{config.name}")
IO.puts("   Dataset: #{config.dataset}")
IO.puts("   Split: #{config.split}")
IO.puts("   Task: #{config.task}")
IO.puts("   Prompt Template: #{config.prompt_template}")
IO.puts("   Metrics: #{inspect(config.metrics)}")
IO.puts("   Default Models: #{inspect(config.default_models)}")
IO.puts("   Timeout: #{config.timeout_ms}ms")
IO.puts("")

# -----------------------------------------------------------------------------
# 3. Benchmarks by Task Type
# -----------------------------------------------------------------------------

IO.puts("3. Benchmarks by Task Type:")
for task <- [:mcq, :mcq_cot, :binary_qa, :cvl_verification, :reasoning] do
  benchmarks = Benchmarks.by_task(task)
  if length(benchmarks) > 0 do
    IO.puts("   #{task}: #{inspect(benchmarks)}")
  end
end
IO.puts("")

# -----------------------------------------------------------------------------
# 4. Benchmarks by Dataset
# -----------------------------------------------------------------------------

IO.puts("4. Benchmarks by Dataset:")
for dataset <- [:medqa, :pubmedqa, :medmcqa, :mmlu_medical, :reasonmed] do
  benchmarks = Benchmarks.by_dataset(dataset)
  if length(benchmarks) > 0 do
    IO.puts("   #{dataset}: #{inspect(benchmarks)}")
  end
end
IO.puts("")

# -----------------------------------------------------------------------------
# 5. Benchmark Features
# -----------------------------------------------------------------------------

IO.puts("5. Benchmark Features:")

IO.puts("   Streaming benchmarks:")
for name <- Benchmarks.list() do
  if Benchmarks.streaming?(name) do
    IO.puts("     - #{name}")
  end
end
IO.puts("")

IO.puts("   Benchmarks with reasoning_quality metric:")
for name <- Benchmarks.with_metric(:reasoning_quality) do
  IO.puts("     - #{name}")
end
IO.puts("")

# -----------------------------------------------------------------------------
# 6. Published Baselines
# -----------------------------------------------------------------------------

IO.puts("6. MedQA Published Baselines:")
baselines = Baselines.get(:medqa)
IO.puts("   Model                  Accuracy    Source")
IO.puts("   " <> String.duplicate("-", 60))

# Sort by accuracy descending
sorted = baselines
         |> Enum.sort_by(fn {_k, v} -> v.accuracy end, :desc)

for {model, data} <- sorted do
  model_str = String.pad_trailing(to_string(model), 20)
  acc_str = String.pad_trailing("#{Float.round(data.accuracy * 100, 1)}%", 12)
  IO.puts("   #{model_str} #{acc_str} #{data.source}")
end
IO.puts("")

# -----------------------------------------------------------------------------
# 7. Baseline Comparison
# -----------------------------------------------------------------------------

IO.puts("7. Comparing Against Baselines:")

# Simulate evaluation results
my_results = [
  {:biomistral_7b, 0.62},   # Slightly above baseline of 0.61
  {:openbio_8b, 0.73},      # Below baseline of 0.75
  {:meditron_7b, 0.65},     # Above baseline of 0.63
  {:ii_medical_8b, 0.86},   # Below baseline of 0.88
  {:gpt4, 0.87}             # Above baseline of 0.86
]

IO.puts("   Simulated Results vs Baselines (+/-5% tolerance):")
IO.puts("")

for {model, accuracy} <- my_results do
  comparison = Baselines.format_comparison(:medqa, model, accuracy)
  status = Baselines.compare(:medqa, model, accuracy)

  status_str = case status do
    :match -> "[MATCH]    "
    :above -> "[ABOVE]    "
    :below -> "[BELOW]    "
    :no_baseline -> "[NO BASELINE]"
  end

  IO.puts("   #{String.pad_trailing(to_string(model), 16)} #{status_str} #{comparison}")
end
IO.puts("")

# -----------------------------------------------------------------------------
# 8. Summary Table
# -----------------------------------------------------------------------------

IO.puts("8. Baseline Summary Table (MedQA):")
table = Baselines.summary_table(:medqa)

IO.puts("   Rank  Model               Accuracy")
IO.puts("   " <> String.duplicate("-", 45))

table
|> Enum.with_index(1)
|> Enum.each(fn {row, idx} ->
  model_str = String.pad_trailing(to_string(row.model), 20)
  IO.puts("   #{idx}.    #{model_str} #{row.accuracy_pct}")
end)
IO.puts("")

# -----------------------------------------------------------------------------
# 9. Prompt Templates
# -----------------------------------------------------------------------------

IO.puts("9. Prompt Templates:")
IO.puts("   Available: #{inspect(Prompts.list_templates())}")
IO.puts("")

sample = %{
  question: "A 45-year-old woman presents with fatigue, weight gain, and cold intolerance. Which test is most appropriate?",
  options: [
    "A. Complete blood count",
    "B. Thyroid stimulating hormone (TSH)",
    "C. Fasting glucose",
    "D. Liver function tests"
  ],
  answer: "B"
}

IO.puts("   Sample Question:")
IO.puts("     #{String.slice(sample.question, 0..60)}...")
IO.puts("")

IO.puts("   Zero-Shot MCQ Prompt:")
prompt = Prompts.format(:zero_shot_mcq, sample)
# Indent the prompt for display
prompt_lines = String.split(prompt, "\n")
for line <- prompt_lines do
  IO.puts("     #{line}")
end
IO.puts("")

# -----------------------------------------------------------------------------
# 10. Response Parsing
# -----------------------------------------------------------------------------

IO.puts("10. Response Parsing:")

test_responses = [
  {"A", "Direct letter"},
  {"B", "Direct letter"},
  {"The answer is B", "Natural language"},
  {"Answer: C", "Labeled format"},
  {"(D)", "Parenthesized"},
  {"A. Because the symptoms suggest cardiac issues", "Letter with explanation"},
  {"Based on the clinical presentation, B is the most appropriate", "Embedded letter"},
  {"I think the answer could be either A or B", "Ambiguous (returns first)"}
]

IO.puts("   Input Response                               Parsed")
IO.puts("   " <> String.duplicate("-", 65))

for {response, desc} <- test_responses do
  parsed = Prompts.parse_mcq_response(response)
  response_str = String.pad_trailing("\"#{String.slice(response, 0..38)}\"", 42)
  parsed_str = if parsed, do: parsed, else: "nil"
  IO.puts("   #{response_str} -> #{parsed_str}")
end
IO.puts("")

# -----------------------------------------------------------------------------
# 11. Chain-of-Thought Parsing
# -----------------------------------------------------------------------------

IO.puts("11. Chain-of-Thought Response Parsing:")

cot_response = """
Let me analyze this step by step:
1. The patient has fatigue, weight gain, and cold intolerance
2. These are classic symptoms of hypothyroidism
3. TSH is the screening test for thyroid disorders
Therefore, the answer is B.
"""

result = Prompts.parse_cot_response(cot_response)
IO.puts("   Reasoning extracted:")
IO.puts("     #{String.slice(result.reasoning, 0..60)}...")
IO.puts("   Answer extracted: #{result.answer}")
IO.puts("")

# -----------------------------------------------------------------------------
# 12. Binary QA Parsing (PubMedQA)
# -----------------------------------------------------------------------------

IO.puts("12. Binary QA Response Parsing (PubMedQA):")

binary_responses = [
  "yes",
  "no",
  "maybe",
  "Yes, the study supports this conclusion",
  "No, because the evidence is insufficient",
  "It's uncertain based on the available data"
]

for response <- binary_responses do
  parsed = Prompts.parse_binary_response(response)
  IO.puts("   \"#{String.slice(response, 0..40)}\" -> #{parsed}")
end
IO.puts("")

# -----------------------------------------------------------------------------
# 13. Sample Validation
# -----------------------------------------------------------------------------

IO.puts("13. Sample Validation:")

valid_sample = %{question: "What is X?", options: ["A", "B", "C", "D"]}
invalid_sample = %{question: "What is X?"}  # Missing options

case Prompts.validate_sample(:zero_shot_mcq, valid_sample) do
  :ok -> IO.puts("   Valid MCQ sample: OK")
  {:error, {:missing_fields, fields}} -> IO.puts("   Valid sample missing: #{inspect(fields)}")
end

case Prompts.validate_sample(:zero_shot_mcq, invalid_sample) do
  :ok -> IO.puts("   Invalid sample: OK (unexpected)")
  {:error, {:missing_fields, fields}} -> IO.puts("   Invalid sample missing: #{inspect(fields)}")
end
IO.puts("")

# -----------------------------------------------------------------------------
# 14. Options Formatting
# -----------------------------------------------------------------------------

IO.puts("14. Options Formatting:")

raw_options = ["Hypertension", "Diabetes", "Asthma", "Arthritis"]
IO.puts("   Raw options: #{inspect(raw_options)}")

formatted = Prompts.format_options(raw_options)
IO.puts("   Formatted options:")
for opt <- formatted do
  IO.puts("     #{opt}")
end
IO.puts("")

IO.puts("   Options have letters?")
IO.puts("     Raw: #{Prompts.options_have_letters?(raw_options)}")
IO.puts("     Formatted: #{Prompts.options_have_letters?(formatted)}")
IO.puts("")

# -----------------------------------------------------------------------------
# 15. Experiment Configuration Example
# -----------------------------------------------------------------------------

IO.puts("15. Experiment Configuration (crucible_harness):")

IO.puts("""
   # Example experiment configuration:

   defmodule MyMedQAExperiment do
     use CrucibleHarness.Experiment

     dataset :medqa
     conditions [
       %{name: "biomistral", fn: &eval_biomistral/1},
       %{name: "openbio", fn: &eval_openbio/1}
     ]

     metrics [:accuracy, :latency_p50, :latency_p95]

     defp eval_biomistral(sample) do
       prompt = MedlumLlm.Eval.Prompts.format(:zero_shot_mcq, sample)
       start = System.monotonic_time(:millisecond)
       {:ok, response} = MedlumLlm.Chat.chat(prompt, model: :biomistral_7b)
       latency = System.monotonic_time(:millisecond) - start

       predicted = MedlumLlm.Eval.Prompts.parse_mcq_response(response)
       correct = predicted == sample.answer

       %{correct: correct, latency_ms: latency, predicted: predicted}
     end
   end
""")

IO.puts("=== Benchmark Examples Complete ===")
