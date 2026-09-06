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
# Output         : ae_severity_by_treatment.png
#                    - Stacked bar chart of AE severity (AESEV: MILD/MODERATE/
#                      SEVERE) by treatment arm (ACTARM)
#                  top10_ae_incidence.png
#                    - Top 10 most frequent AEs (AETERM) with 95% Clopper-
#                      Pearson confidence intervals for incidence rates
#
# Author         : Tapender Singh
# Date Created   : 2026-09-06
# Last Modified  : 2026-09-06
#
# R Version      : R 4.2.0+
# Packages Used  : ggplot2, dplyr, tidyr, binom (for Clopper-Pearson CIs)
#
# Notes          : - Reference: FDA TLG Catalogue (pharmaverse cardinal)
#                  - Denominator (N) for incidence % based on unique subjects
#                    in pharmaverseadam::adsl
#                  - Both plots exported as PNG per assessment requirements
#
# Revision History:
#   Date        Author            Description
#   ----------  ----------------  --------------------------------------------
#   2026-09-06  Tapender Singh    Initial version
#
#===============================================================================
