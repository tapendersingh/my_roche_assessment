#===============================================================================
# Program Name   : 01_create_ds_domain.R
# Study          : [Study ID / Protocol Number]
# Purpose        : Create the SDTM Disposition (DS) domain from raw clinical
#                  trial data using {sdtm.oak}.
#
# Input          : pharmaverseraw::ds_raw
#                  study_ct (controlled terminology mapping file)
#                  pharmaversesdtm::dm (used only to obtain RFSTDTC as the
#                                       reference start date for DSSTDY)
#
# Output         : question_1_sdtm/output/ds_domain.rds  (SDTM DS domain)
#                  Variables: STUDYID, DOMAIN, USUBJID, DSSEQ, DSTERM,
#                             DSDECOD, DSCAT, VISITNUM, VISIT, DSDTC,
#                             DSSTDTC, DSSTDY
#
# Author         : Tapender Singh
# Date Created   : 2026-09-06
# Last Modified  : 2026-09-06
#
# R Version      : R 4.2.0+
# Packages Used  : sdtm.oak, dplyr, tidyr
#
# Notes          : - Follows CDISC SDTMIG v3.4 DS domain specifications
#                  - Modeled on the AE (Events class) example from the
#                    Pharmaverse Examples site, applying the same
#                    oak_id_vars / assign_ct / assign_no_ct pattern to DS
#
# Revision History:
#   Date        Author            Description
#   ----------  ----------------  --------------------------------------------
#   2026-09-06  Tapender Singh    Initial version
#
#===============================================================================

# --- 0. Setup -----------------------------------------------------------------

library(sdtm.oak)
library(pharmaverseraw)
library(pharmaversesdtm)
library(admiral)
library(dplyr)
library(tidyr)

# Create output/log folders relative to this script's folder if run from repo root
dir.create("question_1_sdtm/output", recursive = TRUE, showWarnings = FALSE)
dir.create("question_1_sdtm/log", recursive = TRUE, showWarnings = FALSE)

log_file <- "question_1_sdtm/log/01_create_ds_domain.log"

# Start capturing console output (messages + printed output) to the log file
con <- file(log_file, open = "wt")
sink(con, split = TRUE)                 # split = TRUE also prints to console
sink(con, type = "message", append = TRUE)

cat("=======================================================================\n")
cat("Log for 01_create_ds_domain.R\n")
cat("Run started:", format(Sys.time()), "\n")
cat("=======================================================================\n\n")

# Wrap the whole program in tryCatch so any error is captured in the log
# before the sinks are closed (avoids losing the log if something breaks).
result <- tryCatch({
  
  # --- 1. Read raw data and controlled terminology ---------------------------
  
  ds_raw <- pharmaverseraw::ds_raw
  dm     <- pharmaversesdtm::dm   # used only for RFSTDTC (DSSTDY reference date)
  sv     <- pharmaversesdtm::sv

  study_ct <- read.csv("ct/sdtm_ct.csv") # read controlled terminology
  
  # --- 2. Derive oak_id_vars ---------------------------------------------------
  # oak_id, raw_source, patient_number: the linkage keys used by sdtm.oak to
  # merge each derived variable back together into one target domain.
  
  ds_raw <- ds_raw %>%
    mutate(INSTANCE_UP = toupper(INSTANCE)) %>%
    generate_oak_id_vars(
      pat_var = "PATNUM",
      raw_src = "ds_raw"
    )
  
  # --- 3. Map the topic variable (DSTERM) -------------------------------------
  # DSTERM is the verbatim disposition term as collected on the eCRF.
  # No controlled terminology restriction on the verbatim term itself.
  
  ds <- assign_no_ct(
    raw_dat = ds_raw,
    raw_var = "OTHERSP",
    tgt_var = "DSTERM",
    id_vars = oak_id_vars()
  ) %>%
  assign_no_ct(
      raw_dat = ds_raw,
      raw_var = "IT.DSTERM",
      tgt_var = "DSTERM",
      id_vars = oak_id_vars()
  ) %>%
    # --- 4. Map DSDECOD using the study_ct codelist (C66727 / NCOMPLT) -------
  assign_no_ct(
    raw_dat = ds_raw,
    raw_var = "OTHERSP",
    tgt_var = "DSDECOD",
    id_vars = oak_id_vars()
  ) %>%
  assign_ct(
    raw_dat = ds_raw,
    raw_var = "IT.DSDECOD",
    tgt_var = "DSDECOD",
    ct_spec = study_ct,
    ct_clst = "C66727",
    id_vars = oak_id_vars()
  ) %>%
    # --- 5. Hardcode DSCAT ----------------------------------------------------
  hardcode_no_ct(
    raw_dat = condition_add(ds_raw, !is.na(OTHERSP)),
    raw_var = "OTHERSP",
    tgt_var = "DSCAT",
    tgt_val = "OTHER EVENT",
    id_vars = oak_id_vars()
  ) %>%
  hardcode_no_ct(
    raw_dat = condition_add(ds_raw, is.na(OTHERSP) & IT.DSDECOD != "Randomized"),
    raw_var = "IT.DSDECOD",
    tgt_var = "DSCAT",
    tgt_val = "DISPOSITION EVENT",
    id_vars = oak_id_vars()
  ) %>%
  hardcode_no_ct(
    raw_dat = condition_add(ds_raw, is.na(OTHERSP) & IT.DSDECOD == "Randomized"),
    raw_var = "IT.DSDECOD",
    tgt_var = "DSCAT",
    tgt_val = "PROTOCOL MILESTONE",
    id_vars = oak_id_vars()
  ) %>%
    # --- 6. Map VISIT  ----------------------------------------------
  assign_no_ct(
    raw_dat = ds_raw,
    raw_var = "INSTANCE_UP",
    tgt_var = "VISIT",
    id_vars = oak_id_vars()
  ) %>%
    # --- 7. Map DSDTC (date of collection, ISO 8601) --------------------------
  assign_datetime(
    raw_dat = ds_raw,
    raw_var = c("DSDTCOL","DSTMCOL"),
    tgt_var = "DSDTC",
    raw_fmt = c("m-d-y","H:M"),
    id_vars = oak_id_vars()
  ) %>%
    # --- 8. Map DSSTDTC (start date of disposition event) ---------------------
  assign_datetime(
    raw_dat = ds_raw,
    raw_var = c("IT.DSSTDAT"),
    tgt_var = "DSSTDTC",
    raw_fmt = "m-d-y",
    id_vars = oak_id_vars()
  )
  
  # --- 9. Add STUDYID, DOMAIN, USUBJID ----------------------------------------
  
  ds <- ds %>%
    mutate(
      STUDYID = ds_raw$STUDY[match(patient_number, ds_raw$patient_number)],
      DOMAIN  = "DS",
      USUBJID = paste("01", patient_number, sep = "-")
    )
  
  # --- 10. Derive DSSEQ (sequence number within USUBJID) ----------------------
  
  ds <- ds %>%
    derive_seq(
      tgt_var = "DSSEQ",
      rec_vars = c("USUBJID","DSSTDTC")
    )
  
  # --- 11. Derive DSSTDY (study day relative to RFSTDTC from DM) --------------
  
  ds <- ds %>%
    derive_study_day(dm, "DSSTDTC", "RFSTDTC", "DSSTDY")
  
  # --- 12. Derive VISITNUM  ---------------------------------------------------
  
  ds <- ds %>%
    left_join(
      sv |> 
        select(USUBJID, VISIT, VISITNUM) |> 
        distinct(USUBJID, VISIT, VISITNUM),
      by = c("USUBJID","VISIT")
    )
  
  # --- 13. Finalize variable order and drop helper columns --------------------
  
  ds_domain <- ds %>%
    select(
      STUDYID, DOMAIN, USUBJID, DSSEQ, DSTERM, DSDECOD, DSCAT,
      VISITNUM, VISIT, DSDTC, DSSTDTC, DSSTDY
    ) %>%
    arrange(USUBJID, DSSEQ)
  
  # --- 14. Save the dataset ----------------------------------------------------
  
  saveRDS(ds_domain, file = "question_1_sdtm/output/ds_domain.rds")
  
  cat("\nDS domain successfully created and saved to ",
      "question_1_sdtm/output/ds_domain.rds\n", sep = "")
  
  ds_domain
  
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

# Stop redirecting output/messages back to the console
sink(type = "message")
sink()
close(con)

