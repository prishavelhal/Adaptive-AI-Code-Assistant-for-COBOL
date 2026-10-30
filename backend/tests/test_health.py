# Tests to have backend give us a health check

from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


# simple test to return a 200 and a json with status ok
def test_health_return_ok():
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json()["status"] == "ok"


# Testing out monkeypatch for CI
# def test_health_reports_model(monkeypatch):
#     monkeypatch.setenv("LLM_MODEL", "granite-test-model")

#     response = client.get("/health")

#     assert response.json()["model"] == "granite-test-model"
