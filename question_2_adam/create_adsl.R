#===============================================================================
# Program Name   : create_adsl.R
# Study          : [Study ID / Protocol Number]
# Purpose        : Create the ADaM Subject-Level Analysis (ADSL) dataset from
#                  SDTM source data using {admiral} and tidyverse tools.
#
# Input          : pharmaversesdtm::dm
#                  pharmaversesdtm::vs
#                  pharmaversesdtm::ex
#                  pharmaversesdtm::ds
#                  pharmaversesdtm::ae
#
# Output         : question_2_adam/output/adsl.rds  (ADaM ADSL dataset)
#                  Derived variables include:
#                    - AGEGR9 / AGEGR9N : Age group ("<18","18-50",">50") and
#                                         numeric equivalent (1,2,3)
#                    - TRTSDTM / TRTSTMF: Treatment start datetime (first valid
#                                         dose, EX.EXSTDTC) with partial time
#                                         imputation (seconds only -> no flag)
#                    - ITTFL            : "Y"/"N" based on DM.ARM populated
#                    - LSTAVLDT         : Last known alive date across
#                                         VS/AE/DS/EX records
#                  Supporting standard ADSL variables (TRT01P/TRT01A, TRTSDT/
#                  TRTEDT, TRTEDTM/TRTETMF, etc.) are also derived, following
#                  the {admiral} ADSL vignette, since TRTEDTM is required as
#                  an input to the LSTAVLDT derivation below.
#
# Author         : Tapender Singh
# Date Created   : 2026-09-06
# Last Modified  : 2026-09-06
#
# R Version      : R 4.5.3
# Packages Used  : admiral, admiraldev, pharmaversesdtm, dplyr, tidyr, stringr
#
# Notes          : - DM domain used as ADSL base per {admiral} ADSL vignette
#                  - Valid dose defined as EX.EXDOSE > 0, or EX.EXDOSE == 0 AND
#                    EX.EXTRT contains "PLACEBO"
#                  - Per spec: "If only seconds are missing then do not
#                    populate the imputation flag (TRTSTMF)" -> handled via
#                    derive_vars_dtm(time_imputation = "00:00:00",
#                    ignore_seconds_flag = TRUE)
#                  - LSTAVLDT combines: last VS visit date (valid result),
#                    last AE onset date, last DS disposition date, and last
#                    valid-dose EX date (via TRTEDTM), taking the maximum
#                  - Derivations follow {admiral} functions where possible
#
# Revision History:
#   Date        Author            Description
#   ----------  ----------------  --------------------------------------------
#   2026-09-06  Tapender Singh    Initial version
#
#===============================================================================

# --- 0. Setup -----------------------------------------------------------------

library(metacore)
library(metatools)
library(admiral)
library(pharmaversesdtm)
library(xportr)
library(dplyr)
library(tidyr)
library(stringr)
library(lubridate)

dir.create("question_2_adam/output", recursive = TRUE, showWarnings = FALSE)
dir.create("question_2_adam/log", recursive = TRUE, showWarnings = FALSE)

log_file <- "question_2_adam/log/create_adsl.log"

con <- file(log_file, open = "wt")
sink(con, split = TRUE)
sink(con, type = "message", append = TRUE)

cat("=======================================================================\n")
cat("Log for create_adsl.R\n")
cat("Run started:", format(Sys.time()), "\n")
cat("=======================================================================\n\n")

result <- tryCatch({
  
  # --- 1. Read source SDTM data ------------------------------------------------
  
  dm <- pharmaversesdtm::dm
  vs <- pharmaversesdtm::vs
  ex <- pharmaversesdtm::ex
  ds <- pharmaversesdtm::ds
  ae <- pharmaversesdtm::ae
  
  # When SAS datasets are imported into R using haven::read_sas(), missing
  # character values from SAS appear as "" characters in R, instead of appearing
  # as NA values. Further details can be obtained via the following link:
  # https://pharmaverse.github.io/admiral/articles/admiral.html#handling-of-missing-values
  dm <- convert_blanks_to_na(dm)
  ds <- convert_blanks_to_na(ds)
  ex <- convert_blanks_to_na(ex)
  ae <- convert_blanks_to_na(ae)
  vs <- convert_blanks_to_na(vs)
  suppdm <- convert_blanks_to_na(suppdm)
  
  # Combine Parent and Supp - very handy! ----
  dm_suppdm <- combine_supp(dm, suppdm)
  
  # --- 2. Start ADSL from DM ----------------------------------------------------
  # Per {admiral} ADSL vignette: "Start by assigning pharmaversesdtm::dm to an
  # adsl object."
  
  adsl <- dm_suppdm %>%
    mutate(
      TRT01P = ARM,
      TRT01A = ACTARM
    )
  
  # --- 3. Derive AGEGR9 / AGEGR9N (age grouping) ---------------------------------
  # Categories: "<18", "18 - 50", ">50" ; numeric groupings 1, 2, 3
  
  format_agegr1 <- function(age) {
    case_when(
      age < 18 ~ "<18",
      between(age, 18, 50) ~ "18-50",
      age > 50 ~ ">50",
      TRUE ~ "Missing"
    )
  }
  
  format_agegr1n <- function(age) {
    case_when(
      age < 18 ~ 1,
      between(age, 18, 50) ~ 2,
      age > 50 ~ 3,
      TRUE ~ 4
    )
  }
  
  adsl <- adsl %>%
    mutate(
      AGEGR9 = format_agegr1(AGE),
      AGEGR9N = format_agegr1n(AGE)
    )
  
  # --- 4. Pre-process EX: convert EXSTDTC/EXENDTC to datetime -------------------
  # Impute completely/partially missing time to 00:00:00 for start; do not
  # impute date. Per the assessment spec: if ONLY seconds are missing, do NOT
  # populate the imputation flag (TRTSTMF) - achieved by not imputing seconds
  # as part of the imputation target (only hours/minutes are imputed).
  
  ex_ext <- ex %>%
    derive_vars_dtm(
      dtc = EXSTDTC,
      new_vars_prefix = "EXST",
      ignore_seconds_flag = TRUE
    ) %>%
    derive_vars_dtm(
      dtc = EXENDTC,
      new_vars_prefix = "EXEN",
      time_imputation = "23:59:59",
      ignore_seconds_flag = TRUE
    )
  
  # Flag for a valid dose, per the assessment's NOTE:
  # "A valid dose is defined as (EX.EXDOSE > 0) or
  #  (EX.EXDOSE == 0 and EX.EXTRT contains 'PLACEBO')"
  valid_dose_cond <- expr(
    (EXDOSE > 0 | (EXDOSE == 0 & str_detect(EXTRT, "PLACEBO")))
  )
  
  # --- 5. Derive TRTSDTM / TRTSTMF (treatment start datetime) --------------------
  # First exposure record with a valid dose, sorted in date/time order.
  
  adsl <- adsl %>%
    derive_vars_merged(
      dataset_add = ex_ext,
      filter_add = !!valid_dose_cond & !is.na(EXSTDTM),
      new_vars = exprs(TRTSDTM = EXSTDTM, TRTSTMF = EXSTTMF),
      order = exprs(EXSTDTM, EXSEQ),
      mode = "first",
      by_vars = exprs(STUDYID, USUBJID)
    ) %>%
    # --- 5. Derive TRTEDTM / TRTETMF (treatment end datetime) --------------------
  # Needed as an input to the LSTAVLDT derivation (step 8 below).
  derive_vars_merged(
    dataset_add = ex_ext,
    filter_add = !!valid_dose_cond & !is.na(EXENDTM),
    new_vars = exprs(TRTEDTM = EXENDTM, TRTETMF = EXENTMF),
    order = exprs(EXENDTM, EXSEQ),
    mode = "last",
    by_vars = exprs(STUDYID, USUBJID)
  ) %>%
    # Date-only versions, useful for day/window derivations and reporting
    derive_vars_dtm_to_dt(source_vars = exprs(TRTSDTM, TRTEDTM))
  
  
  
  
  # --- 7. Derive ITTFL (Intent-to-Treat flag) ------------------------------------
  # "Y" if DM.ARM is not missing, else "N"
  
  adsl <- adsl %>%
    mutate(
      ITTFL = if_else(!is.na(ARM) & ARM != "", "Y", "N")
    )
  
  # --- 8. Derive LSTAVLDT (last known alive date) --------------------------------
  # Maximum of:
  #  (1) last VS visit date with a valid result (VSSTRESN/VSSTRESC not both
  #      missing) and non-missing VSDTC datepart
  #  (2) last complete AE onset date (AESTDTC datepart)
  #  (3) last complete DS disposition date (DSSTDTC datepart)
  #  (4) last valid-dose treatment date (datepart of ADSL.TRTEDTM, derived above)
  
  adsl <- adsl %>%
    derive_vars_extreme_event(
      by_vars = exprs(STUDYID, USUBJID),
      events = list(
        event(
          dataset_name = "vs",
          condition = !(is.na(VSSTRESN) & is.na(VSSTRESC)) & !is.na(VSDTC),
          order = exprs(convert_dtc_to_dt(VSDTC)),
          set_values_to = exprs(
            LSTAVLDT = convert_dtc_to_dt(VSDTC),
            LALVDOM  = "VS",
            LALVSEQ  = VSSEQ,
            LALVVAR  = "VSDTC"
          )
        ),
        event(
          dataset_name = "ae",
          condition = !is.na(AESTDTC),
          order = exprs(convert_dtc_to_dt(AESTDTC)),
          set_values_to = exprs(
            LSTAVLDT = convert_dtc_to_dt(AESTDTC),
            LALVDOM  = "AE",
            LALVSEQ  = AESEQ,
            LALVVAR  = "AESTDTC"
          )
        ),
        event(
          dataset_name = "ds",
          condition = !is.na(DSSTDTC),
          order = exprs(convert_dtc_to_dt(DSSTDTC)),
          set_values_to = exprs(
            LSTAVLDT = convert_dtc_to_dt(DSSTDTC),
            LALVDOM  = "DS",
            LALVSEQ  = DSSEQ,
            LALVVAR  = "DSSTDTC"
          )
        ),
        event(
          dataset_name = "adsl",
          condition = !is.na(TRTEDTM),
          order = exprs(TRTEDT),
          set_values_to = exprs(
            LSTAVLDT = TRTEDT,
            LALVDOM  = "EX",
            LALVSEQ  = NA_integer_,
            LALVVAR  = "TRTEDTM"
          )
        )
      ),
      source_datasets = list(vs = vs, ae = ae, ds = ds, adsl = adsl),
      order = exprs(LSTAVLDT),
      mode = "last",
      new_vars = exprs(LSTAVLDT)
    )
  
  # --- 9. Additional Variables  -------------------------------------------------------
  
  # 9.1 Derive Disposition Variables
  # Convert character date to numeric date without imputation
  ds_ext <- derive_vars_dt(
    ds,
    dtc = DSSTDTC,
    new_vars_prefix = "DSST"
  )
  
  adsl <- adsl %>%
    derive_vars_merged(
      dataset_add = ds_ext,
      by_vars = exprs(STUDYID, USUBJID),
      new_vars = exprs(EOSDT = DSSTDT),
      filter_add = DSCAT == "DISPOSITION EVENT" & DSDECOD != "SCREEN FAILURE"
    )
  
  format_eosstt <- function(x) {
    case_when(
      x %in% c("COMPLETED") ~ "COMPLETED",
      x %in% c("SCREEN FAILURE") ~ NA_character_,
      TRUE ~ "DISCONTINUED"
    )
  }
  
  adsl <- adsl %>%
    derive_vars_merged(
      dataset_add = ds,
      by_vars = exprs(STUDYID, USUBJID),
      filter_add = DSCAT == "DISPOSITION EVENT",
      new_vars = exprs(EOSSTT = format_eosstt(DSDECOD)),
      missing_values = exprs(EOSSTT = "ONGOING")
    )
  
  # 9.2 Derive Cause of Death
  
  adsl <- adsl %>%
    derive_vars_merged(
      dataset_add = ds_ext,
      by_vars = exprs(STUDYID, USUBJID),
      new_vars = exprs(RANDDT = DSSTDT),
      filter_add = DSDECOD == "RANDOMIZED",
    ) %>%
    derive_vars_merged(
      dataset_add = ds_ext,
      by_vars = exprs(STUDYID, USUBJID),
      new_vars = exprs(SCRFDT = DSSTDT),
      filter_add = DSCAT == "DISPOSITION EVENT" & DSDECOD == "SCREEN FAILURE"
    ) %>%
    derive_vars_merged(
      dataset_add = ds_ext,
      by_vars = exprs(STUDYID, USUBJID),
      new_vars = exprs(FRVDT = DSSTDT),
      filter_add = DSCAT == "OTHER EVENT" & DSDECOD == "FINAL RETRIEVAL VISIT"
    )
  
  adsl <- adsl %>%
    derive_vars_extreme_event(
      by_vars = exprs(STUDYID, USUBJID),
      events = list(
        event(
          dataset_name = "ae",
          condition = AEOUT == "FATAL",
          set_values_to = exprs(DTHCAUS = AEDECOD, DTHDOM = "AE"),
        ),
        event(
          dataset_name = "ds",
          condition = DSDECOD == "DEATH" & grepl("DEATH DUE TO", DSTERM),
          set_values_to = exprs(DTHCAUS = DSTERM, DTHDOM = "DS"),
        )
      ),
      source_datasets = list(ae = ae, ds = ds),
      tmp_event_nr_var = event_nr,
      order = exprs(event_nr),
      mode = "first",
      new_vars = exprs(DTHCAUS, DTHDOM)
    )
  
  # --- 10. Save the dataset -------------------------------------------------------
  
  saveRDS(adsl, file = "question_2_adam/output/adsl.rds")
  
  cat("\nADSL successfully created and saved to ",
      "question_2_adam/output/adsl.rds\n", sep = "")
  
  adsl
  
}, error = function(e) {
  cat("\n*** ERROR ENCOUNTERED ***\n")
  cat(conditionMessage(e), "\n")
  NULL
})

cat("\n=======================================================================\n")
cat("Run finished:", format(Sys.time()), "\n")
if (is.null(result)) {
  cat("STATUS: FAILED - see error message above.\n")
} else {
  cat("STATUS: SUCCESS - program completed without errors.\n")
}
cat("=======================================================================\n")

sink(type = "message")
sink()
close(con)