# MedCoder - Automated ICD-10 Coding

AI-assisted medical coding from clinical notes.

## Overview

Tools and approaches for automated ICD-10 code assignment from clinical text.

## Approaches

### 1. MedCodER (Retrieval-Augmented)

- Extract medical entities from notes
- Retrieve candidate ICD-10 codes
- Re-rank with LLM
- Reduces hallucination vs pure generation

### 2. LLMCoder (Fine-tuned)

- LLM fine-tuned on MIMIC-IV coding data
- Handles medical abbreviations and typos
- ~71% exact match accuracy

### 3. Traditional ML

- BioBERT/ClinicalBERT embeddings
- Multi-label classification
- Fast inference, good baseline

## Use Cases

1. Coding assistance (human-in-the-loop)
2. Retrospective coding audit
3. Research cohort identification
4. Revenue cycle optimization

## Installation

```bash
./setup.sh
source venv/bin/activate
```

## Directory Structure

```
medcoder/
├── data/
│   └── icd10/               # ICD-10 code definitions
├── models/                  # Trained models (gitignored)
├── src/
│   ├── extract_entities.py  # NER for medical entities
│   ├── retrieve_codes.py    # Code retrieval
│   └── predict.py           # End-to-end prediction
├── configs/
│   └── icd10_mapping.yaml
├── setup.sh
└── requirements.txt
```

## Example Workflow

```python
from medcoder import EntityExtractor, CodeRetriever, Ranker

# Input: clinical note
note = """
Patient presents with shortness of breath and chest pain.
History of COPD and CHF. Started on supplemental O2.
"""

# Step 1: Extract medical entities
extractor = EntityExtractor()
entities = extractor.extract(note)
# ['shortness of breath', 'chest pain', 'COPD', 'CHF']

# Step 2: Retrieve candidate codes
retriever = CodeRetriever()
candidates = retriever.retrieve(entities)
# [('J44.1', 'COPD with acute exacerbation'),
#  ('I50.9', 'Heart failure, unspecified'), ...]

# Step 3: Rank and select
ranker = Ranker()
predictions = ranker.rank(note, candidates, top_k=5)
```

## ICD-10 Resources

- CMS ICD-10: https://www.cms.gov/medicare/coding/icd10
- WHO ICD-10: https://icd.who.int/browse10/
- SNOMED-CT mapping: https://www.nlm.nih.gov/research/umls/

## Related Tools

- **MedCAT**: SNOMED-CT extraction
- **cTAKES**: Apache clinical NLP
- **ScispaCy**: Scientific/medical NER

## Resources

- MedCodER paper: https://arxiv.org/abs/2409.15368
- LLMCoder: https://github.com/hzvictor/LLMCoder
