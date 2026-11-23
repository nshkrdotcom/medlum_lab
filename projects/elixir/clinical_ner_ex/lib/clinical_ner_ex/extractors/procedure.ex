defmodule ClinicalNerEx.Extractors.Procedure do
  @moduledoc """
  Procedure entity extractor.

  Extracts medical procedures, surgeries, and interventions from clinical text.

  ## Extraction Methods

  - `:rule_based` - Fast regex pattern matching
  - `:transformer` - ML model inference via Bumblebee (stub for future)
  - `:hybrid` - Combined approach

  ## Extracted Attributes

  - `procedure_name` - Full name of the procedure
  - `status` - Status (`:completed`, `:planned`, `:cancelled`, `:in_progress`)
  - `body_site` - Anatomical location (when specified)
  - `laterality` - Left, right, bilateral (when specified)
  - `date` - When the procedure was/will be performed (when specified)

  ## Pattern Types

  The extractor recognizes several patterns:

  1. **Abbreviations**: CABG, PTCA, ERCP, EKG, CT, MRI, etc.
  2. **Status prefix**: "s/p CABG" (status post), "planned colonoscopy"
  3. **Full procedure names**: "coronary artery bypass graft"
  4. **Common surgeries**: "appendectomy", "cholecystectomy", etc.

  ## Examples

      iex> context = %{text: "s/p CABG x3", method: :rule_based, opts: []}
      iex> {:ok, entities} = ClinicalNerEx.Extractors.Procedure.extract(context)
      iex> length(entities) >= 1
      true

      iex> context = %{text: "EKG and chest CT ordered", method: :rule_based, opts: []}
      iex> {:ok, entities} = ClinicalNerEx.Extractors.Procedure.extract(context)
      iex> length(entities) >= 2
      true
  """

  @behaviour ClinicalNerEx.Extractors.Behaviour

  alias ClinicalNerEx.Entity

  # Common procedure abbreviations with their full names
  @procedure_abbrevs %{
    "cabg" => "coronary artery bypass graft",
    "ptca" => "percutaneous transluminal coronary angioplasty",
    "pci" => "percutaneous coronary intervention",
    "ercp" => "endoscopic retrograde cholangiopancreatography",
    "egd" => "esophagogastroduodenoscopy",
    "ekg" => "electrocardiogram",
    "ecg" => "electrocardiogram",
    "ct" => "computed tomography",
    "mri" => "magnetic resonance imaging",
    "cxr" => "chest x-ray",
    "echo" => "echocardiogram",
    "tte" => "transthoracic echocardiogram",
    "tee" => "transesophageal echocardiogram",
    "cath" => "cardiac catheterization",
    "lap" => "laparoscopy",
    "tavr" => "transcatheter aortic valve replacement",
    "turp" => "transurethral resection of prostate",
    "turbt" => "transurethral resection of bladder tumor",
    "eeg" => "electroencephalogram",
    "emg" => "electromyography",
    "lpn" => "lumbar puncture",
    "lp" => "lumbar puncture"
  }

  # Common surgery names as strings (compiled at runtime)
  @surgery_names [
    "appendectomy",
    "cholecystectomy",
    "colectomy",
    "gastrectomy",
    "mastectomy",
    "hysterectomy",
    "nephrectomy",
    "prostatectomy",
    "thyroidectomy",
    "tonsillectomy",
    "herniorraphy",
    "hernia repair",
    "hip replacement",
    "knee replacement",
    "joint replacement",
    "colonoscopy",
    "endoscopy",
    "bronchoscopy",
    "biopsy",
    "angioplasty",
    "stent",
    "stenting",
    "ablation",
    "dialysis",
    "chemotherapy",
    "radiation",
    "radiation therapy",
    "intubation",
    "tracheostomy",
    "pacemaker",
    "pacemaker placement",
    "icd placement",
    "defibrillator",
    "defibrillator placement"
  ]

  @impl true
  @doc """
  Returns the entity type handled by this extractor.
  """
  @spec entity_type() :: :procedure
  def entity_type, do: :procedure

  @impl true
  @doc """
  Returns the extraction methods supported by this extractor.
  """
  @spec supported_methods() :: [:rule_based | :transformer | :hybrid]
  def supported_methods, do: [:rule_based, :transformer, :hybrid]

  @impl true
  @doc """
  Extract procedure entities from the context.

  The context must contain:
  - `text` - The clinical text to extract from
  - `method` - The extraction method
  - `opts` - Additional options (optional)

  ## Returns

  - `{:ok, [Entity.t()]}` - List of extracted procedure entities
  - `{:error, reason}` - Error tuple on failure
  """
  @spec extract(map()) :: {:ok, [Entity.t()]} | {:error, term()}
  def extract(context) do
    method = context[:method] || :rule_based

    case method do
      :rule_based -> extract_rule_based(context)
      :transformer -> extract_transformer(context)
      :hybrid -> extract_hybrid(context)
    end
  end

  @doc """
  Extract procedures using rule-based patterns.
  """
  @spec extract_rule_based(map()) :: {:ok, [Entity.t()]} | {:error, term()}
  def extract_rule_based(%{text: text}) do
    entities =
      []
      |> Kernel.++(extract_abbreviations(text))
      |> Kernel.++(extract_surgeries(text))
      |> remove_duplicates()

    {:ok, entities}
  rescue
    e -> {:error, {:extraction_failed, Exception.message(e)}}
  end

  @doc """
  Extract procedures using transformer model.

  Note: This is a stub. Full implementation requires Bumblebee integration.
  """
  @spec extract_transformer(map()) :: {:ok, [Entity.t()]} | {:error, term()}
  def extract_transformer(%{text: _text}) do
    # TODO: Implement with Bumblebee Bio_ClinicalBERT
    {:ok, []}
  end

  @doc """
  Extract procedures using hybrid approach.
  """
  @spec extract_hybrid(map()) :: {:ok, [Entity.t()]} | {:error, term()}
  def extract_hybrid(context) do
    # For now, just use rule_based since transformer is a stub
    extract_rule_based(context)
  end

  # Private extraction functions

  defp extract_abbreviations(text) do
    @procedure_abbrevs
    |> Map.keys()
    |> Enum.flat_map(fn abbrev ->
      # Build pattern that matches the abbreviation as a word
      pattern = ~r/\b#{Regex.escape(abbrev)}\b/i

      Regex.scan(pattern, text, return: :index)
      |> Enum.map(fn [{start, length}] ->
        match_text = String.slice(text, start, length)

        # Check for status prefix
        {status, adjusted_start} = detect_status(text, start)

        # Get full procedure name
        full_name = Map.get(@procedure_abbrevs, String.downcase(match_text))

        # Adjust text span if status prefix was found
        final_text =
          if adjusted_start < start do
            String.slice(text, adjusted_start, start + length - adjusted_start)
          else
            match_text
          end

        Entity.new(%{
          type: :procedure,
          text: final_text,
          start_offset: adjusted_start,
          end_offset: start + length,
          confidence: calculate_confidence(:abbreviation, status),
          attributes: %{
            procedure_name: full_name,
            abbreviation: String.upcase(match_text),
            status: status
          },
          extraction_method: :rule_based,
          metadata: %{pattern_type: :abbreviation}
        })
      end)
    end)
  end

  defp extract_surgeries(text) do
    text_lower = String.downcase(text)

    @surgery_names
    |> Enum.flat_map(fn surgery_name ->
      # Find all occurrences of this surgery name
      find_all_occurrences(text, text_lower, surgery_name)
    end)
  end

  defp find_all_occurrences(text, _text_lower, surgery_name) do
    pattern = ~r/\b#{Regex.escape(surgery_name)}\b/i

    Regex.scan(pattern, text, return: :index)
    |> Enum.map(fn [{start, length}] ->
      match_text = String.slice(text, start, length)

      # Check for status prefix
      {status, adjusted_start} = detect_status(text, start)

      # Adjust text span if status prefix was found
      final_text =
        if adjusted_start < start do
          String.slice(text, adjusted_start, start + length - adjusted_start)
        else
          match_text
        end

      # Detect laterality from context
      laterality = detect_laterality(text, start)

      Entity.new(%{
        type: :procedure,
        text: final_text,
        start_offset: adjusted_start,
        end_offset: start + length,
        confidence: calculate_confidence(:surgery, status),
        attributes:
          Map.merge(
            %{
              procedure_name: normalize_procedure_name(match_text),
              status: status
            },
            if(laterality, do: %{laterality: laterality}, else: %{})
          ),
        extraction_method: :rule_based,
        metadata: %{pattern_type: :surgery}
      })
    end)
  end

  defp detect_status(text, start) do
    # Check for status post pattern before the match
    prefix_start = max(0, start - 15)
    prefix = String.slice(text, prefix_start, start - prefix_start)

    status_post_pattern = ~r/\bs(?:tatus)?[\/\s]p(?:ost)?\s+/i
    planned_pattern = ~r/\b(?:planned|scheduled|upcoming)\s+/i
    pending_pattern = ~r/\b(?:pending|ordered)\s+/i

    cond do
      Regex.match?(status_post_pattern, prefix) ->
        match = Regex.run(status_post_pattern, prefix, return: :index)

        case match do
          [{idx, _}] -> {:completed, prefix_start + idx}
          _ -> {:completed, start}
        end

      Regex.match?(planned_pattern, prefix) ->
        {:planned, start}

      Regex.match?(pending_pattern, prefix) ->
        {:pending, start}

      true ->
        {:unknown, start}
    end
  end

  defp detect_laterality(text, start) do
    # Check for laterality in surrounding context
    context_start = max(0, start - 20)
    context = String.slice(text, context_start, 40) |> String.downcase()

    cond do
      String.contains?(context, "bilateral") -> :bilateral
      String.contains?(context, "left") -> :left
      String.contains?(context, "right") -> :right
      String.contains?(context, " l ") -> :left
      String.contains?(context, " r ") -> :right
      true -> nil
    end
  end

  defp calculate_confidence(type, status) do
    base =
      case type do
        :abbreviation -> 0.90
        :surgery -> 0.88
        _ -> 0.80
      end

    # Boost for known status
    status_boost =
      case status do
        :completed -> 0.05
        :planned -> 0.03
        _ -> 0.0
      end

    min(base + status_boost, 1.0)
  end

  defp normalize_procedure_name(name) do
    name
    |> String.downcase()
    |> String.trim()
  end

  defp remove_duplicates(entities) do
    # Remove entities with same span
    entities
    |> Enum.uniq_by(fn e -> {e.start_offset, e.end_offset} end)
    |> Enum.sort_by(& &1.start_offset)
  end
end
