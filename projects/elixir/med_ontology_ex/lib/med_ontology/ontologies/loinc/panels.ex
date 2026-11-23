defmodule MedOntology.LOINC.Panels do
  @moduledoc """
  Common LOINC panel definitions.

  Laboratory panels are collections of related tests that are commonly
  ordered together. This module provides definitions for common panels
  including their component codes.

  ## Supported Panels

    * **24323-8** - Basic Metabolic Panel (BMP)
    * **24325-3** - Comprehensive Metabolic Panel (CMP)
    * **58410-2** - Complete Blood Count (CBC)
    * **57021-8** - Lipid Panel
    * **24347-7** - Urinalysis Complete
    * **24326-1** - Hepatic Function Panel

  ## Examples

      # Get panel definition
      iex> MedOntology.LOINC.Panels.get("24323-8")
      {:ok, %{name: "Basic Metabolic Panel (BMP)", components: ["2345-7", ...]}}

      # Find panels containing a component
      iex> MedOntology.LOINC.Panels.panels_with_component("2345-7")
      [{"24323-8", "Basic Metabolic Panel (BMP)"}, {"24325-3", "Comprehensive Metabolic Panel (CMP)"}]

  """

  @panels %{
    "24323-8" => %{
      name: "Basic Metabolic Panel (BMP)",
      components: [
        "2345-7",
        "3094-0",
        "2160-0",
        "2951-2",
        "2823-3",
        "2075-0",
        "2028-9",
        "17861-6"
      ],
      description: "Basic panel for metabolic assessment including glucose, renal function, and electrolytes"
    },
    "24325-3" => %{
      name: "Comprehensive Metabolic Panel (CMP)",
      components: [
        "2345-7",
        "3094-0",
        "2160-0",
        "2951-2",
        "2823-3",
        "2075-0",
        "2028-9",
        "17861-6",
        "1751-7",
        "1975-2",
        "6768-6",
        "1742-6",
        "1920-8",
        "2885-2"
      ],
      description: "Extended metabolic panel including liver function tests"
    },
    "58410-2" => %{
      name: "Complete Blood Count (CBC)",
      components: [
        "6690-2",
        "789-8",
        "718-7",
        "4544-3",
        "787-2",
        "785-6",
        "786-4",
        "777-3"
      ],
      description: "Complete blood count with white blood cell differential"
    },
    "57021-8" => %{
      name: "Lipid Panel",
      components: [
        "2093-3",
        "2085-9",
        "13457-7",
        "2571-8"
      ],
      description: "Lipid panel for cardiovascular risk assessment"
    },
    "24347-7" => %{
      name: "Urinalysis Complete",
      components: [
        "5811-5",
        "5803-2",
        "20505-4",
        "5778-6",
        "2349-9",
        "5799-2"
      ],
      description: "Complete urinalysis including physical, chemical, and microscopic examination"
    },
    "24326-1" => %{
      name: "Hepatic Function Panel",
      components: [
        "1751-7",
        "1975-2",
        "6768-6",
        "1742-6",
        "1920-8",
        "2324-2"
      ],
      description: "Liver function panel for hepatic assessment"
    },
    "24362-6" => %{
      name: "Renal Function Panel",
      components: [
        "2160-0",
        "3094-0",
        "33914-3",
        "2951-2",
        "2823-3"
      ],
      description: "Kidney function assessment panel"
    },
    "55231-5" => %{
      name: "Thyroid Panel",
      components: [
        "3016-3",
        "3051-0",
        "3053-6"
      ],
      description: "Thyroid function panel"
    }
  }

  @doc """
  Get panel definition by code.

  Returns the panel name and list of component LOINC codes.

  ## Examples

      iex> MedOntology.LOINC.Panels.get("24323-8")
      {:ok, %{name: "Basic Metabolic Panel (BMP)", components: ["2345-7", ...], description: "..."}}

      iex> MedOntology.LOINC.Panels.get("unknown")
      {:error, :not_found}

  """
  @spec get(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get(panel_code) do
    case Map.get(@panels, panel_code) do
      nil -> {:error, :not_found}
      panel -> {:ok, panel}
    end
  end

  @doc """
  Get all panel definitions.

  Returns a map of panel code to panel definition.

  ## Examples

      iex> panels = MedOntology.LOINC.Panels.all()
      iex> Map.has_key?(panels, "24323-8")
      true

  """
  @spec all() :: map()
  def all, do: @panels

  @doc """
  Get available panel codes.

  Returns a list of all panel LOINC codes.

  ## Examples

      iex> codes = MedOntology.LOINC.Panels.available_panels()
      iex> "24323-8" in codes
      true

  """
  @spec available_panels() :: [String.t()]
  def available_panels, do: Map.keys(@panels)

  @doc """
  Check if a code is a panel.

  ## Examples

      iex> MedOntology.LOINC.Panels.panel?("24323-8")
      true

      iex> MedOntology.LOINC.Panels.panel?("2345-7")
      false

  """
  @spec panel?(String.t()) :: boolean()
  def panel?(code) do
    Map.has_key?(@panels, code)
  end

  @doc """
  Find panels containing a specific component.

  Returns a list of tuples with {panel_code, panel_name}.

  ## Examples

      iex> MedOntology.LOINC.Panels.panels_with_component("2345-7")
      [{"24323-8", "Basic Metabolic Panel (BMP)"}, {"24325-3", "Comprehensive Metabolic Panel (CMP)"}]

      iex> MedOntology.LOINC.Panels.panels_with_component("nonexistent")
      []

  """
  @spec panels_with_component(String.t()) :: [{String.t(), String.t()}]
  def panels_with_component(component_code) do
    @panels
    |> Enum.filter(fn {_code, panel} ->
      component_code in panel.components
    end)
    |> Enum.map(fn {code, panel} ->
      {code, panel.name}
    end)
  end

  @doc """
  Get component codes for a panel.

  Returns just the list of component LOINC codes.

  ## Examples

      iex> MedOntology.LOINC.Panels.components("57021-8")
      {:ok, ["2093-3", "2085-9", "13457-7", "2571-8"]}

      iex> MedOntology.LOINC.Panels.components("unknown")
      {:error, :not_found}

  """
  @spec components(String.t()) :: {:ok, [String.t()]} | {:error, :not_found}
  def components(panel_code) do
    case get(panel_code) do
      {:ok, panel} -> {:ok, panel.components}
      error -> error
    end
  end

  @doc """
  Get panel name.

  ## Examples

      iex> MedOntology.LOINC.Panels.name("24323-8")
      {:ok, "Basic Metabolic Panel (BMP)"}

      iex> MedOntology.LOINC.Panels.name("unknown")
      {:error, :not_found}

  """
  @spec name(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def name(panel_code) do
    case get(panel_code) do
      {:ok, panel} -> {:ok, panel.name}
      error -> error
    end
  end

  @doc """
  Get panel description.

  ## Examples

      iex> MedOntology.LOINC.Panels.description("24323-8")
      {:ok, "Basic panel for metabolic assessment including glucose, renal function, and electrolytes"}

  """
  @spec description(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def description(panel_code) do
    case get(panel_code) do
      {:ok, panel} -> {:ok, panel.description}
      error -> error
    end
  end

  @doc """
  Get panels by category.

  ## Examples

      iex> MedOntology.LOINC.Panels.by_category(:metabolic)
      ["24323-8", "24325-3"]

      iex> MedOntology.LOINC.Panels.by_category(:hematology)
      ["58410-2"]

  """
  @spec by_category(atom()) :: [String.t()]
  def by_category(category) do
    case category do
      :metabolic -> ["24323-8", "24325-3"]
      :hematology -> ["58410-2"]
      :lipids -> ["57021-8"]
      :urinalysis -> ["24347-7"]
      :liver -> ["24326-1"]
      :renal -> ["24362-6"]
      :thyroid -> ["55231-5"]
      _ -> []
    end
  end
end
