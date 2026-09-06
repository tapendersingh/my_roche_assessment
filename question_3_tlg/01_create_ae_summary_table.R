#===============================================================================
# Program Name   : 01_create_ae_summary_table.R
# Study          : [Study ID / Protocol Number]
# Purpose        : Create a summary table of Treatment-Emergent Adverse Events
#                  (TEAEs) by treatment group using {gtsummary}, in line with
#                  FDA Table 10 style regulatory AE reporting.
#
# Input          : pharmaverseadam::adae
#                  pharmaverseadam::adsl
#
# Output         : ae_summary_table.html (or .docx/.pdf)
#                  Table structure:
#                    - Rows    : AETERM (nested under AESOC)
#                    - Columns : Treatment groups (ACTARM), plus Total column
#                    - Cells   : Count (n) and percentage (%)
#                    - Filter  : TRTEMFL == "Y"
#                    - Sort    : Descending frequency
#
# Author         : Tapender Singh
# Date Created   : 2026-09-06
# Last Modified  : 2026-09-06
#
# R Version      : R 4.5.3
# Packages Used  : gtsummary, dplyr, tidyr, gt
#
# Notes          : - Reference: FDA TLG Catalogue, Table 10
#                  - Total column reflects all subjects in pharmaverseadam::adsl
#                    (via gtsummary::add_overall())
#                  - AESOC and AETERM are re-ordered (most frequent first)
#                    using forcats::fct_infreq() before the table is built,
#                    since {gtsummary}/tbl_hierarchical() preserve the row
#                    order implied by factor level order

#
# Revision History:
#   Date        Author            Description
#   ----------  ----------------  --------------------------------------------
#   2026-09-06  Tapender Singh    Initial version
#
#===============================================================================


# --- 0. Setup -----------------------------------------------------------------

library(gtsummary)
library(pharmaverseadam)
library(dplyr)
library(tidyr)
library(gt)

dir.create("question_3_tlg/output", recursive = TRUE, showWarnings = FALSE)
dir.create("question_3_tlg/log", recursive = TRUE, showWarnings = FALSE)

log_file <- "question_3_tlg/log/01_create_ae_summary_table.log"

con <- file(log_file, open = "wt")
sink(con, split = TRUE)
sink(con, type = "message", append = TRUE)

cat("=======================================================================\n")
cat("Log for 01_create_ae_summary_table.R\n")
cat("Run started:", format(Sys.time()), "\n")
cat("=======================================================================\n\n")

result <- tryCatch({
  
  # --- 1. Read source ADaM data ------------------------------------------------
  
  adae <- pharmaverseadam::adae
  adsl <- pharmaverseadam::adsl
  
  # --- 2. Filter to Treatment-Emergent AEs only --------------------------------
  
  adae_teae <- adae %>%
    filter(TRTEMFL == "Y")
  
  cat("Number of TEAE records:", nrow(adae_teae), "\n")
  cat("Number of unique subjects with a TEAE:",
      n_distinct(adae_teae$USUBJID), "\n\n")
  
  # --- 3. Order AESOC and AETERM by descending frequency -----------------------
  # fct_infreq() reorders factor levels by descending count of occurrences;
  # tbl_hierarchical() then renders rows/nesting in that same order.
  
  # adae_teae <- adae_teae %>%
  #   mutate(
  #     AESOC  = fct_infreq(AESOC),
  #     AETERM = fct_infreq(AETERM)
  #   )
  
  aeterm_order <- adae_teae %>%
    distinct(USUBJID, AETERM) %>%
    count(AETERM, sort = TRUE) %>%
    pull(AETERM)
  
  aesoc_order <- adae_teae %>%
    distinct(USUBJID, AESOC) %>%
    count(AESOC, sort = TRUE) %>%
    pull(AESOC)
  
  adae_teae <- adae_teae %>%
    mutate(
      AESOC  = factor(AESOC, levels = aesoc_order),
      AETERM = factor(AETERM, levels = aeterm_order)
    )
  
  # --- 4. Build the TEAE summary table using {gtsummary}::tbl_hierarchical() ----
  # - variables = c(AESOC, AETERM): SOC/PT nesting hierarchy
  # - by = ACTARM: one column per treatment arm
  # - denominator = adsl: uses ADSL for the "N=" subject counts per arm
  # - id = USUBJID: rate calculated as unique subjects with the event
  # - overall_row = TRUE: adds an "Any TEAE" / "Treatment Emergent AEs" summary
  #   row at the top, matching the assessment's sample output
  
  ae_summary_tbl <- tbl_hierarchical(
    data          = adae_teae,
    variables     = c(AESOC, AETERM),
    by            = ACTARM,
    denominator   = adsl,
    id            = USUBJID,
    statistic     = everything() ~ "{n} ({p}%)",
    overall_row   = TRUE,
    label         = list(
      AESOC  = "Primary System Organ Class",
      AETERM = "Reported Term for the Adverse Event",
      ..ard_hierarchical_overall.. = "Treatment Emergent AEs"
    )
  ) %>%
    # --- 5. Add a Total column across all subjects -----------------------------
  add_overall(last = TRUE, col_label = "**Total**  \nN = {N}") %>%
    modify_header(label ~ "**Primary System Organ Class**  \n**Reported Term for the Adverse Event**") %>%
    bold_labels()
  
  cat("\nAE summary table object created (gtsummary tbl_hierarchical).\n")
  
  # --- 6. Convert to {gt} and save as HTML --------------------------------------
  
  ae_summary_gt <- ae_summary_tbl %>%
    as_gt()
  
  gtsave(
    ae_summary_gt,
    filename = "question_3_tlg/output/ae_summary_table.html"
  )
  
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

