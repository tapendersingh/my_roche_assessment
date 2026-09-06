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
# R Version      : R 4.2.0+
# Packages Used  : gtsummary, dplyr, tidyr, gt
#
# Notes          : - Reference: FDA TLG Catalogue, Table 10
#                  - Total column reflects all subjects in pharmaverseadam::adsl
#
# Revision History:
#   Date        Author            Description
#   ----------  ----------------  --------------------------------------------
#   2026-09-06  Tapender Singh    Initial version
#
#===============================================================================
