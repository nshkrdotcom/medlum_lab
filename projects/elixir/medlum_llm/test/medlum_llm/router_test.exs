defmodule MedlumLlm.RouterTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.Router

  describe "route/1" do
    test "routes quick_summary to fast chat model" do
      assert {:ok, config} = Router.route(:quick_summary)

      assert config.category == :chat
      assert config.tier == :fast
      assert is_integer(config.timeout)
      assert config.timeout <= 30_000
    end

    test "routes detailed_summary to balanced chat model" do
      assert {:ok, config} = Router.route(:detailed_summary)

      assert config.category == :chat
      assert config.tier == :balanced
      assert config.timeout <= 60_000
    end

    test "routes critical_analysis to accurate chat model" do
      assert {:ok, config} = Router.route(:critical_analysis)

      assert config.category == :chat
      assert config.tier == :accurate
      assert config.timeout >= 120_000
    end

    test "routes hallucination_check to reasoning model" do
      assert {:ok, config} = Router.route(:hallucination_check)

      assert config.category == :chat
      assert config.tier == :accurate
    end

    test "routes medication_extraction to pharma NER" do
      assert {:ok, config} = Router.route(:medication_extraction)

      assert config.category == :ner
      assert config.domain == :pharma
    end

    test "routes disease_extraction to disease NER" do
      assert {:ok, config} = Router.route(:disease_extraction)

      assert config.category == :ner
      assert config.domain == :disease
    end

    test "routes lab_extraction to chemical NER" do
      assert {:ok, config} = Router.route(:lab_extraction)

      assert config.category == :ner
      assert config.domain == :chemical
    end

    test "routes batch_pii to accurate PII model" do
      assert {:ok, config} = Router.route(:batch_pii)

      assert config.category == :pii
      assert config.tier == :accurate
    end

    test "routes realtime_pii to fast PII model" do
      assert {:ok, config} = Router.route(:realtime_pii)

      assert config.category == :pii
      assert config.tier == :fast
    end

    test "routes document_search to embed model" do
      assert {:ok, config} = Router.route(:document_search)

      assert config.category == :embed
    end

    test "routes sentence_similarity to embed model" do
      assert {:ok, config} = Router.route(:sentence_similarity)

      assert config.category == :embed
    end

    test "returns error for unknown task" do
      assert {:error, :unknown_task} = Router.route(:unknown_task)
    end
  end

  describe "route/2 with options" do
    test "allows tier override" do
      assert {:ok, config} = Router.route(:quick_summary, tier: :accurate)

      assert config.tier == :accurate
    end

    test "allows timeout override" do
      assert {:ok, config} = Router.route(:quick_summary, timeout: 120_000)

      assert config.timeout == 120_000
    end

    test "allows specific model override" do
      assert {:ok, config} = Router.route(:quick_summary, model: :ii_medical_8b)

      assert config.model == :ii_medical_8b
    end
  end

  describe "get_fallbacks/1" do
    test "returns fallback chain for chat models" do
      fallbacks = Router.get_fallbacks(:critical_analysis)

      assert is_list(fallbacks)
      assert length(fallbacks) >= 2
    end

    test "returns fallback chain for NER models" do
      fallbacks = Router.get_fallbacks(:medication_extraction)

      assert is_list(fallbacks)
      assert length(fallbacks) >= 2
    end

    test "returns empty list for unknown task" do
      assert [] = Router.get_fallbacks(:unknown_task)
    end
  end

  describe "available_tasks/0" do
    test "returns list of all available tasks" do
      tasks = Router.available_tasks()

      assert is_list(tasks)
      assert :quick_summary in tasks
      assert :detailed_summary in tasks
      assert :critical_analysis in tasks
      assert :medication_extraction in tasks
      assert :disease_extraction in tasks
      assert :batch_pii in tasks
      assert :document_search in tasks
    end
  end

  describe "task_info/1" do
    test "returns info for known task" do
      assert {:ok, info} = Router.task_info(:quick_summary)

      assert info.name == :quick_summary
      assert is_binary(info.description)
      assert is_atom(info.category)
      assert is_atom(info.tier)
    end

    test "returns error for unknown task" do
      assert {:error, :unknown_task} = Router.task_info(:unknown_task)
    end
  end
end
