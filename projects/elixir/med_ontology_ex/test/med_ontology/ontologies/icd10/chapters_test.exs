defmodule MedOntology.ICD10.ChaptersTest do
  use ExUnit.Case, async: true

  alias MedOntology.ICD10.Chapters

  describe "find_chapter/1" do
    test "finds chapter for code in range" do
      assert {:ok, %{number: "IV", title: title}} = Chapters.find_chapter("E11.9")
      assert title =~ "Endocrine"
    end

    test "finds chapter for category code" do
      assert {:ok, %{number: "IX", title: title}} = Chapters.find_chapter("I10")
      assert title =~ "circulatory"
    end

    test "finds chapter I for infectious diseases" do
      assert {:ok, %{number: "I"}} = Chapters.find_chapter("A00")
      assert {:ok, %{number: "I"}} = Chapters.find_chapter("B99")
    end

    test "finds chapter XXI for Z codes" do
      assert {:ok, %{number: "XXI", title: title}} = Chapters.find_chapter("Z00")
      assert title =~ "health status"
    end

    test "handles case-insensitivity" do
      assert {:ok, chapter1} = Chapters.find_chapter("e11.9")
      assert {:ok, chapter2} = Chapters.find_chapter("E11.9")
      assert chapter1.number == chapter2.number
    end

    test "returns not_found for invalid prefix" do
      assert {:error, :not_found} = Chapters.find_chapter("U00")
    end
  end

  describe "find_block/1" do
    test "finds block for diabetes code" do
      assert {:ok, %{range: "E10-E14", title: "Diabetes mellitus"}} = Chapters.find_block("E11.9")
    end

    test "finds block for hypertension code" do
      assert {:ok, %{range: "I10-I16", title: "Hypertensive diseases"}} = Chapters.find_block("I10")
    end

    test "returns not_found for code without known block" do
      assert {:error, :not_found} = Chapters.find_block("A00")
    end
  end

  describe "all/0" do
    test "returns all 21 chapters" do
      chapters = Chapters.all()
      assert length(chapters) == 21
    end

    test "chapters have required fields" do
      [chapter | _] = Chapters.all()
      assert Map.has_key?(chapter, :number)
      assert Map.has_key?(chapter, :title)
      assert Map.has_key?(chapter, :range)
    end

    test "first chapter is Chapter I" do
      [first | _] = Chapters.all()
      assert first.number == "I"
      assert first.range == "A00-B99"
    end

    test "last chapter is Chapter XXI" do
      chapters = Chapters.all()
      last = List.last(chapters)
      assert last.number == "XXI"
      assert last.range == "Z00-Z99"
    end
  end

  describe "blocks/0" do
    test "returns list of blocks" do
      blocks = Chapters.blocks()
      assert is_list(blocks)
      assert blocks != []
    end

    test "blocks have required fields" do
      [block | _] = Chapters.blocks()
      assert Map.has_key?(block, :range)
      assert Map.has_key?(block, :title)
    end

    test "includes diabetes block" do
      blocks = Chapters.blocks()
      diabetes_block = Enum.find(blocks, &(&1.range == "E10-E14"))
      assert diabetes_block != nil
      assert diabetes_block.title == "Diabetes mellitus"
    end
  end

  describe "chapter_number/1" do
    test "returns chapter number for valid code" do
      assert {:ok, "IV"} = Chapters.chapter_number("E11.9")
    end

    test "returns not_found for invalid code" do
      assert {:error, :not_found} = Chapters.chapter_number("U00")
    end
  end

  describe "chapter_range/1" do
    test "returns range for valid chapter number" do
      assert {:ok, {"E00", "E89"}} = Chapters.chapter_range("IV")
    end

    test "returns range for Chapter I" do
      assert {:ok, {"A00", "B99"}} = Chapters.chapter_range("I")
    end

    test "returns not_found for invalid chapter number" do
      assert {:error, :not_found} = Chapters.chapter_range("XXII")
    end
  end
end
