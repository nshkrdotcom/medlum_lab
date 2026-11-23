defmodule MedlumLlm.Detectors.ClinicalPII.Patterns do
  @moduledoc """
  Clinical PII pattern definitions for HIPAA-compliant detection.

  Patterns are organized into three tiers based on reliability:

  - **Tier 1**: Fixed-format identifiers with high confidence (MRN, DEA, NPI, DOB)
  - **Tier 2**: Variable-format identifiers with medium confidence (medical dates, insurance IDs, room/bed)
  - **Tier 3**: Context-dependent entities with lower confidence (provider names, facility names)

  Each pattern includes:
  - `:type` - The PII type identifier
  - `:regex` - Compiled regex pattern
  - `:context_keywords` - Words that boost confidence when present nearby
  - `:base_confidence` - Default confidence score (0.0-1.0)
  - `:context_boost` - Additional confidence when context keywords are found
  """

  @type pattern :: %{
          type: atom(),
          regex: Regex.t(),
          context_keywords: [String.t()],
          base_confidence: float(),
          context_boost: float()
        }

  @doc """
  Returns all Tier 1 patterns (fixed-format, high confidence).

  These patterns detect MRN, DOB, NPI, and DEA numbers.
  """
  @spec tier_1_patterns() :: [pattern()]
  def tier_1_patterns do
    [
      # Medical Record Number - explicit MRN label
      %{
        type: :mrn,
        regex: ~r/\bMRN[:\s#]*([A-Z0-9]{5,12})\b/i,
        context_keywords: ["patient", "chart", "record", "admit", "medical record"],
        base_confidence: 0.90,
        context_boost: 0.05
      },
      # Medical Record Number - explicit label
      %{
        type: :mrn,
        regex: ~r/\b(?:medical\s+record|chart)\s*(?:number|#|id)?[:\s]*([A-Z0-9]{5,12})\b/i,
        context_keywords: ["patient"],
        base_confidence: 0.85,
        context_boost: 0.07
      },
      # Patient ID
      %{
        type: :mrn,
        regex: ~r/\b(?:patient\s+id|pt\s*id|acct)[:\s#]*([A-Z0-9]{5,15})\b/i,
        context_keywords: ["admit", "discharge", "chart"],
        base_confidence: 0.85,
        context_boost: 0.07
      },

      # Date of Birth - explicit DOB label
      %{
        type: :dob,
        regex: ~r/\bDOB[:\s]*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})\b/i,
        context_keywords: ["patient", "born", "age", "birthday"],
        base_confidence: 0.95,
        context_boost: 0.03
      },
      # Date of Birth - spelled out
      %{
        type: :dob,
        regex: ~r/\b(?:date\s+of\s+birth|birth\s*date)[:\s]*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})\b/i,
        context_keywords: [],
        base_confidence: 0.95,
        context_boost: 0.0
      },
      # Date of Birth - ISO format
      %{
        type: :dob,
        regex: ~r/\bDOB[:\s]*(\d{4}[\/\-]\d{1,2}[\/\-]\d{1,2})\b/i,
        context_keywords: ["patient"],
        base_confidence: 0.95,
        context_boost: 0.03
      },

      # National Provider Identifier (10 digits)
      %{
        type: :npi,
        regex: ~r/\bNPI[:\s#]*(\d{10})\b/i,
        context_keywords: ["provider", "physician", "doctor", "prescriber", "practitioner"],
        base_confidence: 0.95,
        context_boost: 0.03
      },

      # DEA Number (2 letters + 7 digits)
      %{
        type: :dea,
        regex: ~r/\bDEA[:\s#]*([A-Z]{2}\d{7})\b/i,
        context_keywords: ["prescriber", "controlled", "narcotic", "schedule"],
        base_confidence: 0.95,
        context_boost: 0.03
      }
    ]
  end

  @doc """
  Returns all Tier 2 patterns (variable-format, medium confidence).

  These patterns detect medical dates, insurance IDs, and room/bed numbers.
  """
  @spec tier_2_patterns() :: [pattern()]
  def tier_2_patterns do
    [
      # Medical dates - admission/discharge
      %{
        type: :medical_date,
        regex: ~r/\b(?:admit(?:ted)?|admission|discharge[d]?)[:\s]*(?:date)?[:\s]*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})\b/i,
        context_keywords: ["patient", "hospital"],
        base_confidence: 0.85,
        context_boost: 0.05
      },
      # Medical dates - service/visit
      %{
        type: :medical_date,
        regex: ~r/\b(?:service|visit|encounter|procedure|surgery)[:\s]*(?:date)?[:\s]*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})\b/i,
        context_keywords: ["patient", "clinic"],
        base_confidence: 0.85,
        context_boost: 0.05
      },
      # Medical dates - DOA/DOD
      %{
        type: :medical_date,
        regex: ~r/\b(?:DOA|DOD|date\s+of\s+(?:admission|discharge))[:\s]*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})\b/i,
        context_keywords: [],
        base_confidence: 0.90,
        context_boost: 0.05
      },

      # Insurance IDs - policy/member
      %{
        type: :insurance_id,
        regex: ~r/\b(?:policy|member|subscriber)\s*(?:id|#|number)?[:\s]*([A-Z0-9]{8,20})\b/i,
        context_keywords: ["insurance", "coverage", "plan", "payer"],
        base_confidence: 0.80,
        context_boost: 0.10
      },
      # Insurance IDs - group
      %{
        type: :insurance_id,
        regex: ~r/\b(?:group)\s*(?:id|#|number)?[:\s]*([A-Z0-9]{6,15})\b/i,
        context_keywords: ["insurance", "plan"],
        base_confidence: 0.75,
        context_boost: 0.10
      },

      # Medicare/Medicaid IDs - HICN format (9 digits + letter + optional digit)
      %{
        type: :medicare_id,
        regex: ~r/\b(?:HIC|HICN|Medicare(?:\s+ID)?)[:\s#]*(\d{9}[A-Z]\d?)\b/i,
        context_keywords: ["beneficiary", "cms"],
        base_confidence: 0.90,
        context_boost: 0.05
      },
      # Medicare Beneficiary Identifier (MBI) - new format
      %{
        type: :medicare_id,
        regex: ~r/\bMBI[:\s#]*([1-9][A-Z](?:[A-Z0-9]){2}\-?[A-Z0-9]{3}\-?[A-Z0-9]{4})\b/i,
        context_keywords: ["medicare"],
        base_confidence: 0.90,
        context_boost: 0.05
      },

      # Room/Bed numbers
      %{
        type: :room_bed,
        regex: ~r/\b(?:room|rm\.?)\s*(?:#|number)?[:\s]*(\d{1,4}[A-Z]?)\b/i,
        context_keywords: ["admitted", "patient", "ward", "floor", "unit"],
        base_confidence: 0.70,
        context_boost: 0.15
      },
      %{
        type: :room_bed,
        regex: ~r/\bbed\s*(?:#|number)?[:\s]*(\d{1,2}[A-Z]?)\b/i,
        context_keywords: ["patient", "room"],
        base_confidence: 0.70,
        context_boost: 0.15
      }
    ]
  end

  @doc """
  Returns all Tier 3 patterns (context-dependent, lower confidence).

  These patterns detect provider names and facility names.
  """
  @spec tier_3_patterns() :: [pattern()]
  def tier_3_patterns do
    [
      # Provider names - Dr. prefix
      %{
        type: :provider_name,
        regex: ~r/\bDr\.?\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)\b/,
        context_keywords: ["attending", "referring", "ordering", "prescribing", "treating"],
        base_confidence: 0.60,
        context_boost: 0.20
      },
      # Provider names - with credentials
      %{
        type: :provider_name,
        regex: ~r/\b([A-Z][a-z]+(?:\s+[A-Z]\.?)?\s+[A-Z][a-z]+),?\s*(?:MD|DO|NP|PA|RN|PhD|APRN)\b/,
        context_keywords: ["physician", "provider", "practitioner"],
        base_confidence: 0.75,
        context_boost: 0.10
      },
      # Provider names - explicit role
      %{
        type: :provider_name,
        regex: ~r/\b(?:attending|referring|treating|ordering)\s+(?:physician|doctor|provider)[:\s]+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)\b/i,
        context_keywords: [],
        base_confidence: 0.80,
        context_boost: 0.05
      },

      # Facility names - with facility type suffix
      %{
        type: :facility_name,
        regex: ~r/\b([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)\s+(?:Hospital|Medical\s+Center|Clinic|Health\s+(?:System|Center)|Regional\s+Medical)\b/,
        context_keywords: ["admitted", "transferred", "discharged", "referred"],
        base_confidence: 0.65,
        context_boost: 0.15
      },
      # Facility names - with preposition
      %{
        type: :facility_name,
        regex: ~r/\b(?:admitted\s+to|discharged\s+from|seen\s+at|transferred\s+to)\s+([A-Z][A-Za-z\s]+?)(?:\s+on|\s+for|\.|\,)/i,
        context_keywords: [],
        base_confidence: 0.70,
        context_boost: 0.10
      }
    ]
  end

  @doc """
  Returns all patterns from all tiers.
  """
  @spec all_patterns() :: [pattern()]
  def all_patterns, do: tier_1_patterns() ++ tier_2_patterns() ++ tier_3_patterns()

  @doc """
  Returns patterns for aggressive mode (all patterns).

  Use this for export/sanitization where higher recall is preferred.
  """
  @spec aggressive_patterns() :: [pattern()]
  def aggressive_patterns, do: all_patterns()

  @doc """
  Returns patterns for standard mode (Tier 1 + Tier 2).

  Use this for real-time validation where precision is preferred.
  """
  @spec standard_patterns() :: [pattern()]
  def standard_patterns, do: tier_1_patterns() ++ tier_2_patterns()

  @doc """
  Returns the list of all detectable clinical PII types.
  """
  @spec pii_types() :: [atom()]
  def pii_types do
    all_patterns()
    |> Enum.map(& &1.type)
    |> Enum.uniq()
  end

  @doc """
  Returns patterns filtered by type.
  """
  @spec patterns_for_type(atom()) :: [pattern()]
  def patterns_for_type(type) do
    Enum.filter(all_patterns(), &(&1.type == type))
  end
end
