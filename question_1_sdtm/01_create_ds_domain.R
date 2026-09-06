#===============================================================================
# Program Name   : 01_create_ds_domain.R
# Study          : [Study ID / Protocol Number]
# Purpose        : Create the SDTM Disposition (DS) domain from raw clinical
#                  trial data using {sdtm.oak}.
#
# Input          : pharmaverseraw::ds_raw
#                  study_ct (controlled terminology mapping file)
#
# Output         : ds.rds / ds.csv  (SDTM DS domain dataset)
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
#                  - Based on the AE domain example from Pharmaverse Examples
#
# Revision History:
#   Date        Author            Description
#   ----------  ----------------  --------------------------------------------
#   2026-09-06  Tapender Singh    Initial version
#
#===============================================================================
