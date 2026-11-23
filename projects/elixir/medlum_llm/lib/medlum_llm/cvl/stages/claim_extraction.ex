defmodule MedlumLlm.CVL.Stages.ClaimExtraction do
  @moduledoc """
  Forge Stage for extracting verifiable claims from text.

  This stage splits text into individual claims that can be verified for
  factual accuracy. Claims are extracted via sentence/bullet splitting and
  can be optionally enriched with named entity information.

  ## Claim Types

  - `:medication` - Drug names, doses, frequencies
  - `:diagnosis` - Medical conditions, diseases
  - `:lab_value` - Lab results, vital signs
  - `:procedure` - Medical procedures, treatments
  - `:temporal` - Dates, durations, sequences

  ## Configuration Options

  - `:claim_types` - Types of claims to extract (default: all types)
  - `:include_entities` - Whether to include NER extraction (default: `false`)
  - `:min_claim_length` - Minimum characters for a valid claim (default: `10`)

  ## Example

      iex> sample = %Forge.Sample{data: %{
      ...>   source_document: "Patient takes metformin 500mg twice daily. BP is 120/80."
      ...> }}
      iex> {:ok, extracted} = ClaimExtraction.process(sample)
      iex> length(extracted.data.claims)
      2
  """

  @behaviour Forge.Stage

  @default_claim_types [:medication, :diagnosis, :lab_value, :procedure, :temporal]
  @min_claim_length 10

  @impl true
  @spec process(Forge.Sample.t()) :: {:ok, Forge.Sample.t()} | {:skip, term()} | {:error, term()}
  def process(sample) do
    data = sample.data

    # Extract claims from both source and generated text
    source_claims = extract_claims(data[:source_document])
    generated_claims = extract_claims(data[:generated_summary])

    # Categorize claims by type
    all_claims = source_claims ++ generated_claims

    categorized_claims =
      all_claims
      |> Enum.map(&categorize_claim/1)
      |> Enum.reject(&is_nil/1)

    updated_data =
      data
      |> Map.put(:claims, categorized_claims)
      |> Map.put(:source_claims, source_claims)
      |> Map.put(:generated_claims, generated_claims)

    {:ok, %{sample | data: updated_data}}
  rescue
    e ->
      {:error, %{reason: :claim_extraction_failed, exception: Exception.message(e)}}
  end

  @impl true
  @spec async?() :: boolean()
  def async?, do: false

  @impl true
  @spec concurrency() :: pos_integer()
  def concurrency, do: 1

  @impl true
  @spec timeout() :: pos_integer()
  def timeout, do: 30_000

  # Public helper functions for testing

  @doc """
  Extract claims from text by splitting on sentences and bullet points.

  This is the primary claim extraction mechanism - splitting text into
  individual verifiable statements. Each claim is a single sentence or
  bullet point that can be independently verified.
  """
  @spec extract_claims(String.t() | nil) :: [map()]
  def extract_claims(nil), do: []
  def extract_claims(""), do: []

  def extract_claims(text) when is_binary(text) do
    text
    |> split_into_sentences()
    |> Enum.with_index()
    |> Enum.map(fn {sentence, idx} ->
      %{
        text: sentence,
        span: find_span(text, sentence),
        index: idx,
        source: :text_split
      }
    end)
    |> Enum.filter(&valid_claim?/1)
  end

  def extract_claims(_), do: []

  # Private functions

  @spec split_into_sentences(String.t()) :: [String.t()]
  defp split_into_sentences(text) do
    # First, split on bullet points and numbered lists
    bullet_splits =
      text
      |> String.split(~r/[\n\r]+(?:[-•*]\s*|\d+[.)]\s*)/u, trim: true)
      |> Enum.flat_map(&split_on_sentence_boundaries/1)

    bullet_splits
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  @spec split_on_sentence_boundaries(String.t()) :: [String.t()]
  defp split_on_sentence_boundaries(text) do
    # Split on sentence-ending punctuation, but be careful with:
    # - Abbreviations (Dr., Mr., etc.)
    # - Decimal numbers (1.5, 0.75)
    # - Medical units (mg., mL., etc.)

    # Common medical/clinical abbreviations that shouldn't split
    abbreviations = ~w(Dr Mr Mrs Ms Prof St vs etc al ie eg)

    # Create a pattern that matches sentence endings
    # but not abbreviations or decimals
    text
    |> protect_abbreviations(abbreviations)
    |> String.split(~r/(?<=[.!?])\s+(?=[A-Z])/u, trim: true)
    |> Enum.flat_map(&maybe_split_on_semicolon/1)
    |> Enum.map(&restore_abbreviations(&1, abbreviations))
  end

  @spec protect_abbreviations(String.t(), [String.t()]) :: String.t()
  defp protect_abbreviations(text, abbreviations) do
    Enum.reduce(abbreviations, text, fn abbr, acc ->
      pattern = ~r/\b(#{Regex.escape(abbr)})\./i
      Regex.replace(pattern, acc, "\\1<<DOT>>")
    end)
  end

  @spec restore_abbreviations(String.t(), [String.t()]) :: String.t()
  defp restore_abbreviations(text, _abbreviations) do
    String.replace(text, "<<DOT>>", ".")
  end

  @spec maybe_split_on_semicolon(String.t()) :: [String.t()]
  defp maybe_split_on_semicolon(text) do
    # Split on semicolons if they separate distinct statements
    parts = String.split(text, ~r/;\s+/, trim: true)

    if length(parts) > 1 do
      parts
    else
      [text]
    end
  end

  @spec find_span(String.t(), String.t()) :: {non_neg_integer(), non_neg_integer()} | nil
  defp find_span(text, claim) do
    case :binary.match(text, claim) do
      {start, length} -> {start, start + length}
      :nomatch -> nil
    end
  end

  @spec valid_claim?(map()) :: boolean()
  defp valid_claim?(%{text: text}) when is_binary(text) do
    trimmed = String.trim(text)

    # Must meet minimum length
    String.length(trimmed) >= @min_claim_length and
      # Must contain at least some alphanumeric content
      Regex.match?(~r/[a-zA-Z0-9]/u, trimmed)
  end

  defp valid_claim?(_), do: false

  @spec categorize_claim(map()) :: map() | nil
  defp categorize_claim(%{text: text} = claim) do
    type = detect_claim_type(text)

    if type in @default_claim_types do
      Map.put(claim, :type, type)
    else
      Map.put(claim, :type, :general)
    end
  end

  defp categorize_claim(_), do: nil

  @spec detect_claim_type(String.t()) :: atom()
  defp detect_claim_type(text) do
    lower_text = String.downcase(text)

    cond do
      medication_claim?(lower_text) -> :medication
      lab_claim?(lower_text) -> :lab_value
      diagnosis_claim?(lower_text) -> :diagnosis
      procedure_claim?(lower_text) -> :procedure
      temporal_claim?(lower_text) -> :temporal
      true -> :general
    end
  end

  @spec medication_claim?(String.t()) :: boolean()
  defp medication_claim?(text) do
    # Check for medication patterns
    medication_patterns = [
      # Drug dosages
      ~r/\d+\s*(mg|mcg|g|ml|units?|iu)/i,
      # Frequency patterns
      ~r/(daily|twice|three times|bid|tid|qid|prn|q\d+h)/i,
      # Route patterns
      ~r/(oral|iv|im|subq|topical|inhaled)/i,
      # Common drug suffixes
      ~r/(pril|sartan|statin|mab|nib|zole|cillin|mycin)/i
    ]

    Enum.any?(medication_patterns, &Regex.match?(&1, text))
  end

  @spec lab_claim?(String.t()) :: boolean()
  defp lab_claim?(text) do
    lab_patterns = [
      # Lab value ranges
      ~r/(level|value|result)\s*(is|was|of)\s*[\d.]+/i,
      # Common lab terms
      ~r/(hemoglobin|hgb|wbc|rbc|platelet|creatinine|glucose|a1c|ldl|hdl|tsh|t[34])/i,
      # Reference ranges
      ~r/\d+\s*-\s*\d+\s*(mg\/dl|mmol\/l|%|g\/dl)/i,
      # Vital signs
      ~r/(blood pressure|bp|heart rate|hr|temperature|temp|o2 sat|spo2)/i,
      ~r/\d+\/\d+\s*(mmhg)?/i
    ]

    Enum.any?(lab_patterns, &Regex.match?(&1, text))
  end

  @spec diagnosis_claim?(String.t()) :: boolean()
  defp diagnosis_claim?(text) do
    diagnosis_patterns = [
      # Diagnosis language
      ~r/(diagnos|present(s|ed|ing) with|history of|suffer(s|ed|ing) from)/i,
      # Disease suffixes
      ~r/(itis|osis|emia|pathy|plasia|trophy|oma)\b/i,
      # Common diagnosis terms
      ~r/(disease|syndrome|disorder|condition|infection|cancer|tumor)/i,
      # Symptom language
      ~r/(symptom|complain|report(s|ed|ing)|experienc(e|es|ed|ing))/i
    ]

    Enum.any?(diagnosis_patterns, &Regex.match?(&1, text))
  end

  @spec procedure_claim?(String.t()) :: boolean()
  defp procedure_claim?(text) do
    procedure_patterns = [
      # Procedure terms
      ~r/(surgery|procedure|operation|biopsy|scan|imaging|x-ray|ct|mri|ultrasound)/i,
      # Treatment terms
      ~r/(treatment|therapy|intervention|removal|repair|replacement)/i,
      # Procedure language
      ~r/(underwent|performed|scheduled|recommended|indicated)/i,
      # Surgical suffixes
      ~r/(ectomy|otomy|ostomy|plasty|scopy)\b/i
    ]

    Enum.any?(procedure_patterns, &Regex.match?(&1, text))
  end

  @spec temporal_claim?(String.t()) :: boolean()
  defp temporal_claim?(text) do
    temporal_patterns = [
      # Date patterns
      ~r/\b\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}\b/,
      # Relative time
      ~r/(ago|since|prior to|after|before|following|during)/i,
      # Duration
      ~r/\d+\s*(day|week|month|year|hour|minute)s?/i,
      # Temporal keywords
      ~r/(onset|duration|frequency|interval|episode|chronic|acute)/i
    ]

    Enum.any?(temporal_patterns, &Regex.match?(&1, text))
  end
end
