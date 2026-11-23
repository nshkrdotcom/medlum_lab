defmodule MedlumLlm.TestHelpers do
  @moduledoc """
  Helper functions for testing MedlumLlm.
  """

  @doc """
  Generate a fake embedding vector of specified dimensions.
  """
  def generate_fake_embedding(dimensions \\ 768) do
    :rand.seed(:exsss, {1, 2, 3})
    Enum.map(1..dimensions, fn _ -> :rand.uniform() - 0.5 end)
  end

  @doc """
  Generate multiple fake embeddings.
  """
  def generate_fake_embeddings(count, dimensions \\ 768) do
    Enum.map(1..count, fn i ->
      :rand.seed(:exsss, {i, i + 1, i + 2})
      Enum.map(1..dimensions, fn _ -> :rand.uniform() - 0.5 end)
    end)
  end

  @doc """
  Check if Ollama is running on localhost.
  """
  def ollama_available? do
    case :gen_tcp.connect(~c"localhost", 11434, [], 1000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _} ->
        false
    end
  end

  @doc """
  Skip test if Ollama is not available.
  """
  def skip_if_no_ollama do
    if not ollama_available?() do
      {:skip, "Ollama not running on localhost:11434"}
    else
      :ok
    end
  end

  @doc """
  Sample clinical notes for testing.
  """
  def sample_clinical_notes do
    [
      "Patient presents with acute chest pain radiating to left arm. ECG shows ST elevation.",
      "Type 2 diabetes mellitus with poor glycemic control. HbA1c 9.8%.",
      "COPD exacerbation with increased dyspnea and productive cough.",
      "Left knee MRI reveals complete ACL tear.",
      "New onset seizure activity. EEG shows epileptiform discharges."
    ]
  end

  @doc """
  Sample ICD-10 codes for testing.
  """
  def sample_icd10_codes do
    [
      %{code: "I21.0", description: "ST elevation myocardial infarction of anterior wall"},
      %{code: "E11.65", description: "Type 2 diabetes mellitus with hyperglycemia"},
      %{code: "J44.1", description: "COPD with acute exacerbation"},
      %{code: "S83.511A", description: "Sprain of anterior cruciate ligament"},
      %{code: "G40.209", description: "Epilepsy, unspecified"}
    ]
  end
end
