import os
import pytest
from app import app as flask_app


@pytest.fixture
def client():
    flask_app.config["TESTING"] = True
    with flask_app.test_client() as c:
        yield c


def test_root_returns_json_with_required_fields(client):
    response = client.get("/")
    assert response.status_code == 200
    data = response.get_json()
    assert "message" in data
    assert "version" in data
    assert "environment" in data


def test_root_message_content(client):
    response = client.get("/")
    data = response.get_json()
    assert "Flask" in data["message"]


def test_root_version_from_env(client, monkeypatch):
    monkeypatch.setenv("APP_VERSION", "2.5.0")
    response = client.get("/")
    assert response.get_json()["version"] == "2.5.0"


def test_root_version_defaults_when_env_missing(client, monkeypatch):
    monkeypatch.delenv("APP_VERSION", raising=False)
    response = client.get("/")
    assert response.get_json()["version"] == "1.0.0"


def test_root_environment_from_env(client, monkeypatch):
    monkeypatch.setenv("APP_ENV", "staging")
    response = client.get("/")
    assert response.get_json()["environment"] == "staging"


def test_liveness_returns_200_and_alive(client):
    response = client.get("/health/live")
    assert response.status_code == 200
    assert response.get_json() == {"status": "alive"}


def test_readiness_returns_200_and_ready(client):
    response = client.get("/health/ready")
    assert response.status_code == 200
    assert response.get_json() == {"status": "ready"}


def test_metrics_returns_prometheus_content_type(client):
    response = client.get("/metrics")
    assert response.status_code == 200
    assert "text/plain" in response.content_type


def test_metrics_contains_request_counter(client):
    client.get("/")
    response = client.get("/metrics")
    assert b"http_requests_total" in response.data


def test_unknown_route_returns_404(client):
    response = client.get("/does-not-exist")
    assert response.status_code == 404
