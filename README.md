# Analytical Data Science Programmer — Coding Assessment

This repository contains my solutions to the **Pharmaverse Expertise and Python Coding Assessment** (Roche PD Data Science). It covers SDTM domain creation, ADaM ADSL derivation, clinical TLG reporting, and a bonus GenAI/Python exercise.

## Repository Structure

```
.
├── README.md
├── question_1_sdtm/
│   ├── 01_create_ds_domain.R
│   ├── output/
│   │   └── ds_domain.rds          # (or .csv / .sas7bdat)
│   └── log/
│       └── 01_create_ds_domain.log
│
├── question_2_adam/
│   ├── create_adsl.R
│   ├── output/
│   │   └── adsl.rds
│   └── log/
│       └── create_adsl.log
│
├── question_3_tlg/
│   ├── 01_create_ae_summary_table.R
│   ├── 02_create_visualizations.R
│   ├── output/
│   │   ├── ae_summary_table.html
│   │   ├── ae_severity_by_treatment.png
│   │   └── top10_ae_incidence.png
│   └── log/
│       ├── 01_create_ae_summary_table.log
│       └── 02_create_visualizations.log
│
└── question_4_genai/            # Bonus
    ├── clinical_trial_data_agent.py
    ├── test_queries.py
    └── output/
        └── test_run.log
```

## Contents by Folder

### `question_1_sdtm/` — SDTM DS Domain Creation
- **Objective:** Build the SDTM Disposition (DS) domain from `pharmaverseraw::ds_raw` using `{sdtm.oak}`.
- **Script:** `01_create_ds_domain.R` — maps raw eCRF data to DS using the study controlled terminology (`study_ct`), producing `STUDYID, DOMAIN, USUBJID, DSSEQ, DSTERM, DSDECOD, DSCAT, VISITNUM, VISIT, DSDTC, DSSTDTC, DSSTDY`.
- **Output:** Resulting DS dataset + run log confirming error-free execution.

### `question_2_adam/` — ADaM ADSL Dataset Creation
- **Objective:** Derive the ADSL dataset from SDTM sources (`dm`, `vs`, `ex`, `ds`, `ae`) using `{admiral}`.
- **Script:** `create_adsl.R` — derives standard ADSL variables plus:
  - `AGEGR9` / `AGEGR9N` — age grouping (`<18`, `18-50`, `>50`)
  - `TRTSDTM` / `TRTSTMF` — treatment start datetime with partial imputation
  - `ITTFL` — intent-to-treat flag based on `DM.ARM`
  - `LSTAVLDT` — last known alive date across VS/AE/DS/EX
- **Output:** Resulting ADSL dataset + run log.

### `question_3_tlg/` — TLG: Adverse Events Reporting
- **Objective:** Regulatory-style AE reporting from `pharmaverseadam::adae` / `adsl`.
- **Scripts:**
  - `01_create_ae_summary_table.R` — TEAE summary table (`{gtsummary}`) by `ACTARM`, with total column, sorted by descending frequency.
  - `02_create_visualizations.R` — Plot 1 (AE severity by treatment, stacked bar) and Plot 2 (Top 10 AEs with 95% CI).
- **Output:** `ae_summary_table.html`, two PNG plots, run logs.

### `question_4_genai/` — GenAI Clinical Data Assistant (Bonus, Python)
- **Objective:** `ClinicalTrialDataAgent` that parses natural-language questions about `adae.csv` into structured JSON (`target_column`, `filter_value`) and applies the corresponding Pandas filter.
- **Files:**
  - `clinical_trial_data_agent.py` — schema definition, LLM prompt/parse logic (or mocked LLM response), and filter execution returning unique `USUBJID` count + matching IDs.
  - `test_queries.py` — runs 3 example natural-language queries and prints results.

## How to Run

1. Clone this repository and open it in [Posit Cloud](https://posit.cloud/) or a local RStudio session (R 4.2.0+).
2. Install dependencies:
   ```r
   install.packages(c("admiral", "sdtm.oak", "gt", "gtsummary", "ggplot2", "dplyr", "tidyr"))
   ```
3. Run each question's script(s) in order from the repository root, e.g.:
   ```r
   source("question_1_sdtm/01_create_ds_domain.R")
   source("question_2_adam/create_adsl.R")
   source("question_3_tlg/01_create_ae_summary_table.R")
   source("question_3_tlg/02_create_visualizations.R")
   ```
4. For the Python bonus question:
   ```bash
   pip install -r question_4_genai/requirements.txt
   python question_4_genai/test_queries.py
   ```

## Notes for Reviewers

- Each script is self-contained and can be run independently, provided the required input packages (`pharmaverseraw`, `pharmaversesdtm`, `pharmaverseadam`) are installed.
- Log files under each `log/` folder serve as evidence of error-free execution.
- Key derivation logic is documented inline via comments, particularly for the custom ADSL variables (`AGEGR9N`, `TRTSDTM/TRTSTMF`, `ITTFL`, `LSTAVLDT`) and the DS domain mapping.
- A short video walkthrough (link in the submission form) explains the overall approach, design decisions, and challenges encountered.
