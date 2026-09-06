#===============================================================================
# Program Name   : 02_create_visualizations.R
# Study          : [Study ID / Protocol Number]
# Purpose        : Create AE visualizations using {ggplot2} to support the
#                  adverse events summary reporting: AE severity distribution
#                  by treatment, and top 10 most frequent AEs with 95% CIs.
#
# Input          : pharmaverseadam::adae
#                  pharmaverseadam::adsl
#
# Output         : question_3_tlg/output/ae_severity_by_treatment.png
#                    - Stacked bar chart of AE severity (AESEV: MILD/MODERATE/
#                      SEVERE) by treatment arm (ACTARM)
#                  question_3_tlg/output/top10_ae_incidence.png
#                    - Top 10 most frequent AEs (AETERM) with 95% Clopper-
#                      Pearson confidence intervals for incidence rates
#
# Author         : Tapender Singh
# Date Created   : 2026-09-06
# Last Modified  : 2026-09-06
#
# R Version      : R 4.2.0+
# Packages Used  : ggplot2, dplyr, tidyr, forcats, binom
#
# Notes          : - Reference: FDA TLG Catalogue (pharmaverse cardinal)
#                  - Denominator (N) for incidence % based on unique subjects
#                    in pharmaverseadam::adsl (all randomized/treated subjects)
#                  - Plot 2 uses distinct-subject incidence (one count per
#                    USUBJID per AETERM), not raw AE record counts, so a
#                    subject with a recurring event is only counted once
#                  - 95% CIs computed via the Clopper-Pearson ("exact")
#                    method using {binom}::binom.confint()
#                  - Both plots exported as PNG per assessment requirements
#
# Revision History:
#   Date        Author            Description
#   ----------  ----------------  --------------------------------------------
#   2026-09-06  Tapender Singh    Initial version
#
#===============================================================================

# --- 0. Setup -----------------------------------------------------------------

library(ggplot2)
library(pharmaverseadam)
library(dplyr)
library(tidyr)
library(forcats)
library(binom)

dir.create("question_3_tlg/output", recursive = TRUE, showWarnings = FALSE)
dir.create("question_3_tlg/log", recursive = TRUE, showWarnings = FALSE)

log_file <- "question_3_tlg/log/02_create_visualizations.log"

con <- file(log_file, open = "wt")
sink(con, split = TRUE)
sink(con, type = "message", append = TRUE)

cat("=======================================================================\n")
cat("Log for 02_create_visualizations.R\n")
cat("Run started:", format(Sys.time()), "\n")
cat("=======================================================================\n\n")

result <- tryCatch({
  
  # --- 1. Read source ADaM data ------------------------------------------------
  
  adae <- pharmaverseadam::adae
  adsl <- pharmaverseadam::adsl
  
  # Filter to Treatment-Emergent AEs only, consistent with the summary table
  adae_teae <- adae %>%
    filter(TRTEMFL == "Y")
  
  cat("Number of TEAE records used for plots:", nrow(adae_teae), "\n\n")
  
  # Total N per treatment arm, from ADSL (denominator for Plot 1 context /
  # overall incidence in Plot 2)
  n_total <- n_distinct(adsl$USUBJID)
  cat("Total number of subjects (ADSL):", n_total, "\n\n")
  
  # =============================================================================
  # PLOT 1: AE severity distribution by treatment (stacked bar chart)
  # =============================================================================
  
  # One record per subject/AE for severity counting (AESEV should already be
  # collected per AE record; no de-duplication is applied here since each row
  # in adae_teae represents one adverse event occurrence with its own severity)
  ae_severity <- adae_teae %>%
    mutate(
      AESEV = factor(AESEV, levels = c("MILD", "MODERATE", "SEVERE"))
    ) %>%
    count(ACTARM, AESEV, name = "n_events")
  
  cat("AE counts by treatment arm and severity:\n")
  print(ae_severity)
  cat("\n")
  
  plot1 <- ggplot(
    ae_severity,
    aes(x = ACTARM, y = n_events, fill = AESEV)
  ) +
    geom_col(position = "stack", color = "white", linewidth = 0.2) +
    scale_fill_manual(
      values = c(
        "MILD"     = "#F4A6A0",
        "MODERATE" = "#4CAF50",
        "SEVERE"   = "#2E6FDB"
      ),
      name = "Severity/Intensity"
    ) +
    labs(
      title = "AE severity distribution by treatment",
      x = "Treatment Arm",
      y = "Count of AEs"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title   = element_text(face = "bold"),
      panel.grid.major.x = element_blank(),
      legend.position = "right"
    )
  
  ggsave(
    filename = "question_3_tlg/output/ae_severity_by_treatment.png",
    plot     = plot1,
    width    = 8,
    height   = 6,
    dpi      = 300,
    bg       = "white"
  )
  
  cat("Plot 1 (AE severity by treatment) saved to ",
      "question_3_tlg/output/ae_severity_by_treatment.png\n\n", sep = "")
  
  # =============================================================================
  # PLOT 2: Top 10 most frequent AEs with 95% CI for incidence rates
  # =============================================================================
  
  # Incidence is based on the number of DISTINCT subjects reporting each
  # AETERM at least once (not raw AE record counts), out of the total number
  # of subjects in ADSL.
  ae_subject_counts <- adae_teae %>%
    distinct(USUBJID, AETERM) %>%
    count(AETERM, name = "n_subjects") %>%
    arrange(desc(n_subjects)) %>%
    slice_head(n = 10)
  
  cat("Top 10 most frequent AEs (by distinct subject count):\n")
  print(ae_subject_counts)
  cat("\n")
  
  # Compute 95% Clopper-Pearson ("exact") confidence intervals for each
  # AE's incidence proportion, using the total ADSL subject count as n.
  ae_ci <- ae_subject_counts %>%
    rowwise() %>%
    mutate(
      ci = list(binom.confint(
        x = n_subjects,
        n = n_total,
        conf.level = 0.95,
        methods = "exact"
      ))
    ) %>%
    unnest(ci) %>%
    ungroup() %>%
    mutate(
      pct    = mean * 100,
      lower  = lower * 100,
      upper  = upper * 100,
      AETERM = fct_reorder(AETERM, pct)   # ascending for coord_flip, highest at top
    )
  
  cat("AE incidence with 95% Clopper-Pearson CIs:\n")
  print(ae_ci %>% select(AETERM, n_subjects, pct, lower, upper))
  cat("\n")
  
  plot2 <- ggplot(ae_ci, aes(x = pct, y = AETERM)) +
    geom_errorbarh(
      aes(xmin = lower, xmax = upper),
      height = 0.2,
      color  = "black"
    ) +
    geom_point(size = 3, color = "black") +
    scale_x_continuous(
      labels = function(x) paste0(x, "%"),
      limits = c(0, max(ae_ci$upper) * 1.1)
    ) +
    labs(
      title    = "Top 10 Most Frequent Adverse Events",
      subtitle = paste0("n = ", n_total, " subjects; 95% Clopper-Pearson CIs"),
      x        = "Percentage of Patients (%)",
      y        = NULL
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title    = element_text(face = "bold"),
      plot.subtitle = element_text(color = "grey40"),
      panel.grid.minor = element_blank()
    )
  
  ggsave(
    filename = "question_3_tlg/output/top10_ae_incidence.png",
    plot     = plot2,
    width    = 9,
    height   = 6,
    dpi      = 300,
    bg       = "white"
  )
  
  cat("Plot 2 (Top 10 AE incidence with 95% CI) saved to ",
      "question_3_tlg/output/top10_ae_incidence.png\n", sep = "")
  
  list(plot1 = plot1, plot2 = plot2)
  
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