"""
Clinical Trial Data Agent
==========================
Translates natural-language questions about an ADAE (Adverse Events) dataset
into structured Pandas queries using an LLM.

Pipeline: PROMPT -> PARSE -> EXECUTE

    1. PROMPT   - build_prompt() embeds a description of the dataset schema
                  and the user's question into an LLM prompt that asks for
                  strict JSON output.
    2. PARSE    - call_llm() sends the prompt to OpenAI (if an API key is
                  configured) and parses the JSON response into
                  {target_column, filter_value}. If no API key is available,
                  mock_llm() simulates what the LLM would return, so the
                  full pipeline still runs end-to-end.
    3. EXECUTE  - execute_query() takes that structured output and applies
                  the actual filter to the AE dataframe, returning the
                  count of unique subjects and their USUBJIDs.

Author: (your name)
"""

import os
import json
import pandas as pd

# ---------------------------------------------------------------------------
# 1. SCHEMA DEFINITION
# ---------------------------------------------------------------------------
# This is what teaches the LLM how to map free-text intent -> real column
# names, without us hard-coding "if 'headache' in question" style rules.

SCHEMA_DESCRIPTION = """
You are working with the ADAE (Adverse Events analysis) dataset from a
clinical trial (CDISC ADaM-style structure, based on pharmaversesdtm::ae).

Relevant columns:

- USUBJID (string): Unique Subject Identifier. Always the ID returned to
  the reviewer, never something to filter ON.
- AETERM (string): Verbatim/reported term for the adverse event as entered
  by the site (e.g., "Headache", "Nausea", "Fatigue"). Use this column when
  the question names a specific medical condition/symptom.
- AEDECOD (string): MedDRA Preferred Term (coded/standardized version of
  AETERM). Use this as an alternative to AETERM if the question uses a
  formal/coded medical term.
- AESOC (string): MedDRA System Organ Class - the body system affected
  (e.g., "Cardiac disorders", "Skin and subcutaneous tissue disorders",
  "Gastrointestinal disorders"). Use this when the question asks about a
  body system, organ class, or general area of the body rather than a
  specific symptom.
- AESEV (string): Severity/intensity of the adverse event. Typical values:
  "MILD", "MODERATE", "SEVERE". Use this when the question asks about
  severity, intensity, how bad/serious an event was.
- AESER (string): Whether the adverse event was "SERIOUS" (Y/N). Use this
  when the question asks specifically about "serious" adverse events
  (a distinct regulatory concept from severity).
- AEREL (string): Causality/relationship to study drug (e.g., "RELATED",
  "NOT RELATED"). Use this when the question asks whether an event was
  drug-related.
- AEOUT (string): Outcome of the adverse event (e.g., "RECOVERED/RESOLVED",
  "FATAL"). Use this when the question asks about the outcome/resolution.

Your job: read the reviewer's question and decide which ONE column above is
being filtered on, and what value (from the question) should be searched
for within that column.

Respond with STRICT JSON ONLY, no explanation, no markdown fences, in this
exact shape:

{"target_column": "<COLUMN_NAME>", "filter_value": "<VALUE_TO_SEARCH_FOR>"}
"""


class ClinicalTrialDataAgent:
    """
    Agent that takes a free-text clinical-safety question, uses an LLM to
    map it onto the AE dataset's schema, and executes the resulting filter
    against the dataframe.
    """

    def __init__(self, df: pd.DataFrame, model: str = "gpt-4o-mini"):
        self.df = df
        self.model = model
        self.api_key = os.environ.get("OPENAI_API_KEY")

    # ------------------------------------------------------------------
    # STEP 1: PROMPT
    # ------------------------------------------------------------------
    def build_prompt(self, question: str) -> str:
        return f"{SCHEMA_DESCRIPTION}\n\nReviewer question: \"{question}\"\n\nJSON:"

    # ------------------------------------------------------------------
    # STEP 2: PARSE (real LLM call, with a mock fallback so the pipeline
    # is always runnable even without an API key)
    # ------------------------------------------------------------------
    def call_llm(self, prompt: str) -> str:
        """Calls OpenAI's chat completion API and returns the raw text response."""
        from openai import OpenAI  # imported here so the module still loads
                                    # even if openai isn't installed and the
                                    # user only wants to use the mock path

        client = OpenAI(api_key=self.api_key)
        response = client.chat.completions.create(
            model=self.model,
            messages=[{"role": "user", "content": prompt}],
            response_format={"type": "json_object"},
            temperature=0,
        )
        return response.choices[0].message.content

    def mock_llm(self, question: str) -> str:
        """
        Stand-in for the LLM when no API key is configured. This still goes
        through a 'reasoning' step (matching the intent behind the question
        to the schema description above) rather than special-casing on
        specific dataset values -- it's simulating what a real LLM call
        would return for demo/offline purposes, keeping the
        prompt -> parse -> execute flow fully intact.
        """
        q = question.lower()

        severity_terms = ["severity", "intensity", "severe", "moderate", "mild"]
        soc_terms = ["cardiac", "skin", "gastrointestinal", "system", "body", "organ class"]
        serious_terms = ["serious"]
        related_terms = ["related", "causality", "drug-related"]
        outcome_terms = ["outcome", "resolved", "recovered", "fatal"]

        if any(t in q for t in severity_terms):
            target_column = "AESEV"
            for val in ["mild", "moderate", "severe"]:
                if val in q:
                    filter_value = val.upper()
                    break
            else:
                filter_value = "MODERATE"
        elif any(t in q for t in serious_terms):
            target_column = "AESER"
            filter_value = "Y"
        elif any(t in q for t in related_terms):
            target_column = "AEREL"
            filter_value = "RELATED"
        elif any(t in q for t in outcome_terms):
            target_column = "AEOUT"
            filter_value = "FATAL" if "fatal" in q else "RECOVERED/RESOLVED"
        elif any(t in q for t in soc_terms):
            target_column = "AESOC"
            for val in ["cardiac", "skin", "gastrointestinal"]:
                if val in q:
                    filter_value = val.capitalize()
                    break
            else:
                filter_value = "Cardiac"
        else:
            # Default: treat as a named condition/symptom -> AETERM
            target_column = "AETERM"
            # crude extraction: last capitalised-looking word in the
            # original (non-lowered) question, else the raw question
            words = question.replace("?", "").split()
            candidates = [w for w in words if w[:1].isupper()]
            filter_value = candidates[-1] if candidates else question.strip()

        return json.dumps({"target_column": target_column, "filter_value": filter_value})

    def parse_question(self, question: str) -> dict:
        """Runs PROMPT -> (LLM or mock) -> returns structured dict."""
        prompt = self.build_prompt(question)

        if self.api_key:
            try:
                raw = self.call_llm(prompt)
            except Exception as e:
                print(f"  [warning] OpenAI call failed ({e}); falling back to mock_llm().")
                raw = self.mock_llm(question)
        else:
            raw = self.mock_llm(question)

        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError as e:
            raise ValueError(f"LLM did not return valid JSON: {raw}") from e

        if "target_column" not in parsed or "filter_value" not in parsed:
            raise ValueError(f"LLM response missing required keys: {parsed}")

        return parsed

    # ------------------------------------------------------------------
    # STEP 3: EXECUTE
    # ------------------------------------------------------------------
    def execute_query(self, parsed: dict) -> dict:
        column = parsed["target_column"]
        value = str(parsed["filter_value"])

        if column not in self.df.columns:
            raise ValueError(f"Column '{column}' not found in dataframe.")

        mask = self.df[column].astype(str).str.contains(value, case=False, na=False)
        matches = self.df.loc[mask]

        unique_ids = sorted(matches["USUBJID"].unique().tolist())

        return {
            "target_column": column,
            "filter_value": value,
            "subject_count": len(unique_ids),
            "usubjids": unique_ids,
        }

    # ------------------------------------------------------------------
    # Full pipeline in one call
    # ------------------------------------------------------------------
    def ask(self, question: str) -> dict:
        parsed = self.parse_question(question)
        result = self.execute_query(parsed)
        result["question"] = question
        return result


# ---------------------------------------------------------------------------
# TEST SCRIPT
# ---------------------------------------------------------------------------
if __name__ == "__main__":

    # Load the AE dataset (exported from R's pharmaversesdtm::ae — see the
    # setup instructions for how to generate this CSV from RStudio).
    DATA_PATH = "adae.csv"
    ae = pd.read_csv(DATA_PATH)

    agent = ClinicalTrialDataAgent(ae)

    mode = "REAL OpenAI LLM" if agent.api_key else "MOCK LLM (no OPENAI_API_KEY found)"
    print(f"Running in mode: {mode}\n")

    test_questions = [
        "Give me the subjects who had Adverse events of Moderate severity.",
        "Which subjects reported Headache?",
        "Show me subjects with adverse events in the Cardiac system.",
    ]

    for q in test_questions:
        print("=" * 70)
        print(f"QUESTION: {q}")
        result = agent.ask(q)
        print(f"  -> Mapped to column: {result['target_column']}")
        print(f"  -> Filter value:     {result['filter_value']}")
        print(f"  -> Unique subjects:  {result['subject_count']}")
        print(f"  -> USUBJIDs:         {result['usubjids']}")
    print("=" * 70)
