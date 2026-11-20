import json

import psycopg
import pytest

import app as application

DB_ENVIRONMENT = {
    "DB_HOST": "db.example.internal",
    "DB_PORT": "5432",
    "DB_NAME": "appdb",
    "DB_SECRET_ARN": "arn:aws:secretsmanager:eu-north-1:000000000000:secret:test",
    "AWS_REGION": "eu-north-1",
}


class FakeSecretsManager:
    def __init__(self, passwords):
        self.passwords = list(passwords)
        self.calls = 0

    def get_secret_value(self, SecretId):
        password = self.passwords[self.calls]
        self.calls += 1
        return {"SecretString": json.dumps({"username": "appadmin", "password": password})}


class FakeConnection:
    def __init__(self, failures):
        self.failures = failures
        self.executed = 0
        self.commits = 0
        self.rollbacks = 0

    def execute(self, query, params=None):
        self.executed += 1
        if self.failures:
            self.failures -= 1
            raise psycopg.errors.UniqueViolation("duplicate key value violates unique constraint")

    def commit(self):
        self.commits += 1

    def rollback(self):
        self.rollbacks += 1


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(application, "instance_metadata", lambda: {"instance_id": "i-0abc", "zone": "eu-north-1a"})
    monkeypatch.setenv("APP_VERSION", "v1")
    return application.app.test_client()


@pytest.fixture
def secrets(monkeypatch):
    for name, value in DB_ENVIRONMENT.items():
        monkeypatch.setenv(name, value)
    monkeypatch.setattr(application, "_credentials", {})
    fake = FakeSecretsManager(["rotated-away", "current"])
    monkeypatch.setattr(application.boto3, "client", lambda *args, **kwargs: fake)
    return fake


def test_health_does_not_touch_the_database(client, monkeypatch):
    def fail(*args, **kwargs):
        raise AssertionError("the health check must not use the database")

    monkeypatch.setattr(application, "connect", fail)
    monkeypatch.setattr(application, "record_visit", fail)

    response = client.get("/health")

    assert response.status_code == 200
    assert response.get_json() == {"status": "ok"}


def test_api_info_records_a_visit_and_reports_the_total(client, monkeypatch):
    visits = []

    def record(instance_id, zone, version):
        visits.append((instance_id, zone, version))
        return 42

    monkeypatch.setattr(application, "record_visit", record)

    response = client.get("/api/info")

    assert response.status_code == 200
    assert response.get_json() == {"instance_id": "i-0abc", "zone": "eu-north-1a", "version": "v1", "visits": 42}
    assert visits == [("i-0abc", "eu-north-1a", "v1")]


def test_index_page_shows_instance_zone_version_and_visits(client, monkeypatch):
    monkeypatch.setattr(application, "record_visit", lambda *args: 7)

    page = client.get("/").get_data(as_text=True)

    for value in ("i-0abc", "eu-north-1a", "v1", "<td>7</td>"):
        assert value in page


def test_database_outage_returns_503(client, monkeypatch):
    def fail(*args):
        raise psycopg.OperationalError("connection timeout expired")

    monkeypatch.setattr(application, "record_visit", fail)

    response = client.get("/api/info")

    assert response.status_code == 503
    assert response.get_json() == {"error": "database unavailable"}


@pytest.mark.parametrize(
    ("query", "expected"),
    [("", 200), ("?ms=50", 50), ("?ms=5000", 1000), ("?ms=-5", 0), ("?ms=abc", 200)],
)
def test_work_keeps_the_duration_between_0_and_1000_ms(client, monkeypatch, query, expected):
    burned = []
    monkeypatch.setattr(application, "burn_cpu", burned.append)

    response = client.get(f"/work{query}")

    assert response.status_code == 200
    assert response.get_json()["worked_ms"] == expected
    assert burned == [expected]


def test_credentials_are_fetched_again_after_an_authentication_failure(secrets, monkeypatch):
    def fake_connect(**kwargs):
        assert kwargs["sslmode"] == "require"
        if kwargs["password"] != "current":
            raise psycopg.OperationalError('FATAL: password authentication failed for user "appadmin"')
        return "connection"

    monkeypatch.setattr(application.psycopg, "connect", fake_connect)

    assert application.connect() == "connection"
    assert secrets.calls == 2


def test_other_connection_errors_keep_the_cached_credentials(secrets, monkeypatch):
    def fake_connect(**kwargs):
        raise psycopg.OperationalError("connection timeout expired")

    monkeypatch.setattr(application.psycopg, "connect", fake_connect)

    with pytest.raises(psycopg.OperationalError):
        application.connect()
    assert secrets.calls == 1


def test_table_creation_retries_when_another_instance_wins_the_race(monkeypatch):
    monkeypatch.setattr(application, "_table_ready", False)
    monkeypatch.setattr(application.time, "sleep", lambda seconds: None)
    connection = FakeConnection(failures=1)

    application.ensure_table(connection)

    assert (connection.executed, connection.rollbacks, connection.commits) == (2, 1, 1)
    assert application._table_ready
