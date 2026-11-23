defmodule MedlumLlm.CVL.Verifier do
  @moduledoc """
  Primary API for Clinical Verification Layer (CVL).

  The Verifier coordinates the full CVL pipeline:

  1. **Claim Extraction**: Split summary into atomic claims (`ClaimExtractor`)
  2. **Source Indexing**: Extract entities from source documents (`SourceIndex`)
  3. **Verification**: Verify each claim via `Consensus`
  4. **Aggregation**: Compute summary-level verdict

  ## Usage

      {:ok, result} = Verifier.verify_summary(
        "Patient started on metformin 500mg. HbA1c is 7.2%.",
        ["Source note: Patient with diabetes started metformin 500mg. Lab: A1c 7.2%."],
        demographics: %{age: 55}
      )

      result.summary_verdict
      #=> :entailment

      result.claim_results
      #=> [
      #=>   %{claim: %{id: "c1", text: "..."}, verdict: :entailment, needs_review: false, ...},
      #=>   %{claim: %{id: "c2", text: "..."}, verdict: :entailment, needs_review: false, ...}
      #=> ]

  ## Summary Verdict Rules

  - `:contradiction` if any claim is `:contradiction` with confidence ≥ 0.7
  - `:neutral` if any claim is `:neutral` or `:contradiction`
  - `:entailment` only if all claims are `:entailment`

  ## Needs Review

  A claim `needs_review: true` when:
  - Verdict is `:contradiction`
  - Verdict is `:neutral`

  These claims should be surfaced to clinical reviewers in the Medlum UX.

  """

  alias MedlumLlm.CVL.{ClaimExtractor, SourceIndex, Consensus}

  @type claim_result :: %{
          claim: ClaimExtractor.claim(),
          verdict: Consensus.verdict(),
          confidence: float(),
          needs_review: boolean(),
          agent_results: [Consensus.agent_result()],
          scores: map()
        }

  @type verification_result :: %{
          summary_verdict: Consensus.verdict(),
          summary_confidence: float(),
          claim_results: [claim_result()],
          claim_count: non_neg_integer(),
          needs_review_count: non_neg_integer(),
          source_index: SourceIndex.index()
        }

  @contradiction_confidence_threshold 0.7

  @doc """
  Verify a generated summary against source documents.

  This is the primary CVL entry point. It:
  1. Extracts atomic claims from the summary
  2. Builds a source index from documents
  3. Verifies each claim via Consensus
  4. Computes an overall summary verdict

  ## Arguments

  - `summary_text` - The generated summary to verify
  - `source_documents` - Source documents (strings or maps with `:id`/`:text`)

  ## Options

  - `:demographics` - Patient demographics for context (default: `%{}`)
  - `:timeout` - Timeout per agent in ms (default: 30000)
  - `:min_claim_length` - Minimum claim length (default: 5)
  - `:max_claim_length` - Maximum claim length (default: 500)

  ## Returns

  `{:ok, result}` with:
  - `summary_verdict` - Overall verdict (`:entailment`, `:contradiction`, `:neutral`)
  - `summary_confidence` - Aggregated confidence
  - `claim_results` - Per-claim verification results
  - `claim_count` - Total number of claims
  - `needs_review_count` - Number of claims needing review
  - `source_index` - The built source index

  ## Examples

      iex> summary = "Patient on metformin 500mg for diabetes."
      iex> docs = ["Patient with type 2 diabetes started on metformin 500mg."]
      iex> {:ok, result} = Verifier.verify_summary(summary, docs)
      iex> result.summary_verdict
      :entailment

  """
  @spec verify_summary(String.t(), [String.t() | map()], keyword()) ::
          {:ok, verification_result()} | {:error, term()}
  def verify_summary(summary_text, source_documents, opts \\ []) do
    demographics = Keyword.get(opts, :demographics, %{})

    # Step 1: Extract claims from summary
    claim_opts = [
      min_length: Keyword.get(opts, :min_claim_length, 5),
      max_length: Keyword.get(opts, :max_claim_length, 500)
    ]

    claims = ClaimExtractor.extract(summary_text, claim_opts)

    if Enum.empty?(claims) do
      {:ok, empty_result()}
    else
      # Step 2: Build source index
      index_opts = Keyword.take(opts, [:method, :confidence_threshold, :snippet_context])

      {:ok, source_index} = SourceIndex.build(source_documents, index_opts)

      # Step 3: Build verification context
      context = %{
        documents: source_documents,
        source_index: source_index,
        demographics: demographics
      }

      # Step 4: Verify each claim
      consensus_opts = Keyword.take(opts, [:timeout, :agents])
      claim_results = verify_claims(claims, context, consensus_opts)

      # Step 5: Compute summary verdict
      {summary_verdict, summary_confidence} = compute_summary_verdict(claim_results)

      needs_review_count = Enum.count(claim_results, & &1.needs_review)

      {:ok,
       %{
         summary_verdict: summary_verdict,
         summary_confidence: summary_confidence,
         claim_results: claim_results,
         claim_count: length(claims),
         needs_review_count: needs_review_count,
         source_index: source_index
       }}
    end
  end

  @doc """
  Verify a summary, raising on error.

  ## Examples

      iex> result = Verifier.verify_summary!("Summary", ["Source"])
      iex> is_map(result)
      true

  """
  @spec verify_summary!(String.t(), [String.t() | map()], keyword()) :: verification_result()
  def verify_summary!(summary_text, source_documents, opts \\ []) do
    {:ok, result} = verify_summary(summary_text, source_documents, opts)
    result
  end

  @doc """
  Verify a single claim against context.

  Lower-level API for verifying individual claims when you already have
  a built context with source_index.

  ## Examples

      iex> context = %{documents: [...], source_index: %{...}, demographics: %{}}
      iex> result = Verifier.verify_claim("HbA1c is 7.2%", context)
      iex> result.verdict
      :neutral

  """
  @spec verify_claim(String.t(), map(), keyword()) :: claim_result()
  def verify_claim(claim_text, context, opts \\ []) do
    claim = %{id: "c1", text: claim_text, source_offset: nil, source_length: nil}
    consensus_result = Consensus.verify(claim_text, context, opts)

    %{
      claim: claim,
      verdict: consensus_result.verdict,
      confidence: consensus_result.confidence,
      needs_review: consensus_result.verdict in [:contradiction, :neutral],
      agent_results: consensus_result.agent_results,
      scores: consensus_result.scores
    }
  end

  # Verify all claims and return results
  defp verify_claims(claims, context, opts) do
    Enum.map(claims, fn claim ->
      consensus_result = Consensus.verify(claim.text, context, opts)

      %{
        claim: claim,
        verdict: consensus_result.verdict,
        confidence: consensus_result.confidence,
        needs_review: consensus_result.verdict in [:contradiction, :neutral],
        agent_results: consensus_result.agent_results,
        scores: consensus_result.scores
      }
    end)
  end

  # Compute summary-level verdict from claim results
  defp compute_summary_verdict(claim_results) do
    # Check for high-confidence contradictions
    has_high_confidence_contradiction =
      Enum.any?(claim_results, fn r ->
        r.verdict == :contradiction and r.confidence >= @contradiction_confidence_threshold
      end)

    # Check for any contradiction or neutral
    has_any_non_entailment =
      Enum.any?(claim_results, fn r ->
        r.verdict in [:contradiction, :neutral]
      end)

    cond do
      # Contradiction if any claim is contradiction with high confidence
      has_high_confidence_contradiction ->
        avg_confidence = average_confidence(claim_results, :contradiction)
        {:contradiction, avg_confidence}

      # Neutral if any claim is neutral or contradiction (but low confidence)
      has_any_non_entailment ->
        avg_confidence = average_confidence_all(claim_results)
        {:neutral, avg_confidence}

      # Entailment only if all claims are entailment
      true ->
        avg_confidence = average_confidence(claim_results, :entailment)
        {:entailment, avg_confidence}
    end
  end

  # Calculate average confidence for claims with a specific verdict
  defp average_confidence(claim_results, verdict) do
    matching = Enum.filter(claim_results, &(&1.verdict == verdict))

    if Enum.empty?(matching) do
      0.5
    else
      sum = Enum.reduce(matching, 0.0, fn r, acc -> acc + r.confidence end)
      Float.round(sum / length(matching), 3)
    end
  end

  # Calculate average confidence across all claims
  defp average_confidence_all(claim_results) do
    if Enum.empty?(claim_results) do
      0.5
    else
      sum = Enum.reduce(claim_results, 0.0, fn r, acc -> acc + r.confidence end)
      Float.round(sum / length(claim_results), 3)
    end
  end

  # Return empty result when no claims
  defp empty_result do
    %{
      summary_verdict: :neutral,
      summary_confidence: 0.5,
      claim_results: [],
      claim_count: 0,
      needs_review_count: 0,
      source_index: SourceIndex.empty_index()
    }
  end
end
