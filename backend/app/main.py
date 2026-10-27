import os
from fastapi import FastAPI

app = FastAPI(title="COBOL Assistant")

@app.get("/health")
def health():
    return {
        "status": "ok",
        "model": os.getenv("LLM_MODEL"),
        "llm_base_url": os.getenv("LLM_BASE_URL"),
    }