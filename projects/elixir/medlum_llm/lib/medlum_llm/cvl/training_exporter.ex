defmodule MedlumLlm.CVL.TrainingExporter do
  @moduledoc """
  Exports CVL verification results for labeling and training.

  The TrainingExporter selects claims that would benefit from human review
  and exports them in a format suitable for the labeling pipeline (Anvil)
  and model training (Forge).

  ## Selection Criteria

  - All `:contradiction` claims (potential hallucinations detected)
  - `:neutral` claims with confidence below threshold (uncertain verification)

  ## Export Format

  JSONL format with minimal data to reduce PHI exposure:

      {"id": "...", "claim_text": "...", "verdict": "contradiction", "confidence": 0.85, "agent_results": [...], "evidence_snippets": [...]}

  ## PHI Considerations

  - Only exports claim text and evidence snippets
  - Does not include full source documents
  - Use additional PII redaction before leaving clinical boundary

  ## Usage

      {:ok, result} = Verifier.verify_summary(summary, docs)
      candidates = TrainingExporter.select_candidates(result.claim_results)
      jsonl = TrainingExporter.to_jsonl(candidates)
      File.write!("training_candidates.jsonl", jsonl)

  """

  @type candidate :: %{
          id: String.t(),
          claim_text: String.t(),
          verdict: :contradiction | :neutral,
          confidence: float(),
          agent_results: [map()],
          evidence_snippets: [String.t()]
        }

  @default_neutral_threshold 0.7

  @doc """
  Select claims that are candidates for labeling/training.

  ## Selection Rules

  - All `:contradiction` claims
  - `:neutral` claims with `confidence < neutral_threshold`

  ## Options

  - `:neutral_threshold` - Confidence threshold for neutral claims (default: 0.7)

  ## Examples

      iex> claim_results = [
      ...>   %{verdict: :contradiction, confidence: 0.9, ...},
      ...>   %{verdict: :neutral, confidence: 0.5, ...},
      ...>   %{verdict: :entailment, confidence: 0.95, ...}
      ...> ]
      iex> candidates = TrainingExporter.select_candidates(claim_results)
      iex> length(candidates)
      2

  """
  @spec select_candidates([MedlumLlm.CVL.Verifier.claim_result()], keyword()) :: [candidate()]
  def select_candidates(claim_results, opts \\ []) do
    neutral_threshold = Keyword.get(opts, :neutral_threshold, @default_neutral_threshold)

    claim_results
    |> Enum.filter(fn result ->
      case result.verdict do
        :contradiction -> true
        :neutral -> result.confidence < neutral_threshold
        :entailment -> false
      end
    end)
    |> Enum.map(&format_candidate/1)
  end

  @doc """
  Export candidates to JSONL format.

  Each line is a valid JSON object with:
  - `id` - Stable claim identifier
  - `claim_text` - The claim text
  - `verdict` - Agent verdict
  - `confidence` - Confidence score
  - `agent_results` - Per-agent verdicts and explanations
  - `evidence_snippets` - Evidence snippets from source documents

  ## Examples

      iex> candidates = [%{id: "c1", claim_text: "...", verdict: :contradiction, ...}]
      iex> jsonl = TrainingExporter.to_jsonl(candidates)
      iex> String.contains?(jsonl, "c1")
      true

  """
  @spec to_jsonl([candidate()]) :: String.t()
  def to_jsonl(candidates) do
    candidates
    |> Enum.map(&to_json_row/1)
    |> Enum.join("\n")
  end

  @doc """
  Export candidates to a list of JSON-encodable maps.

  Useful when you want to process the data further before serialization.

  ## Examples

      iex> candidates = [%{id: "c1", ...}]
      iex> maps = TrainingExporter.to_maps(candidates)
      iex> is_list(maps)
      true

  """
  @spec to_maps([candidate()]) :: [map()]
  def to_maps(candidates) do
    Enum.map(candidates, &to_json_map/1)
  end

  @doc """
  Write candidates to a JSONL file.

  ## Options

  - `:append` - Append to existing file instead of overwriting (default: false)

  ## Examples

      iex> TrainingExporter.write_jsonl(candidates, "/tmp/training.jsonl")
      :ok

  """
  @spec write_jsonl([candidate()], Path.t(), keyword()) :: :ok | {:error, term()}
  def write_jsonl(candidates, path, opts \\ []) do
    jsonl = to_jsonl(candidates)
    mode = if Keyword.get(opts, :append, false), do: [:append, :utf8], else: [:write, :utf8]

    case File.open(path, mode, fn file ->
           IO.write(file, jsonl)

           if Keyword.get(opts, :append, false) do
             IO.write(file, "\n")
           end
         end) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Generate a summary of export candidates.

  ## Examples

      iex> summary = TrainingExporter.summarize(candidates)
      iex> summary.total_count
      5

  """
  @spec summarize([candidate()]) :: map()
  def summarize(candidates) do
    %{
      total_count: length(candidates),
      contradiction_count: Enum.count(candidates, &(&1.verdict == :contradiction)),
      neutral_count: Enum.count(candidates, &(&1.verdict == :neutral)),
      average_confidence:
        if(Enum.empty?(candidates),
          do: 0.0,
          else:
            Float.round(
              Enum.reduce(candidates, 0.0, fn c, acc -> acc + c.confidence end) /
                length(candidates),
              3
            )
        ),
      agents_with_contradictions: count_agent_contradictions(candidates)
    }
  end

  # Format a claim result into a candidate for export
  defp format_candidate(result) do
    %{
      id: result.claim.id,
      claim_text: result.claim.text,
      verdict: result.verdict,
      confidence: result.confidence,
      agent_results: format_agent_results(result.agent_results),
      evidence_snippets: extract_evidence_snippets(result.agent_results)
    }
  end

  # Format agent results for export (minimal data)
  defp format_agent_results(agent_results) do
    Enum.map(agent_results, fn ar ->
      %{
        agent: ar.agent,
        weight: ar.weight,
        verdict: ar.result.verdict,
        confidence: ar.result.confidence,
        explanations: ar.result.explanations
      }
    end)
  end

  # Extract unique evidence snippets from agent results
  defp extract_evidence_snippets(agent_results) do
    agent_results
    |> Enum.flat_map(fn ar ->
      Enum.map(ar.result.evidence || [], fn ev ->
        ev[:snippet] || ev["snippet"] || ""
      end)
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  # Convert a candidate to a JSON-encodable map
  defp to_json_map(candidate) do
    %{
      "id" => candidate.id,
      "claim_text" => candidate.claim_text,
      "verdict" => Atom.to_string(candidate.verdict),
      "confidence" => candidate.confidence,
      "agent_results" =>
        Enum.map(candidate.agent_results, fn ar ->
          %{
            "agent" => Atom.to_string(ar.agent),
            "weight" => ar.weight,
            "verdict" => Atom.to_string(ar.verdict),
            "confidence" => ar.confidence,
            "explanations" => ar.explanations
          }
        end),
      "evidence_snippets" => candidate.evidence_snippets
    }
  end

  # Convert a candidate to a JSON string
  defp to_json_row(candidate) do
    candidate
    |> to_json_map()
    |> Jason.encode!()
  end

  # Count how many contradictions each agent produced
  defp count_agent_contradictions(candidates) do
    candidates
    |> Enum.flat_map(fn c -> c.agent_results end)
    |> Enum.filter(&(&1.verdict == :contradiction))
    |> Enum.reduce(%{}, fn ar, acc ->
      agent_name = ar.agent
      Map.update(acc, agent_name, 1, &(&1 + 1))
    end)
  end
end
