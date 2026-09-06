# =============================================================================
# ClinicalTrialDataAgent
# Natural-language -> Structured JSON (LLM) -> Pandas-free R filter -> Result
#
# Context: Posit Cloud / RStudio. reticulate's Python environment does NOT
# have pandas available. Solution: we never touch pandas at all. The `ae`
# SDTM dataset stays a plain R data.frame/tibble the whole time. reticulate
# is used *only* (optionally) to call an LLM SDK (e.g. Python's `openai`
# package) purely for text-in / JSON-text-out -- no dataframes cross the
# R <-> Python boundary, so the missing-pandas problem never bites.
#
# If you'd rather skip Python entirely, there's a native-R (httr) LLM caller
# below too -- pick whichever is available in your environment. A
# deterministic mock is included so the full Prompt -> Parse -> Execute
# pipeline runs with zero external dependencies.
# =============================================================================

# ---- 0. Packages ------------------------------------------------------------
# install.packages(c("dplyr", "jsonlite", "httr"))   # base requirements
# install.packages("reticulate")                      # only if using the Python LLM path
library(dplyr)
library(jsonlite)

# ---- 1. Load the data ---------------------------------------------------
# install.packages("pharmaversesdtm")  # if not already installed
ae <- pharmaversesdtm::ae

# Column names can vary slightly by SDTM standard/version (e.g. AESOC vs
# AEBODSYS). Resolve the "system organ class" column dynamically so the
# rest of the code doesn't hardcode something that might not exist.
soc_col <- intersect(c("AESOC", "AEBODSYS"), names(ae))[1]

# ---- 2. Schema Definition -------------------------------------------------
# This is what gets shown to the LLM so it knows what columns/values exist.
ae_schema <- list(
  USUBJID = "Unique Subject Identifier - identifies a single trial subject.",
  AETERM  = "Reported Term for the Adverse Event, as originally verbatim recorded (e.g. 'HEADACHE', 'NAUSEA').",
  AEDECOD = "Dictionary-Derived Term - the MedDRA-coded preferred term for the event.",
  `AESOC/AEBODSYS` = "Body System or Organ Class (MedDRA SOC) the event is classified under (e.g. 'GASTROINTESTINAL DISORDERS').",
  AESEV   = "Severity/intensity of the adverse event. One of: MILD, MODERATE, SEVERE.",
  AESER   = "Whether the event was Serious. One of: Y, N.",
  AEREL   = "Causality / relationship of the event to study treatment (e.g. RELATED, NOT RELATED).",
  AEOUT   = "Outcome of the adverse event (e.g. RECOVERED/RESOLVED, NOT RECOVERED/NOT RESOLVED, FATAL)."
)

schema_to_prompt_text <- function(schema) {
  paste(
    sprintf("- %s: %s", names(schema), unlist(schema)),
    collapse = "\n"
  )
}

# ---- 3. LLM call implementations -------------------------------------------
# All of these return a *raw JSON string* like:
#   {"target_column": "AESEV", "filter_value": "MODERATE"}

build_prompt <- function(question, schema) {
  sprintf(
    paste(
      "You are a clinical trial data assistant. You have access to an AE",
      "(Adverse Events) SDTM dataset with these columns:\n\n%s\n\n",
      "Given the user's question, identify:",
      "  - target_column: the single most relevant column name from the list above",
      "    (if it's a body system question, use \"%s\")",
      "  - filter_value: the value to filter that column for, extracted from the",
      "    question, in UPPERCASE to match SDTM controlled terminology conventions.\n\n",
      "Respond with ONLY a JSON object, no prose, in this exact shape:",
      "{\"target_column\": \"...\", \"filter_value\": \"...\"}\n\n",
      "Question: %s",
      sep = ""
    ),
    schema_to_prompt_text(schema),
    if (!is.na(soc_col)) soc_col else "AESOC",
    question
  )
}

## 3a. Native-R option (no reticulate needed): direct REST call via httr.
call_llm_httr <- function(question, schema, api_key, model = "gpt-4o-mini") {
  if (!requireNamespace("httr", quietly = TRUE)) stop("httr not installed")
  resp <- httr::POST(
    url = "https://api.openai.com/v1/chat/completions",
    httr::add_headers(Authorization = paste("Bearer", api_key)),
    encode = "json",
    body = list(
      model = model,
      response_format = list(type = "json_object"),
      messages = list(
        list(role = "user", content = build_prompt(question, schema))
      )
    )
  )
  content <- httr::content(resp, as = "parsed", simplifyVector = TRUE)
  content$choices$message$content[[1]]
}

## 3b. reticulate option: call Python's `openai` SDK. Note this ONLY passes
##     strings back and forth -- pandas is never imported or required.
call_llm_reticulate <- function(question, schema, api_key, model = "gpt-4o-mini") {
  reticulate::py_run_string(sprintf("
from openai import OpenAI
_client = OpenAI(api_key=%s)
_resp = _client.chat.completions.create(
    model=%s,
    response_format={'type': 'json_object'},
    messages=[{'role': 'user', 'content': %s}]
)
_llm_json_result = _resp.choices[0].message.content
",
    jsonlite::toJSON(api_key), jsonlite::toJSON(model),
    jsonlite::toJSON(build_prompt(question, schema))
  ))
  reticulate::py$`_llm_json_result`
}

## 3c. Mock option: deterministic keyword-based stand-in for the LLM, so the
##     full pipeline is demonstrably complete without any API key/network.
call_llm_mock <- function(question, schema) {
  q <- toupper(question)

  severities <- c("MILD", "MODERATE", "SEVERE")
  hit_sev <- severities[sapply(severities, function(s) grepl(s, q))]

  socs <- toupper(unique(ae[[soc_col]]))
  hit_soc <- socs[sapply(socs, function(s) grepl(s, q, fixed = TRUE))]

  terms <- toupper(unique(ae$AETERM))
  hit_term <- terms[sapply(terms, function(t) grepl(t, q, fixed = TRUE))]

  if (length(hit_sev) > 0) {
    result <- list(target_column = "AESEV", filter_value = hit_sev[1])
  } else if (length(hit_soc) > 0) {
    result <- list(target_column = soc_col, filter_value = hit_soc[1])
  } else if (length(hit_term) > 0) {
    result <- list(target_column = "AETERM", filter_value = hit_term[1])
  } else {
    # Fallback: assume it's an AETERM-style free-text lookup on the last
    # capitalized word-ish token in the question.
    result <- list(target_column = "AETERM", filter_value = toupper(tail(strsplit(question, " ")[[1]], 1)))
  }
  jsonlite::toJSON(result, auto_unbox = TRUE)
}

# ---- 4. Execution: apply the parsed filter to the `ae` data.frame ---------
execute_query <- function(ae_data, parsed) {
  col <- parsed$target_column
  val <- parsed$filter_value

  if (!col %in% names(ae_data)) {
    stop(sprintf("target_column '%s' not found in ae dataset.", col))
  }

  matched <- ae_data %>%
    filter(toupper(.data[[col]]) == toupper(val))

  subjects <- sort(unique(matched$USUBJID))

  list(
    target_column = col,
    filter_value  = val,
    n_subjects    = length(subjects),
    subjects      = subjects
  )
}

# ---- 5. The Agent -----------------------------------------------------------
# Constructor. mode = "mock" | "httr" | "reticulate"
ClinicalTrialDataAgent <- function(ae_data, schema, mode = "mock",
                                    api_key = NULL, model = "gpt-4o-mini") {
  structure(
    list(
      ae_data = ae_data,
      schema  = schema,
      mode    = mode,
      api_key = api_key,
      model   = model
    ),
    class = "ClinicalTrialDataAgent"
  )
}

# Step 1+2: Prompt -> Parse (returns an R list with target_column/filter_value)
parse_question <- function(agent, question) {
  raw_json <- switch(
    agent$mode,
    mock       = call_llm_mock(question, agent$schema),
    httr       = call_llm_httr(question, agent$schema, agent$api_key, agent$model),
    reticulate = call_llm_reticulate(question, agent$schema, agent$api_key, agent$model),
    stop("Unknown mode: ", agent$mode)
  )
  jsonlite::fromJSON(raw_json)
}

# Full pipeline: Prompt -> Parse -> Execute
ask <- function(agent, question) {
  parsed <- parse_question(agent, question)
  result <- execute_query(agent$ae_data, parsed)
  result$question <- question
  result
}

# =============================================================================
# TEST SCRIPT — 3 example queries
# =============================================================================
agent <- ClinicalTrialDataAgent(ae, ae_schema, mode = "mock")
# To use a real LLM instead, e.g.:
#   agent <- ClinicalTrialDataAgent(ae, ae_schema, mode = "httr", api_key = Sys.getenv("OPENAI_API_KEY"))
#   agent <- ClinicalTrialDataAgent(ae, ae_schema, mode = "reticulate", api_key = Sys.getenv("OPENAI_API_KEY"))

queries <- c(
  "Give me the subjects who had Adverse events of Moderate severity.",
  "Which subjects experienced a HEADACHE adverse event?",
  paste0("List subjects with adverse events in the ",
         if (!is.na(soc_col)) ae[[soc_col]][1] else "GASTROINTESTINAL DISORDERS",
         " system organ class.")
)

for (q in queries) {
  res <- ask(agent, q)
  cat("\n================================================================\n")
  cat("Question      :", res$question, "\n")
  cat("Parsed filter :", res$target_column, "==", res$filter_value, "\n")
  cat("Subject count :", res$n_subjects, "\n")
  cat("Subject IDs   :", paste(head(res$subjects, 10), collapse = ", "),
      if (res$n_subjects > 10) "... (truncated)" else "", "\n")
}
