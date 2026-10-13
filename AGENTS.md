# GENERAL DESCRIPTION
This repo is the code for an agentic AI system that teaches users the COBOL coding language based on their learning styles. The learning styles in question are derived from the GenderMag method.

# TECH STACK
- Backend: Python
- Frontend: HTML, CSS, JavaScript
- Libraries: FastAPI, LangChain, 

#LLMS AND RAG
Keep prompts and the persona/character file in their own files, not as strings buried in code. 
Only index public or partner-approved COBOL documentation in the RAG pipeline.
Unit tests must mock LLM calls. No real API calls in CI.


# THINGS YOU SHOULD NEVER DO
- Never write hardcoded credentials
- Never share API keys

# WORKFLOWS
Branch from main;  name branches in kebab-case. Never commit to main directly.
Commits use Conventional Commits
Every PR must pass unit, integration, e2e, lint, and format checks. Never skip or weaken a check to get a green build.


# ALWAYS
- Ask before modifying large parts of the code
- Ask before making a large structural change to the project


