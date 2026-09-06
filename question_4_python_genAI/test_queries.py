"""
===============================================================================
Program Name   : test_queries.py
Study          : [Study ID / Protocol Number]
Purpose        : Test script demonstrating ClinicalTrialDataAgent end-to-end
                 on 3 example natural-language questions, per the assessment
                 deliverable: "A simple block of code that runs 3 example
                 queries (of your choice) and prints the results."

Input          : adae.csv (place this file in question_4_genai/ or update
                 the CSV_PATH constant below)

Output         : Console output showing, for each question:
                   - the LLM's raw JSON response
                   - the parsed target_column / filter_value
                   - the count of unique matching subjects (USUBJID)
                   - the list of matching subject IDs

Author         : Tapender Singh
Date Created   : 2026-09-06
Last Modified  : 2026-09-06
===============================================================================
"""

import pandas as pd
from clinical_trial_data_agent import ClinicalTrialDataAgent

CSV_PATH = "adae.csv"


def main():
    ae_df = pd.read_csv(CSV_PATH)

    # If you have an OpenAI API key, set it as an environment variable
    # (OPENAI_API_KEY) before running this script to use a real LLM call.
    # Otherwise, the agent automatically falls back to a mocked LLM response,
    # and the full Prompt -> Parse -> Execute flow still runs end-to-end.
    agent = ClinicalTrialDataAgent(ae_df=ae_df)

    example_questions = [
        "Give me the subjects who had Adverse events of Moderate severity.",
        "Which subjects reported Headache?",
        "Show me subjects with Cardiac related adverse events.",
    ]

    for i, question in enumerate(example_questions, start=1):
        print("=" * 79)
        print(f"Example Query {i}")
        print("=" * 79)

        result = agent.answer(question)

        print(f"\nNumber of unique subjects : {result.subject_count}")
        print(f"Matching USUBJIDs         : {result.subject_ids}\n")


if __name__ == "__main__":
    main()
