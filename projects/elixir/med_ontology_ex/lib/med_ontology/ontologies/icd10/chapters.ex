defmodule MedOntology.ICD10.Chapters do
  @moduledoc """
  ICD-10-CM chapter and block definitions.

  ICD-10-CM codes are organized hierarchically into chapters based on the first
  character(s) of the code. This module provides chapter lookup and enumeration.

  ## ICD-10-CM Structure

      Chapter (e.g., "Endocrine, nutritional and metabolic diseases")
        +-- Block (e.g., E10-E14 "Diabetes mellitus")
             +-- Category (e.g., E11 "Type 2 diabetes mellitus")
                  +-- Subcategory (e.g., E11.9 "Type 2 DM without complications")

  ## Examples

      # Find chapter for a code
      iex> MedOntology.ICD10.Chapters.find_chapter("E11.9")
      {:ok, %{number: "IV", title: "Endocrine, nutritional and metabolic diseases"}}

      # Get all chapters
      iex> MedOntology.ICD10.Chapters.all()
      [%{number: "I", title: "Certain infectious and parasitic diseases", range: "A00-B99"}, ...]

  """

  @chapters [
    {"A00", "B99", "I", "Certain infectious and parasitic diseases"},
    {"C00", "D49", "II", "Neoplasms"},
    {"D50", "D89", "III", "Diseases of the blood and blood-forming organs and certain disorders involving the immune mechanism"},
    {"E00", "E89", "IV", "Endocrine, nutritional and metabolic diseases"},
    {"F01", "F99", "V", "Mental, Behavioral and Neurodevelopmental disorders"},
    {"G00", "G99", "VI", "Diseases of the nervous system"},
    {"H00", "H59", "VII", "Diseases of the eye and adnexa"},
    {"H60", "H95", "VIII", "Diseases of the ear and mastoid process"},
    {"I00", "I99", "IX", "Diseases of the circulatory system"},
    {"J00", "J99", "X", "Diseases of the respiratory system"},
    {"K00", "K95", "XI", "Diseases of the digestive system"},
    {"L00", "L99", "XII", "Diseases of the skin and subcutaneous tissue"},
    {"M00", "M99", "XIII", "Diseases of the musculoskeletal system and connective tissue"},
    {"N00", "N99", "XIV", "Diseases of the genitourinary system"},
    {"O00", "O9A", "XV", "Pregnancy, childbirth and the puerperium"},
    {"P00", "P96", "XVI", "Certain conditions originating in the perinatal period"},
    {"Q00", "Q99", "XVII", "Congenital malformations, deformations and chromosomal abnormalities"},
    {"R00", "R99", "XVIII", "Symptoms, signs and abnormal clinical and laboratory findings, not elsewhere classified"},
    {"S00", "T88", "XIX", "Injury, poisoning and certain other consequences of external causes"},
    {"V00", "Y99", "XX", "External causes of morbidity"},
    {"Z00", "Z99", "XXI", "Factors influencing health status and contact with health services"}
  ]

  # Common blocks within chapters (subset for development)
  @blocks [
    {"E10", "E14", "Diabetes mellitus"},
    {"I10", "I16", "Hypertensive diseases"},
    {"J00", "J06", "Acute upper respiratory infections"},
    {"J09", "J18", "Influenza and pneumonia"},
    {"M50", "M54", "Other dorsopathies"},
    {"F30", "F39", "Mood [affective] disorders"},
    {"K20", "K31", "Diseases of esophagus, stomach and duodenum"}
  ]

  @doc """
  Find the chapter for a given ICD-10 code.

  Returns the chapter number (Roman numeral) and title for the given code.

  ## Examples

      iex> MedOntology.ICD10.Chapters.find_chapter("E11.9")
      {:ok, %{number: "IV", title: "Endocrine, nutritional and metabolic diseases"}}

      iex> MedOntology.ICD10.Chapters.find_chapter("ZZZ.99")
      {:error, :not_found}

  """
  @spec find_chapter(String.t()) :: {:ok, %{number: String.t(), title: String.t()}} | {:error, :not_found}
  def find_chapter(code) when is_binary(code) do
    prefix = code |> String.slice(0, 3) |> String.upcase()

    @chapters
    |> Enum.find(fn {range_start, range_end, _num, _title} ->
      prefix >= range_start and prefix <= range_end
    end)
    |> case do
      {_, _, num, title} -> {:ok, %{number: num, title: title}}
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Find the block for a given ICD-10 code.

  Returns the block range and title for the given code, if available.

  ## Examples

      iex> MedOntology.ICD10.Chapters.find_block("E11.9")
      {:ok, %{range: "E10-E14", title: "Diabetes mellitus"}}

      iex> MedOntology.ICD10.Chapters.find_block("A00")
      {:error, :not_found}

  """
  @spec find_block(String.t()) :: {:ok, %{range: String.t(), title: String.t()}} | {:error, :not_found}
  def find_block(code) when is_binary(code) do
    category = code |> extract_category() |> String.upcase()

    @blocks
    |> Enum.find(fn {range_start, range_end, _title} ->
      category >= range_start and category <= range_end
    end)
    |> case do
      {start_code, end_code, title} ->
        {:ok, %{range: "#{start_code}-#{end_code}", title: title}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Get all chapters.

  Returns a list of all ICD-10-CM chapters with their number, title, and code range.

  ## Examples

      iex> chapters = MedOntology.ICD10.Chapters.all()
      iex> length(chapters)
      21
      iex> hd(chapters)
      %{number: "I", title: "Certain infectious and parasitic diseases", range: "A00-B99"}

  """
  @spec all() :: [%{number: String.t(), title: String.t(), range: String.t()}]
  def all do
    Enum.map(@chapters, fn {start_code, end_code, num, title} ->
      %{
        number: num,
        title: title,
        range: "#{start_code}-#{end_code}"
      }
    end)
  end

  @doc """
  Get all known blocks.

  Returns a list of common ICD-10-CM blocks with their range and title.
  Note: This is a subset of all blocks; the full set would be loaded from CMS data.

  ## Examples

      iex> blocks = MedOntology.ICD10.Chapters.blocks()
      iex> Enum.find(blocks, &(&1.range == "E10-E14"))
      %{range: "E10-E14", title: "Diabetes mellitus"}

  """
  @spec blocks() :: [%{range: String.t(), title: String.t()}]
  def blocks do
    Enum.map(@blocks, fn {start_code, end_code, title} ->
      %{
        range: "#{start_code}-#{end_code}",
        title: title
      }
    end)
  end

  @doc """
  Get the chapter number (Roman numeral) for a given code.

  ## Examples

      iex> MedOntology.ICD10.Chapters.chapter_number("E11.9")
      {:ok, "IV"}

  """
  @spec chapter_number(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def chapter_number(code) do
    case find_chapter(code) do
      {:ok, %{number: num}} -> {:ok, num}
      error -> error
    end
  end

  @doc """
  Get all codes in a chapter by chapter number.

  Returns the code range for the chapter.

  ## Examples

      iex> MedOntology.ICD10.Chapters.chapter_range("IV")
      {:ok, {"E00", "E89"}}

  """
  @spec chapter_range(String.t()) :: {:ok, {String.t(), String.t()}} | {:error, :not_found}
  def chapter_range(chapter_number) when is_binary(chapter_number) do
    @chapters
    |> Enum.find(fn {_start, _end, num, _title} -> num == chapter_number end)
    |> case do
      {start_code, end_code, _num, _title} -> {:ok, {start_code, end_code}}
      nil -> {:error, :not_found}
    end
  end

  # Private helpers

  defp extract_category(code) do
    # Category is the first 3 characters (letter + 2 digits)
    String.slice(code, 0, 3)
  end
end
