import json
import os
import time
import urllib.request

import boto3
import psycopg
from flask import Flask, render_template_string, request

IMDS_URL = "http://169.254.169.254/latest"
MAX_WORK_MS = 1000

CREATE_TABLE = """
CREATE TABLE IF NOT EXISTS visits (
    id bigserial PRIMARY KEY,
    instance_id text NOT NULL,
    zone text NOT NULL,
    app_version text NOT NULL,
    visited_at timestamptz NOT NULL DEFAULT now()
)
"""

PAGE = """<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>aws-ha-three-tier</title></head>
<body>
<h1>aws-ha-three-tier</h1>
<table>
<tr><th>Instance</th><td>{{ instance_id }}</td></tr>
<tr><th>Availability Zone</th><td>{{ zone }}</td></tr>
<tr><th>Version</th><td>{{ version }}</td></tr>
<tr><th>Total visits</th><td>{{ visits }}</td></tr>
</table>
</body>
</html>
"""

app = Flask(__name__)
_metadata = {}
_credentials = {}
_table_ready = False


def imds(path, method="GET", headers=None):
    req = urllib.request.Request(f"{IMDS_URL}/{path}", method=method, headers=headers or {})
    with urllib.request.urlopen(req, timeout=2) as response:
        return response.read().decode()


def instance_metadata():
    if not _metadata:
        try:
            token = imds("api/token", method="PUT", headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"})
            headers = {"X-aws-ec2-metadata-token": token}
            _metadata.update(
                instance_id=imds("meta-data/instance-id", headers=headers),
                zone=imds("meta-data/placement/availability-zone", headers=headers),
            )
        except OSError:
            return {"instance_id": "unknown", "zone": "unknown"}
    return _metadata


def database_credentials(refresh=False):
    if refresh or not _credentials:
        client = boto3.client("secretsmanager", region_name=os.environ["AWS_REGION"])
        secret = client.get_secret_value(SecretId=os.environ["DB_SECRET_ARN"])
        _credentials.update(json.loads(secret["SecretString"]))
    return _credentials


def connect():
    for attempt in (1, 2):
        credentials = database_credentials(refresh=attempt == 2)
        try:
            return psycopg.connect(
                host=os.environ["DB_HOST"],
                port=os.environ["DB_PORT"],
                dbname=os.environ["DB_NAME"],
                user=credentials["username"],
                password=credentials["password"],
                sslmode="require",
                connect_timeout=3,
            )
        except psycopg.OperationalError as error:
            if attempt == 2 or "password authentication failed" not in str(error):
                raise


def ensure_table(connection):
    global _table_ready
    if _table_ready:
        return
    for attempt in (1, 2, 3):
        try:
            connection.execute(CREATE_TABLE)
            connection.commit()
            _table_ready = True
            return
        except (psycopg.errors.UniqueViolation, psycopg.errors.DuplicateTable):
            connection.rollback()
            if attempt == 3:
                raise
            time.sleep(0.2 * attempt)


def record_visit(instance_id, zone, version):
    with connect() as connection:
        ensure_table(connection)
        connection.execute(
            "INSERT INTO visits (instance_id, zone, app_version) VALUES (%s, %s, %s)",
            (instance_id, zone, version),
        )
        return connection.execute("SELECT count(*) FROM visits").fetchone()[0]


def info():
    metadata = instance_metadata()
    version = os.environ.get("APP_VERSION", "dev")
    visits = record_visit(metadata["instance_id"], metadata["zone"], version)
    return {**metadata, "version": version, "visits": visits}


def burn_cpu(milliseconds):
    deadline = time.perf_counter() + milliseconds / 1000
    while time.perf_counter() < deadline:
        pass


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/")
def index():
    return render_template_string(PAGE, **info())


@app.get("/api/info")
def api_info():
    return info()


@app.get("/work")
def work():
    milliseconds = min(max(request.args.get("ms", 200, type=int), 0), MAX_WORK_MS)
    burn_cpu(milliseconds)
    return {"worked_ms": milliseconds, **instance_metadata()}


@app.errorhandler(psycopg.OperationalError)
def database_unavailable(error):
    app.logger.warning("Database unavailable: %s", error)
    return {"error": "database unavailable"}, 503


def prepare_database():
    try:
        with connect() as connection:
            ensure_table(connection)
    except Exception:
        app.logger.exception("Database not ready at startup, the table will be created on first use")


if "DB_SECRET_ARN" in os.environ:
    prepare_database()
