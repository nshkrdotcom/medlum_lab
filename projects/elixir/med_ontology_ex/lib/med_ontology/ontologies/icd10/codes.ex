defmodule MedOntology.ICD10.Codes do
  @moduledoc """
  Local ICD-10-CM code database.

  This module provides access to ICD-10-CM codes loaded from CMS files.
  In production, this would be populated from the annual CMS release
  (typically ~72,000 codes).

  For initial development and testing, we include a subset of common codes
  covering major diagnostic categories.

  ## Data Source

  In production, codes would be loaded from CMS ICD-10-CM files:
  - `icd10cm_tabular_YYYY.xml` (structured code data)
  - `icd10cm_order_YYYY.txt` (with billable flags)

  ## Examples

      # Get a code by identifier
      MedOntology.ICD10.Codes.get("E11.9")
      #=> {:ok, %{description: "Type 2 diabetes mellitus without complications", billable: true}}

      # Search codes by description
      MedOntology.ICD10.Codes.search("diabetes")
      #=> [{"E11.9", %{description: "Type 2 diabetes mellitus without complications", ...}}, ...]

  """

  # Sample codes for development/testing
  # Organized by chapter for easier maintenance
  # In production, this would be loaded from CMS XML files
  @codes %{
    # Chapter IV - Endocrine, nutritional and metabolic diseases (E00-E89)
    "E11" => %{
      description: "Type 2 diabetes mellitus",
      billable: false,
      includes: ["diabetes mellitus due to insulin secretory defect"],
      excludes1: ["diabetes mellitus due to underlying condition (E08.-)", "drug or chemical induced diabetes mellitus (E09.-)"],
      excludes2: []
    },
    "E11.9" => %{
      description: "Type 2 diabetes mellitus without complications",
      billable: true,
      includes: [],
      excludes1: [],
      excludes2: []
    },
    "E11.65" => %{
      description: "Type 2 diabetes mellitus with hyperglycemia",
      billable: true,
      includes: [],
      excludes1: [],
      excludes2: []
    },
    "E11.21" => %{
      description: "Type 2 diabetes mellitus with diabetic nephropathy",
      billable: true,
      includes: [],
      excludes1: [],
      excludes2: []
    },
    "E11.22" => %{
      description: "Type 2 diabetes mellitus with diabetic chronic kidney disease",
      billable: true,
      includes: [],
      excludes1: [],
      excludes2: []
    },
    "E11.40" => %{
      description: "Type 2 diabetes mellitus with diabetic neuropathy, unspecified",
      billable: true,
      includes: [],
      excludes1: [],
      excludes2: []
    },
    "E10" => %{
      description: "Type 1 diabetes mellitus",
      billable: false,
      includes: ["brittle diabetes (mellitus)", "juvenile onset diabetes"],
      excludes1: [],
      excludes2: []
    },
    "E10.9" => %{
      description: "Type 1 diabetes mellitus without complications",
      billable: true,
      includes: [],
      excludes1: [],
      excludes2: []
    },
    "E78.0" => %{
      description: "Pure hypercholesterolemia",
      billable: true,
      includes: ["Familial hypercholesterolemia", "Fredrickson's hyperlipoproteinemia, type IIa"],
      excludes1: [],
      excludes2: []
    },
    "E78.5" => %{
      description: "Hyperlipidemia, unspecified",
      billable: true,
      includes: [],
      excludes1: [],
      excludes2: []
    },

    # Chapter IX - Diseases of the circulatory system (I00-I99)
    "I10" => %{
      description: "Essential (primary) hypertension",
      billable: true,
      includes: ["high blood pressure", "hypertension (arterial) (benign) (essential) (malignant) (primary) (systemic)"],
      excludes1: ["hypertensive disease complicating pregnancy (O10-O11, O13-O16)"],
      excludes2: ["essential (primary) hypertension involving vessels of brain (I60-I69)", "essential (primary) hypertension involving vessels of eye (H35.0-)"]
    },
    "I11" => %{
      description: "Hypertensive heart disease",
      billable: false,
      includes: [],
      excludes1: [],
      excludes2: []
    },
    "I11.0" => %{
      description: "Hypertensive heart disease with heart failure",
      billable: true,
      includes: [],
      excludes1: [],
      excludes2: []
    },
    "I11.9" => %{
      description: "Hypertensive heart disease without heart failure",
      billable: true,
      includes: [],
      excludes1: [],
      excludes2: []
    },
    "I25.10" => %{
      description: "Atherosclerotic heart disease of native coronary artery without angina pectoris",
      billable: true,
      includes: [],
      excludes1: [],
      excludes2: []
    },
    "I50.9" => %{
      description: "Heart failure, unspecified",
      billable: true,
      includes: [],
      excludes1: [],
      excludes2: []
    },

    # Chapter X - Diseases of the respiratory system (J00-J99)
    "J06.9" => %{
      description: "Acute upper respiratory infection, unspecified",
      billable: true,
      includes: ["Upper respiratory disease, acute", "Upper respiratory infection NOS"],
      excludes1: [],
      excludes2: []
    },
    "J18.9" => %{
      description: "Pneumonia, unspecified organism",
      billable: true,
      includes: [],
      excludes1: [],
      excludes2: []
    },
    "J44.9" => %{
      description: "Chronic obstructive pulmonary disease, unspecified",
      billable: true,
      includes: [],
      excludes1: [],
      excludes2: []
    },
    "J45.20" => %{
      description: "Mild intermittent asthma, uncomplicated",
      billable: true,
      includes: [],
      excludes1: [],
      excludes2: []
    },

    # Chapter XIII - Diseases of the musculoskeletal system (M00-M99)
    "M54.5" => %{
      description: "Low back pain",
      billable: true,
      includes: ["Loin pain", "Lumbago NOS"],
      excludes1: ["low back pain due to intervertebral disc displacement (M51.1-)"],
      excludes2: []
    },
    "M54.50" => %{
      description: "Low back pain, unspecified",
      billable: true,
      includes: [],
      excludes1: [],
      excludes2: []
    },
    "M79.3" => %{
      description: "Panniculitis, unspecified",
      billable: true,
      includes: [],
      excludes1: [],
      excludes2: []
    },

    # Chapter V - Mental, Behavioral and Neurodevelopmental disorders (F01-F99)
    "F32.9" => %{
      description: "Major depressive disorder, single episode, unspecified",
      billable: true,
      includes: [],
      excludes1: [],
      excludes2: []
    },
    "F32.0" => %{
      description: "Major depressive disorder, single episode, mild",
      billable: true,
      includes: [],
      excludes1: [],
      excludes2: []
    },
    "F32.1" => %{
      description: "Major depressive disorder, single episode, moderate",
      billable: true,
      includes: [],
      excludes1: [],
      excludes2: []
    },
    "F33.0" => %{
      description: "Major depressive disorder, recurrent, mild",
      billable: true,
      includes: [],
      excludes1: [],
      excludes2: []
    },
    "F41.1" => %{
      description: "Generalized anxiety disorder",
      billable: true,
      includes: [],
      excludes1: [],
      excludes2: []
    },
    "F41.9" => %{
      description: "Anxiety disorder, unspecified",
      billable: true,
      includes: [],
      excludes1: [],
      excludes2: []
    },

    # Chapter XI - Diseases of the digestive system (K00-K95)
    "K21.0" => %{
      description: "Gastro-esophageal reflux disease with esophagitis",
      billable: true,
      includes: [],
      excludes1: [],
      excludes2: []
    },
    "K21.9" => %{
      description: "Gastro-esophageal reflux disease without esophagitis",
      billable: true,
      includes: [],
      excludes1: [],
      excludes2: []
    },

    # Chapter I - Certain infectious and parasitic diseases (A00-B99)
    "A00" => %{
      description: "Cholera",
      billable: false,
      includes: [],
      excludes1: [],
      excludes2: []
    },
    "A00.0" => %{
      description: "Cholera due to Vibrio cholerae 01, biovar cholerae",
      billable: true,
      includes: ["Classical cholera"],
      excludes1: [],
      excludes2: []
    },

    # Chapter XXI - Factors influencing health status (Z00-Z99)
    "Z87.891" => %{
      description: "Personal history of nicotine dependence",
      billable: true,
      includes: [],
      excludes1: ["nicotine dependence (F17.-)"],
      excludes2: []
    },
    "Z86.32" => %{
      description: "Personal history of gestational diabetes",
      billable: true,
      includes: [],
      excludes1: [],
      excludes2: []
    },
    "Z00.00" => %{
      description: "Encounter for general adult medical examination without abnormal findings",
      billable: true,
      includes: [],
      excludes1: [],
      excludes2: []
    },
    "Z99" => %{
      description: "Dependence on enabling machines and devices, not elsewhere classified",
      billable: false,
      includes: [],
      excludes1: [],
      excludes2: []
    },
    "Z99.89" => %{
      description: "Dependence on other enabling machines and devices",
      billable: true,
      includes: [],
      excludes1: [],
      excludes2: []
    }
  }

  @doc """
  Get a code by its identifier.

  Returns the code data including description and billability flag.

  ## Examples

      iex> MedOntology.ICD10.Codes.get("E11.9")
      {:ok, %{description: "Type 2 diabetes mellitus without complications", billable: true, ...}}

      iex> MedOntology.ICD10.Codes.get("INVALID")
      :not_found

  """
  @spec get(String.t()) :: {:ok, map()} | :not_found
  def get(code) when is_binary(code) do
    case Map.get(@codes, String.upcase(code)) do
      nil -> :not_found
      data -> {:ok, data}
    end
  end

  @doc """
  Search codes by description.

  Performs a case-insensitive substring match on the description.

  ## Options

    * `:limit` - Maximum number of results (default: 25)

  ## Examples

      iex> MedOntology.ICD10.Codes.search("diabetes")
      [{"E11.9", %{description: "Type 2 diabetes mellitus without complications", ...}}, ...]

  """
  @spec search(String.t(), keyword()) :: [{String.t(), map()}]
  def search(query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, 25)
    query_lower = String.downcase(query)

    @codes
    |> Enum.filter(fn {_code, data} ->
      String.downcase(data.description) |> String.contains?(query_lower)
    end)
    |> Enum.sort_by(fn {code, data} ->
      # Sort by relevance: exact matches first, then by code length, then alphabetically
      description_lower = String.downcase(data.description)
      cond do
        description_lower == query_lower -> {0, String.length(code), code}
        String.starts_with?(description_lower, query_lower) -> {1, String.length(code), code}
        true -> {2, String.length(code), code}
      end
    end)
    |> Enum.take(limit)
  end

  @doc """
  Get child codes of a category.

  Returns codes that start with the given category prefix.

  ## Options

    * `:limit` - Maximum number of results (default: 100)

  ## Examples

      iex> MedOntology.ICD10.Codes.children("E11")
      [{"E11.9", %{...}}, {"E11.65", %{...}}, ...]

  """
  @spec children(String.t(), keyword()) :: [{String.t(), map()}]
  def children(category_code, opts \\ []) when is_binary(category_code) do
    limit = Keyword.get(opts, :limit, 100)
    prefix = String.upcase(category_code)

    @codes
    |> Enum.filter(fn {code, _data} ->
      String.starts_with?(code, prefix) and code != prefix
    end)
    |> Enum.sort_by(fn {code, _data} -> code end)
    |> Enum.take(limit)
  end

  @doc """
  Get codes in a range.

  Returns codes whose category falls within the specified range.

  ## Options

    * `:limit` - Maximum number of results (default: 100)

  ## Examples

      iex> MedOntology.ICD10.Codes.in_range("E10", "E14")
      [{"E10", %{...}}, {"E10.9", %{...}}, {"E11", %{...}}, ...]

  """
  @spec in_range(String.t(), String.t(), keyword()) :: [{String.t(), map()}]
  def in_range(start_code, end_code, opts \\ []) when is_binary(start_code) and is_binary(end_code) do
    limit = Keyword.get(opts, :limit, 100)
    start_upper = String.upcase(start_code)
    end_upper = String.upcase(end_code)

    @codes
    |> Enum.filter(fn {code, _data} ->
      # Compare the category part (first 3 characters)
      category = String.slice(code, 0, 3)
      category >= start_upper and category <= end_upper
    end)
    |> Enum.sort_by(fn {code, _data} -> code end)
    |> Enum.take(limit)
  end

  @doc """
  Check if a code exists in the database.

  ## Examples

      iex> MedOntology.ICD10.Codes.exists?("E11.9")
      true

      iex> MedOntology.ICD10.Codes.exists?("ZZZ.99")
      false

  """
  @spec exists?(String.t()) :: boolean()
  def exists?(code) when is_binary(code) do
    Map.has_key?(@codes, String.upcase(code))
  end

  @doc """
  Get all codes.

  Returns all codes in the database. Use with caution in production
  as the full ICD-10-CM set has ~72,000 codes.

  ## Options

    * `:limit` - Maximum number of results (default: 1000)

  ## Examples

      iex> codes = MedOntology.ICD10.Codes.all(limit: 10)
      iex> length(codes)
      10

  """
  @spec all(keyword()) :: [{String.t(), map()}]
  def all(opts \\ []) do
    limit = Keyword.get(opts, :limit, 1000)

    @codes
    |> Enum.sort_by(fn {code, _data} -> code end)
    |> Enum.take(limit)
  end

  @doc """
  Get the count of codes in the database.

  ## Examples

      iex> MedOntology.ICD10.Codes.count()
      34

  """
  @spec count() :: non_neg_integer()
  def count do
    map_size(@codes)
  end

  @doc """
  Check if a code is billable.

  ## Examples

      iex> MedOntology.ICD10.Codes.billable?("E11.9")
      true

      iex> MedOntology.ICD10.Codes.billable?("E11")
      false

  """
  @spec billable?(String.t()) :: boolean()
  def billable?(code) when is_binary(code) do
    case get(code) do
      {:ok, %{billable: billable}} -> billable
      :not_found -> false
    end
  end
end
