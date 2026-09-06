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
# Output         : adsl.rds / adsl.csv  (ADaM ADSL dataset)
#                  Derived variables include:
#                    - AGEGR9 / AGEGR9N : Age group ("<18","18-50",">50") and
#                                         numeric equivalent (1,2,3)
#                    - TRTSDTM / TRTSTMF: Treatment start datetime (first valid
#                                         dose, EX.EXSTDTC) with partial time
#                                         imputation (seconds only -> no flag)
#                    - ITTFL            : "Y"/"N" based on DM.ARM populated
#                    - LSTAVLDT         : Last known alive date across
#                                         VS/AE/DS/EX records
#
# Author         : Tapender Singh
# Date Created   : 2026-09-06
# Last Modified  : 2026-09-06
#
# R Version      : R 4.2.0+
# Packages Used  : admiral, dplyr, tidyr, lubridate
#
# Notes          : - DM domain used as ADSL base per {admiral} ADSL vignette
#                  - Valid dose defined as EX.EXDOSE > 0, or EX.EXDOSE == 0 AND
#                    EX.EXTRT contains "PLACEBO"
#                  - Derivations follow {admiral} functions where possible
#
# Revision History:
#   Date        Author            Description
#   ----------  ----------------  --------------------------------------------
#   2026-09-06  Tapender Singh    Initial version
#
#===============================================================================
