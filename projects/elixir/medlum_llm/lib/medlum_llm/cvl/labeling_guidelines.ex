defmodule MedlumLlm.CVL.LabelingGuidelines do
  @moduledoc """
  CVL NLI labeling guidelines for human annotators.

  Provides structured guidance for classifying Natural Language Inference (NLI)
  pairs in clinical contexts. These guidelines are used to:

  1. Train new labelers on the annotation task
  2. Generate documentation for labeling interfaces
  3. Provide context for disagreement resolution
  4. Support quality control and calibration

  ## NLI Classification Task

  Given a **premise** (source clinical text) and a **hypothesis** (generated claim),
  classify the relationship as:

  - **ENTAILMENT**: The hypothesis is fully supported by the premise
  - **CONTRADICTION**: The hypothesis conflicts with the premise
  - **NEUTRAL**: Cannot determine if hypothesis is true/false from premise

  ## Usage

      # Get full guidelines
      guidelines = MedlumLlm.CVL.LabelingGuidelines.full_guidelines()

      # Get verdict descriptions
      descriptions = MedlumLlm.CVL.LabelingGuidelines.verdict_descriptions()

      # Get common pitfalls
      pitfalls = MedlumLlm.CVL.LabelingGuidelines.common_pitfalls()

      # Generate markdown documentation
      markdown = MedlumLlm.CVL.LabelingGuidelines.to_markdown()
  """

  @doc """
  Returns the full labeling guidelines as a structured map.
  """
  @spec full_guidelines() :: map()
  def full_guidelines do
    %{
      task_overview: task_overview(),
      verdicts: verdict_descriptions(),
      confidence_scale: confidence_scale(),
      evidence_quality: evidence_quality_scale(),
      decision_tree: decision_tree(),
      examples: examples(),
      common_pitfalls: common_pitfalls(),
      clinical_considerations: clinical_considerations(),
      quality_standards: quality_standards()
    }
  end

  @doc """
  Returns the task overview description.
  """
  @spec task_overview() :: String.t()
  def task_overview do
    """
    ## CVL NLI Classification Task

    Your task is to determine the logical relationship between a **premise**
    (source clinical document) and a **hypothesis** (generated claim about
    the patient).

    This data trains the Clinical Verification Layer (CVL) to detect
    hallucinations in AI-generated medical summaries.

    ### Why This Matters

    Medical AI systems sometimes generate plausible-sounding but incorrect
    information. Your annotations help train systems to catch these errors
    before they reach clinicians and patients.

    ### Key Principles

    1. **Base judgments only on the premise text** - Don't use outside knowledge
    2. **Focus on factual accuracy** - Not grammar, style, or completeness
    3. **When uncertain, use NEUTRAL** - But consider if more context would help
    4. **Record your confidence honestly** - This helps calibrate the model
    """
  end

  @doc """
  Returns descriptions for each verdict option.
  """
  @spec verdict_descriptions() :: map()
  def verdict_descriptions do
    %{
      entailment: %{
        label: "ENTAILMENT",
        short_description: "Hypothesis is supported by the premise",
        full_description: """
        Select ENTAILMENT when:
        - The hypothesis directly restates information from the premise
        - The hypothesis is a valid inference from the premise
        - The premise explicitly or implicitly confirms the hypothesis
        - All claims in the hypothesis are supported by the premise

        Key question: "Can I conclude the hypothesis is TRUE based on the premise?"
        """,
        examples: [
          %{
            premise: "Patient is a 65-year-old male with Type 2 diabetes, A1C 8.2%",
            hypothesis: "The patient has diabetes",
            explanation: "The premise explicitly states the patient has Type 2 diabetes"
          },
          %{
            premise: "Labs show WBC 15,000, temperature 101.5F",
            hypothesis: "Lab results suggest possible infection",
            explanation: "Elevated WBC and fever are consistent with infection"
          }
        ]
      },
      contradiction: %{
        label: "CONTRADICTION",
        short_description: "Hypothesis conflicts with the premise",
        full_description: """
        Select CONTRADICTION when:
        - The hypothesis directly contradicts information in the premise
        - The premise states the opposite of the hypothesis
        - Key facts in the hypothesis are incorrect based on the premise
        - Numbers, dates, or medications don't match

        Key question: "Does the premise tell me the hypothesis is FALSE?"
        """,
        examples: [
          %{
            premise: "Patient is a 65-year-old male with Type 2 diabetes",
            hypothesis: "Patient has no history of diabetes",
            explanation: "The premise explicitly states diabetes; hypothesis denies it"
          },
          %{
            premise: "Metformin 500mg twice daily",
            hypothesis: "Patient takes Metformin 1000mg once daily",
            explanation: "Dosing regimen contradicts the premise"
          }
        ]
      },
      neutral: %{
        label: "NEUTRAL",
        short_description: "Cannot determine from premise alone",
        full_description: """
        Select NEUTRAL when:
        - The premise doesn't mention the topic of the hypothesis
        - The hypothesis requires information not in the premise
        - The claim is plausible but unverifiable from given text
        - The premise is ambiguous about the hypothesis

        Key question: "The premise doesn't tell me if the hypothesis is true or false"
        """,
        examples: [
          %{
            premise: "Patient is a 65-year-old male with Type 2 diabetes",
            hypothesis: "Patient has hypertension",
            explanation: "The premise doesn't mention blood pressure or hypertension"
          },
          %{
            premise: "Labs ordered for follow-up",
            hypothesis: "Labs were normal",
            explanation: "The premise mentions labs were ordered but not results"
          }
        ]
      }
    }
  end

  @doc """
  Returns the confidence scale descriptions.
  """
  @spec confidence_scale() :: map()
  def confidence_scale do
    %{
      1 => %{
        label: "Very Uncertain",
        description: "Guessing - unclear evidence, could easily be wrong",
        guidance: "Consider if you need more training on this type of sample"
      },
      2 => %{
        label: "Somewhat Uncertain",
        description: "Leaning toward an answer but significant doubt remains",
        guidance: "Flag for potential expert review"
      },
      3 => %{
        label: "Moderately Confident",
        description: "Reasonable evidence but some ambiguity exists",
        guidance: "Standard annotation - your best judgment"
      },
      4 => %{
        label: "Confident",
        description: "Good evidence supporting the verdict with minor uncertainty",
        guidance: "Strong annotation - proceed confidently"
      },
      5 => %{
        label: "Very Confident",
        description: "Clear, unambiguous evidence - highly certain",
        guidance: "Can be used for calibration and gold standard"
      }
    }
  end

  @doc """
  Returns the evidence quality scale descriptions.
  """
  @spec evidence_quality_scale() :: map()
  def evidence_quality_scale do
    %{
      clear: %{
        label: "Clear Evidence",
        description: "The premise provides explicit, unambiguous evidence for the judgment",
        examples: ["Direct statement of the fact", "Explicit confirmation or denial"]
      },
      partial: %{
        label: "Partial Evidence",
        description: "Some evidence available but requires inference or is incomplete",
        examples: ["Implied but not stated", "Related facts suggest the answer"]
      },
      ambiguous: %{
        label: "Ambiguous Evidence",
        description: "Evidence is unclear, contradictory, or open to interpretation",
        examples: ["Conflicting information", "Vague or imprecise language"]
      },
      missing: %{
        label: "Missing Evidence",
        description: "Required information to make judgment is absent from the premise",
        examples: ["Topic not mentioned", "Relevant section not provided"]
      }
    }
  end

  @doc """
  Returns a decision tree for making verdicts.
  """
  @spec decision_tree() :: [map()]
  def decision_tree do
    [
      %{
        step: 1,
        question: "Is the topic of the hypothesis mentioned in the premise?",
        if_no: "Consider NEUTRAL - the premise may not address this claim",
        if_yes: "Proceed to step 2"
      },
      %{
        step: 2,
        question: "Does the premise explicitly confirm the hypothesis?",
        if_yes: "Strong case for ENTAILMENT",
        if_no: "Proceed to step 3"
      },
      %{
        step: 3,
        question: "Does the premise explicitly contradict the hypothesis?",
        if_yes: "Strong case for CONTRADICTION",
        if_no: "Proceed to step 4"
      },
      %{
        step: 4,
        question: "Can you logically infer the hypothesis from the premise?",
        if_yes: "Consider ENTAILMENT",
        if_no: "Proceed to step 5"
      },
      %{
        step: 5,
        question: "Would accepting the hypothesis require information not in the premise?",
        if_yes: "NEUTRAL - cannot verify without additional information",
        if_no: "Re-examine: you may have missed evidence in steps 2-4"
      }
    ]
  end

  @doc """
  Returns example annotations.
  """
  @spec examples() :: [map()]
  def examples do
    [
      %{
        type: :entailment,
        premise: """
        HISTORY: 72-year-old female with past medical history of atrial fibrillation,
        hypertension, and chronic kidney disease stage 3. Currently on warfarin 5mg daily,
        lisinopril 20mg daily, and amlodipine 10mg daily.
        """,
        hypothesis: "Patient is being treated with blood thinners",
        verdict: "ENTAILMENT",
        confidence: 5,
        evidence_quality: "clear",
        reasoning:
          "Warfarin is explicitly listed as a current medication, and warfarin is a blood thinner (anticoagulant)"
      },
      %{
        type: :contradiction,
        premise: """
        LABS: Hemoglobin A1c: 5.4% (normal range 4.0-5.6%)
        Fasting glucose: 92 mg/dL (normal range 70-100 mg/dL)
        """,
        hypothesis: "Patient has poorly controlled diabetes",
        verdict: "CONTRADICTION",
        confidence: 5,
        evidence_quality: "clear",
        reasoning:
          "A1c of 5.4% is within normal range and does not indicate diabetes, let alone poorly controlled diabetes"
      },
      %{
        type: :neutral,
        premise: """
        CHIEF COMPLAINT: Patient presents with chest pain x 3 days.
        Describes as sharp, worse with deep breathing.
        """,
        hypothesis: "Patient has a history of coronary artery disease",
        verdict: "NEUTRAL",
        confidence: 4,
        evidence_quality: "missing",
        reasoning:
          "The premise describes current symptoms but doesn't mention past medical history or cardiac history"
      }
    ]
  end

  @doc """
  Returns common pitfalls to avoid.
  """
  @spec common_pitfalls() :: [map()]
  def common_pitfalls do
    [
      %{
        pitfall: "Using outside medical knowledge",
        description:
          "Judging based on what you know about medicine rather than what the premise states",
        example:
          "Premise says 'chest pain' - don't assume heart attack even though that's a common cause",
        correction: "Only use information explicitly stated or directly implied in the premise"
      },
      %{
        pitfall: "Confusing NEUTRAL with uncertainty",
        description: "Selecting NEUTRAL because you're unsure, not because the premise lacks info",
        example: "You're not sure if 'mild anemia' supports 'needs transfusion'",
        correction:
          "NEUTRAL means the premise doesn't address the hypothesis; use confidence for your certainty"
      },
      %{
        pitfall: "Overlooking partial information",
        description: "Missing implied or indirect evidence in the premise",
        example: "Premise mentions 'insulin pump' - implies diabetes even if not stated",
        correction: "Consider reasonable inferences, not just explicit statements"
      },
      %{
        pitfall: "Ignoring negation",
        description: "Missing 'no', 'denies', 'negative for', 'without' in the premise",
        example: "'Patient denies chest pain' means NO chest pain",
        correction: "Read carefully for negation words that flip the meaning"
      },
      %{
        pitfall: "Number mismatches",
        description: "Not catching differences in doses, dates, values, or counts",
        example: "Premise: 'Metformin 500mg' vs Hypothesis: 'Metformin 1000mg'",
        correction: "Always verify numbers match exactly"
      }
    ]
  end

  @doc """
  Returns clinical-specific considerations.
  """
  @spec clinical_considerations() :: [map()]
  def clinical_considerations do
    [
      %{
        topic: "Medication Terminology",
        guidance:
          "Brand and generic names may differ. Lisinopril = Prinivil = Zestril. When in doubt, use NEUTRAL.",
        examples: ["Tylenol vs acetaminophen", "Advil vs ibuprofen"]
      },
      %{
        topic: "Lab Value Interpretation",
        guidance:
          "Don't interpret lab values unless the premise does. 'WBC 15,000' isn't 'elevated' unless stated.",
        examples: ["Let the premise interpret significance", "Numbers alone aren't diagnoses"]
      },
      %{
        topic: "Temporal Relationships",
        guidance: "Pay attention to when things happened. 'Had' vs 'has' vs 'will have' matters.",
        examples: [
          "'History of MI' = past heart attack",
          "'Presenting with MI' = current heart attack"
        ]
      },
      %{
        topic: "Medical Abbreviations",
        guidance:
          "Common abbreviations have standard meanings. CHF = congestive heart failure, DM = diabetes mellitus.",
        examples: ["HTN = hypertension", "CAD = coronary artery disease"]
      }
    ]
  end

  @doc """
  Returns quality standards for annotations.
  """
  @spec quality_standards() :: map()
  def quality_standards do
    %{
      agreement_threshold: 0.80,
      min_labels_per_sample: 3,
      confidence_calibration:
        "High confidence annotations should have >90% accuracy on review",
      timing_guidelines: "Average 30-60 seconds per sample; complex samples may take longer",
      break_recommendations: "Take breaks every 30-50 annotations to maintain quality"
    }
  end

  @doc """
  Generates markdown documentation from the guidelines.
  """
  @spec to_markdown() :: String.t()
  def to_markdown do
    guidelines = full_guidelines()

    """
    # CVL NLI Labeling Guidelines

    #{guidelines.task_overview}

    ## Verdict Options

    #{format_verdicts_markdown(guidelines.verdicts)}

    ## Confidence Scale

    #{format_confidence_markdown(guidelines.confidence_scale)}

    ## Evidence Quality

    #{format_evidence_quality_markdown(guidelines.evidence_quality)}

    ## Decision Tree

    #{format_decision_tree_markdown(guidelines.decision_tree)}

    ## Examples

    #{format_examples_markdown(guidelines.examples)}

    ## Common Pitfalls

    #{format_pitfalls_markdown(guidelines.common_pitfalls)}

    ## Clinical Considerations

    #{format_clinical_markdown(guidelines.clinical_considerations)}

    ## Quality Standards

    - **Agreement threshold**: #{guidelines.quality_standards.agreement_threshold}
    - **Minimum labels per sample**: #{guidelines.quality_standards.min_labels_per_sample}
    - **Timing**: #{guidelines.quality_standards.timing_guidelines}
    - **Breaks**: #{guidelines.quality_standards.break_recommendations}

    ---

    *Generated by MedlumLlm.CVL.LabelingGuidelines*
    """
  end

  # Markdown formatting helpers

  defp format_verdicts_markdown(verdicts) do
    Enum.map_join([:entailment, :contradiction, :neutral], "\n\n", fn key ->
      verdict = verdicts[key]

      """
      ### #{verdict.label}

      #{verdict.full_description}

      **Examples:**
      #{format_verdict_examples_markdown(verdict.examples)}
      """
    end)
  end

  defp format_verdict_examples_markdown(examples) do
    Enum.map_join(examples, "\n", fn ex ->
      """
      - **Premise**: "#{ex.premise}"
        **Hypothesis**: "#{ex.hypothesis}"
        **Why**: #{ex.explanation}
      """
    end)
  end

  defp format_confidence_markdown(scale) do
    Enum.map_join(1..5, "\n", fn level ->
      info = scale[level]
      "- **#{level} - #{info.label}**: #{info.description}"
    end)
  end

  defp format_evidence_quality_markdown(scale) do
    Enum.map_join([:clear, :partial, :ambiguous, :missing], "\n", fn key ->
      info = scale[key]
      "- **#{info.label}**: #{info.description}"
    end)
  end

  defp format_decision_tree_markdown(tree) do
    Enum.map_join(tree, "\n\n", fn step ->
      """
      **Step #{step.step}**: #{step.question}
      - If yes: #{Map.get(step, :if_yes, "N/A")}
      - If no: #{Map.get(step, :if_no, "N/A")}
      """
    end)
  end

  defp format_examples_markdown(examples) do
    Enum.map_join(examples, "\n\n---\n\n", fn ex ->
      """
      **Type**: #{String.upcase(to_string(ex.type))}

      **Premise**:
      > #{String.trim(ex.premise)}

      **Hypothesis**: "#{ex.hypothesis}"

      **Verdict**: #{ex.verdict} (Confidence: #{ex.confidence}/5, Evidence: #{ex.evidence_quality})

      **Reasoning**: #{ex.reasoning}
      """
    end)
  end

  defp format_pitfalls_markdown(pitfalls) do
    Enum.map_join(pitfalls, "\n\n", fn p ->
      """
      ### #{p.pitfall}

      #{p.description}

      **Example**: #{p.example}

      **Correction**: #{p.correction}
      """
    end)
  end

  defp format_clinical_markdown(considerations) do
    Enum.map_join(considerations, "\n\n", fn c ->
      examples = Enum.join(c.examples, ", ")

      """
      ### #{c.topic}

      #{c.guidance}

      *Examples: #{examples}*
      """
    end)
  end
end
