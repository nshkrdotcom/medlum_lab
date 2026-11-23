defmodule MedlumLlm.CVL.DifferentialDBTest do
  use ExUnit.Case

  alias MedlumLlm.CVL.DifferentialDB

  describe "get_supporting_symptoms/1" do
    test "returns symptoms for known diagnosis" do
      {:ok, info} = DifferentialDB.get_supporting_symptoms("myocardial infarction")

      assert is_list(info.required)
      assert is_list(info.supporting)
      assert is_list(info.contradicting)
      assert "chest pain" in info.supporting
      assert "dyspnea" in info.supporting
    end

    test "returns symptoms for diabetes" do
      {:ok, info} = DifferentialDB.get_supporting_symptoms("diabetes")

      assert "polyuria" in info.supporting
      assert "polydipsia" in info.supporting
      assert "fatigue" in info.supporting
    end

    test "normalizes diabetes variations" do
      {:ok, info1} = DifferentialDB.get_supporting_symptoms("type 2 diabetes")
      {:ok, info2} = DifferentialDB.get_supporting_symptoms("type 1 diabetes mellitus")
      {:ok, info3} = DifferentialDB.get_supporting_symptoms("diabetes")

      assert info1 == info2
      assert info2 == info3
    end

    test "returns symptoms for pneumonia" do
      {:ok, info} = DifferentialDB.get_supporting_symptoms("pneumonia")

      assert "cough" in info.supporting
      assert "fever" in info.supporting
      assert "dyspnea" in info.supporting
    end

    test "returns error for unknown diagnosis" do
      assert {:error, :not_found} = DifferentialDB.get_supporting_symptoms("madeupitis")
    end

    test "handles case insensitivity" do
      {:ok, info1} = DifferentialDB.get_supporting_symptoms("PNEUMONIA")
      {:ok, info2} = DifferentialDB.get_supporting_symptoms("pneumonia")

      assert info1 == info2
    end

    test "handles whitespace" do
      {:ok, info1} = DifferentialDB.get_supporting_symptoms("  pneumonia  ")
      {:ok, info2} = DifferentialDB.get_supporting_symptoms("pneumonia")

      assert info1 == info2
    end
  end

  describe "get_red_flags/1" do
    test "returns red flags for chest pain" do
      {:ok, flags} = DifferentialDB.get_red_flags(["chest pain"])

      assert length(flags) >= 1
      flag = hd(flags)
      assert is_binary(flag.description)
      assert is_binary(flag.condition)
      assert is_list(flag.requires_workup_for)
    end

    test "returns red flags for syncope" do
      {:ok, flags} = DifferentialDB.get_red_flags(["syncope"])

      assert length(flags) >= 1
      flag = hd(flags)
      assert "stroke" in flag.requires_workup_for or "arrhythmia" in flag.requires_workup_for
    end

    test "returns red flags for fever" do
      {:ok, flags} = DifferentialDB.get_red_flags(["fever"])

      assert length(flags) >= 1
      flag = hd(flags)
      assert "meningitis" in flag.requires_workup_for or "sepsis" in flag.requires_workup_for
    end

    test "returns red flags for weakness" do
      {:ok, flags} = DifferentialDB.get_red_flags(["weakness"])

      assert length(flags) >= 1
      flag = hd(flags)
      assert "stroke" in flag.requires_workup_for
    end

    test "returns combined red flags for multiple symptoms" do
      {:ok, flags} = DifferentialDB.get_red_flags(["chest pain", "syncope"])

      # Should have red flags from both symptoms
      assert length(flags) >= 2
    end

    test "deduplicates red flags" do
      {:ok, flags} = DifferentialDB.get_red_flags(["fever", "fever", "fever"])

      # Should only have one set of fever flags
      fever_flags = Enum.filter(flags, &String.contains?(&1.description, "fever"))
      assert length(fever_flags) == 1
    end

    test "returns error for symptoms without red flags" do
      assert {:error, :no_red_flags} = DifferentialDB.get_red_flags(["mild headache"])
    end

    test "returns error for empty symptom list" do
      assert {:error, :no_red_flags} = DifferentialDB.get_red_flags([])
    end
  end

  describe "get_contradicting_symptoms/1" do
    test "returns contradicting symptoms for known diagnosis" do
      {:ok, contras} = DifferentialDB.get_contradicting_symptoms("myocardial infarction")

      assert is_list(contras)
    end

    test "returns error for unknown diagnosis" do
      assert {:error, :not_found} = DifferentialDB.get_contradicting_symptoms("unknown disease")
    end
  end

  describe "list_diagnoses/0" do
    test "returns all supported diagnoses" do
      diagnoses = DifferentialDB.list_diagnoses()

      assert is_list(diagnoses)
      assert length(diagnoses) >= 10
      assert "myocardial infarction" in diagnoses
      assert "pneumonia" in diagnoses
      assert "diabetes" in diagnoses
      assert "hypertension" in diagnoses
      assert "heart failure" in diagnoses
    end

    test "returns sorted list" do
      diagnoses = DifferentialDB.list_diagnoses()

      assert diagnoses == Enum.sort(diagnoses)
    end
  end

  describe "list_red_flag_symptoms/0" do
    test "returns all red flag symptoms" do
      symptoms = DifferentialDB.list_red_flag_symptoms()

      assert is_list(symptoms)
      assert "chest pain" in symptoms
      assert "syncope" in symptoms
      assert "fever" in symptoms
      assert "weakness" in symptoms
    end

    test "returns sorted list" do
      symptoms = DifferentialDB.list_red_flag_symptoms()

      assert symptoms == Enum.sort(symptoms)
    end
  end
end
