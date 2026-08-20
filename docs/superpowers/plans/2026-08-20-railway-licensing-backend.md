# Railway Licensing Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add licence validation, deactivation, onboarding and Gumroad webhook handling to the existing Railway FastAPI service, backed by a new Railway Postgres, with the 39 live licences migrated across.

**Architecture:** A new `APIRouter` in `api/license.py` talks to Postgres through an asyncpg pool in `api/db.py`. Schema and roles come from numbered SQL files in `api/migrations/`, applied by `api/migrate.py`. The router is registered in `main.py` **only when `DATABASE_URL` is set**, because that same `main.py` runs bundled inside the .app where no database exists.

**Tech Stack:** Python 3.11, FastAPI, asyncpg, Postgres 15, pytest + pytest-asyncio + httpx for tests, Railway (Nixpacks) for deploy.

**Spec:** `docs/superpowers/specs/2026-08-20-supabase-to-railway-design.md`

## Global Constraints

- **Scope of this plan is the backend only.** The macOS app still calls Supabase when this plan finishes. Supabase stays live and untouched. The app cutover and Supabase shutdown are a separate plan, written after this one is verified in production.
- **All work happens inside `Server/`, which is its own git repository** (`Sudhanva5/DropBeats-Server`). The outer repo tracks zero files under `Server/`. Commit and push from inside `Server/`.
- **`Server/api/main.py` has uncommitted yt-dlp changes that must never reach Railway.** `/stream-url` and `/song-info` shell out to yt-dlp, which YouTube blocks from datacenter IPs. They exist only as working-tree changes. Every commit touching `main.py` in this plan **must** stage only the licensing hunks, and Task 8 has a hard gate that verifies this before any push.
- **Python version is 3.11**, matching `NIXPACKS_PYTHON_VERSION` in `nixpacks.toml`. The machine's default `python3` is 3.9.6, which is below the target and rejects the PEP 604 unions (`str | None`) this code uses. Install `python@3.11` via Homebrew and run everything — pip, pytest, scripts — through a venv built on it. Never downgrade an annotation to `typing.Optional` to appease 3.9.
- **Dates crossing the wire are `isoformat(timespec="seconds")`.** The shipped Swift decoder has no fractional-seconds formatter; microseconds make the entire response undecodable.
- **Local test database:** Homebrew `postgresql@15`, already running. Binaries are keg-only at `/opt/homebrew/opt/postgresql@15/bin`. Prepend that to `PATH`.
- **Response field names are fixed** by the existing Swift `Codable` decoders in `DropBeat/DropBeat/Models/LicenseModels.swift` and must not change: `valid`, `error`, `name`, `email`, `country`, `created_at`, `has_completed_onboarding`, `success`, `message`.
- **Secrets never go in the repo.** `GUMROAD_SELLER_ID` is `1MCDeB0zEW1je0kaXIy40Q==` and is currently hardcoded in the Supabase plpgsql; in the rebuild it comes from an environment variable.
- **No linter and no existing test suite in this repo.** This plan introduces pytest for the licensing module only. Do not add lint config or reformat untouched code.

---

## File Structure

**Created:**
- `api/db.py` — asyncpg pool lifecycle. Nothing else.
- `api/license.py` — the `APIRouter`, request/response models, and licensing logic.
- `api/migrate.py` — migration runner and app-role provisioning.
- `api/migrations/001_licenses.sql` — tables, normalise function, indexes.
- `api/migrations/002_roles_rls.sql` — grants and RLS policies.
- `api/requirements-dev.txt` — test-only dependencies.
- `api/conftest.py` — pytest fixtures: test database, migrated schema, seeded rows, HTTP client.
- `api/test_license.py` — the licensing test suite.
- `api/export_supabase.py` — one-shot data export, kept for auditability.

**Modified:**
- `api/main.py` — conditional router registration and pool lifecycle. Roughly 12 lines added, nothing removed.
- `api/requirements.txt` — add `asyncpg`.

---

### Task 1: Migration runner and schema

**Files:**
- Create: `api/migrations/001_licenses.sql`, `api/migrations/002_roles_rls.sql`, `api/migrate.py`, `api/requirements-dev.txt`, `api/conftest.py`, `api/test_license.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `migrate.apply(conn, migrations_dir: Path) -> list[str]` returning the names of migrations applied this run. `migrate.ensure_app_role(conn, password: str) -> None`.

- [ ] **Step 1: Add dev dependencies**

Create `api/requirements-dev.txt`:

```
pytest==8.3.4
pytest-asyncio==0.25.2
httpx==0.28.1
asgi-lifespan==2.1.0
```

Add `asyncpg==0.30.0` to `api/requirements.txt` (production dependency — Railway needs it).

Create `api/pytest.ini` so `pytest_asyncio` fixtures resolve without decorating
every one of them:

```ini
[pytest]
asyncio_mode = auto
asyncio_default_fixture_loop_scope = function
```

Install:

```bash
cd Server/api
python3 -m pip install -r requirements.txt -r requirements-dev.txt
```

- [ ] **Step 2: Write the failing test**

Create `api/test_license.py`:

```python
import pytest


@pytest.mark.asyncio
async def test_migrations_create_licenses_table(migrated_conn):
    exists = await migrated_conn.fetchval(
        "select to_regclass('public.licenses') is not null"
    )
    assert exists is True


@pytest.mark.asyncio
async def test_migrations_are_idempotent(migrated_conn, migrations_dir):
    import migrate

    applied = await migrate.apply(migrated_conn, migrations_dir)
    assert applied == [], "re-running migrations should apply nothing"


@pytest.mark.asyncio
async def test_normalize_license_key_strips_case_and_separators(migrated_conn):
    result = await migrated_conn.fetchval(
        "select normalize_license_key($1)", "ab-cd_ef"
    )
    assert result == "ABCDEF"
```

Create `api/conftest.py`:

```python
import os
import sys
from pathlib import Path

import asyncpg
import pytest
import pytest_asyncio

sys.path.insert(0, str(Path(__file__).parent))

# Owner connection: used by fixtures to migrate and to seed rows.
TEST_DSN = os.getenv(
    "TEST_DATABASE_URL", "postgresql://localhost/dropbeats_test"
)
# Maintenance connection: used to drop and recreate the test database.
ADMIN_DSN = os.getenv("TEST_ADMIN_URL", "postgresql://localhost/postgres")
# Least-privilege connection: what the endpoints themselves run under, mirroring
# production. Password matches ensure_app_role() in the migrated_conn fixture.
APP_DSN = os.getenv(
    "TEST_APP_URL",
    "postgresql://dropbeats_app:test_password@localhost/dropbeats_test",
)


@pytest.fixture(scope="session")
def migrations_dir() -> Path:
    return Path(__file__).parent / "migrations"


@pytest_asyncio.fixture
async def migrated_conn(migrations_dir):
    """A connection to a freshly created, freshly migrated test database.

    The database is dropped and recreated per test so that no test can see
    another's rows. At 39 production rows this is cheap and worth the
    isolation.
    """
    import migrate

    admin = await asyncpg.connect(ADMIN_DSN)
    await admin.execute("drop database if exists dropbeats_test with (force)")
    await admin.execute("create database dropbeats_test")
    await admin.close()

    conn = await asyncpg.connect(TEST_DSN)
    # Role first: 002_roles_rls.sql grants TO dropbeats_app, so applying
    # migrations before the role exists fails with "role does not exist".
    await migrate.ensure_app_role(conn, "test_password")
    await migrate.apply(conn, migrations_dir)
    try:
        yield conn
    finally:
        await conn.close()
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
cd Server/api
export PATH="/opt/homebrew/opt/postgresql@15/bin:$PATH"
python3 -m pytest test_license.py -v
```

Expected: FAIL with `ModuleNotFoundError: No module named 'migrate'`.

- [ ] **Step 4: Write the schema migration**

Create `api/migrations/001_licenses.sql`:

```sql
-- Licence storage. Mirrors the live Supabase schema as introspected on
-- 2026-08-20, minus device_id (never written) and last_country (never read).
create table if not exists licenses (
  id                       uuid primary key default gen_random_uuid(),
  email                    text not null,
  full_name                text,
  phone_number             text,
  country                  text,
  license_key              text not null unique,
  sale_id                  text unique,
  is_active                boolean not null default true,
  is_beta                  boolean not null default true,
  has_completed_onboarding boolean not null default false,
  last_login               timestamptz,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);

-- Append-only audit of every inbound webhook payload.
create table if not exists webhook_logs (
  id          uuid primary key default gen_random_uuid(),
  received_at timestamptz not null default now(),
  payload     jsonb,
  success     boolean,
  error       text
);

-- IMMUTABLE because the index below depends on it. Licence keys are compared
-- case-insensitively with dashes and underscores ignored, matching the
-- behaviour the Supabase implementation had.
create or replace function normalize_license_key(p_key text)
returns text language sql immutable strict as $$
  select regexp_replace(upper(p_key), '[-_]', '', 'g')
$$;

-- Validation looks keys up NORMALISED, so a plain index on license_key cannot
-- serve it. Without this expression index every validation is a seq scan.
create unique index if not exists licenses_normalized_key_idx
  on licenses (normalize_license_key(license_key));

create index if not exists licenses_email_idx on licenses (email);

create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists licenses_set_updated_at on licenses;
create trigger licenses_set_updated_at
  before update on licenses
  for each row execute function set_updated_at();
```

Create `api/migrations/002_roles_rls.sql`:

```sql
-- Least-privilege application role. Owns nothing, cannot do DDL, and cannot
-- DELETE anything. The role itself is created by migrate.ensure_app_role,
-- which supplies the password; this file only grants.
grant usage on schema public to dropbeats_app;

grant select, insert, update on licenses     to dropbeats_app;
grant insert                 on webhook_logs to dropbeats_app;
-- Deliberately no DELETE anywhere, and no UPDATE on webhook_logs: the audit
-- log is append-only at the privilege level, not merely by convention.

grant execute on function normalize_license_key(text) to dropbeats_app;

alter table licenses     enable row level security;
alter table licenses     force  row level security;
alter table webhook_logs enable row level security;
alter table webhook_logs force  row level security;

-- SELECT is unrestricted on purpose. Validation must tell "unknown key" apart
-- from "License is not active", and a policy hiding inactive rows collapses
-- those two cases into one error message. Containment here comes from the
-- grants above, not from row filtering.
create policy licenses_app_select on licenses
  for select to dropbeats_app using (true);

create policy licenses_app_insert on licenses
  for insert to dropbeats_app with check (true);

create policy licenses_app_update on licenses
  for update to dropbeats_app using (true) with check (true);

create policy webhook_logs_app_insert on webhook_logs
  for insert to dropbeats_app with check (true);
```

- [ ] **Step 5: Write the migration runner**

Create `api/migrate.py`:

```python
"""Applies numbered .sql files once each, tracked in schema_migrations.

Deliberately tiny. Alembic would bring a migration DSL, autogeneration and a
config file for what is two tables that change roughly never.
"""

import asyncio
import os
import sys
from pathlib import Path

import asyncpg

MIGRATIONS_DIR = Path(__file__).parent / "migrations"


async def apply(conn: asyncpg.Connection, migrations_dir: Path) -> list[str]:
    """Apply every unapplied migration in filename order. Returns their names."""
    await conn.execute(
        """
        create table if not exists schema_migrations (
          name       text primary key,
          applied_at timestamptz not null default now()
        )
        """
    )
    done = {r["name"] for r in await conn.fetch("select name from schema_migrations")}

    applied = []
    for path in sorted(migrations_dir.glob("*.sql")):
        if path.name in done:
            continue
        # Each migration runs in its own transaction: a failure half way
        # through leaves the database on the last good migration rather than
        # in an undefined state.
        async with conn.transaction():
            await conn.execute(path.read_text())
            await conn.execute(
                "insert into schema_migrations (name) values ($1)", path.name
            )
        applied.append(path.name)
    return applied


async def ensure_app_role(conn: asyncpg.Connection, password: str) -> None:
    """Create or update the dropbeats_app login role.

    Kept out of the .sql files because the password comes from the
    environment and must never be committed.
    """
    exists = await conn.fetchval(
        "select 1 from pg_roles where rolname = 'dropbeats_app'"
    )
    quoted = quote_literal(password)
    if exists:
        await conn.execute(f"alter role dropbeats_app with login password {quoted}")
    else:
        await conn.execute(f"create role dropbeats_app with login password {quoted}")


def quote_literal(value: str) -> str:
    """Postgres single-quoted literal. Doubling quotes is the escape."""
    escaped = value.replace("'", "''")
    return f"'{escaped}'"


async def main() -> int:
    dsn = os.environ.get("DATABASE_URL")
    if not dsn:
        print("DATABASE_URL is not set", file=sys.stderr)
        return 1

    conn = await asyncpg.connect(dsn)
    try:
        password = os.environ.get("APP_DB_PASSWORD")
        if password:
            await ensure_app_role(conn, password)
        applied = await apply(conn, MIGRATIONS_DIR)
    finally:
        await conn.close()

    print(f"applied: {applied}" if applied else "already up to date")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
```

Note the ordering in `main()`: the role is created *before* migrations run, because `002_roles_rls.sql` grants to it.

- [ ] **Step 6: Run the tests to verify they pass**

```bash
cd Server/api
export PATH="/opt/homebrew/opt/postgresql@15/bin:$PATH"
python3 -m pytest test_license.py -v
```

Expected: 3 passed.

- [ ] **Step 7: Verify the privilege model actually holds**

Add to `api/test_license.py`:

```python
@pytest.mark.asyncio
async def test_app_role_cannot_delete_licenses(migrated_conn):
    """Asserts the grants are in force rather than assuming the migration ran.

    A DELETE grant slipping in is exactly the kind of regression that is
    invisible until it matters.
    """
    import asyncpg

    await migrated_conn.execute(
        "insert into licenses (email, license_key) values ($1, $2)",
        "a@example.com",
        "KEY-1",
    )

    app_conn = await asyncpg.connect(
        "postgresql://dropbeats_app:test_password@localhost/dropbeats_test"
    )
    try:
        with pytest.raises(asyncpg.InsufficientPrivilegeError):
            await app_conn.execute("delete from licenses")
    finally:
        await app_conn.close()


@pytest.mark.asyncio
async def test_app_role_cannot_update_webhook_logs(migrated_conn):
    import asyncpg

    app_conn = await asyncpg.connect(
        "postgresql://dropbeats_app:test_password@localhost/dropbeats_test"
    )
    try:
        with pytest.raises(asyncpg.InsufficientPrivilegeError):
            await app_conn.execute("update webhook_logs set success = false")
    finally:
        await app_conn.close()
```

Run: `python3 -m pytest test_license.py -v`
Expected: 5 passed.

- [ ] **Step 8: Commit**

```bash
cd Server
git add api/migrate.py api/migrations api/conftest.py api/test_license.py api/pytest.ini \
        api/requirements-dev.txt api/requirements.txt
git commit -m "feat: add licence schema, migration runner and least-privilege role

Two tables, an IMMUTABLE key-normalising function and the expression index
validation needs. The app role owns nothing and holds no DELETE grant
anywhere; tests assert both rather than trusting the migration ran."
```

---

### Task 2: Database pool

**Files:**
- Create: `api/db.py`
- Test: `api/test_license.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `db.init_pool(dsn: str | None = None) -> asyncpg.Pool`, `db.close_pool() -> None`, `db.get_pool() -> asyncpg.Pool`.

- [ ] **Step 1: Write the failing test**

Append to `api/test_license.py`:

```python
@pytest.mark.asyncio
async def test_get_pool_before_init_raises():
    import db

    await db.close_pool()
    with pytest.raises(RuntimeError, match="not initialised"):
        db.get_pool()


@pytest.mark.asyncio
async def test_init_pool_is_idempotent(migrated_conn):
    import db

    await db.close_pool()
    first = await db.init_pool("postgresql://localhost/dropbeats_test")
    second = await db.init_pool("postgresql://localhost/dropbeats_test")
    assert first is second
    await db.close_pool()
```

- [ ] **Step 2: Run to verify it fails**

Run: `python3 -m pytest test_license.py -k pool -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'db'`.

- [ ] **Step 3: Implement**

Create `api/db.py`:

```python
"""asyncpg pool lifecycle. Imported only when DATABASE_URL is set.

Kept separate from license.py so that the bundled macOS build never pulls a
database driver into a process that has no database.
"""

import os

import asyncpg

_pool: asyncpg.Pool | None = None


async def init_pool(dsn: str | None = None) -> asyncpg.Pool:
    global _pool
    if _pool is None:
        _pool = await asyncpg.create_pool(
            dsn or os.environ["DATABASE_URL"],
            min_size=1,
            max_size=5,
            command_timeout=10,
        )
    return _pool


async def close_pool() -> None:
    global _pool
    if _pool is not None:
        await _pool.close()
        _pool = None


def get_pool() -> asyncpg.Pool:
    if _pool is None:
        raise RuntimeError("database pool is not initialised")
    return _pool
```

- [ ] **Step 4: Run to verify it passes**

Run: `python3 -m pytest test_license.py -v`
Expected: 7 passed.

- [ ] **Step 5: Commit**

```bash
cd Server
git add api/db.py api/test_license.py
git commit -m "feat: add asyncpg pool module"
```

---

### Task 3: Validate endpoint

**Files:**
- Create: `api/license.py`
- Test: `api/test_license.py`

**Interfaces:**
- Consumes: `db.get_pool()`.
- Produces: `license.router` (a `fastapi.APIRouter`), serving `POST /license/validate`.

- [ ] **Step 1: Add the app fixture**

Append to `api/conftest.py`:

```python
@pytest_asyncio.fixture
async def client(migrated_conn, monkeypatch):
    """An httpx client bound to a FastAPI app carrying only the licence router.

    main.py is not imported: it constructs a YTMusic client at import time and
    would make these tests depend on YouTube being reachable.
    """
    import httpx
    from fastapi import FastAPI

    import db
    import license as license_module

    monkeypatch.setenv("GUMROAD_SELLER_ID", "test-seller")
    monkeypatch.setenv("GUMROAD_WEBHOOK_SECRET", "test-secret")

    await db.close_pool()
    # Connect as dropbeats_app, not as the owner. Production runs under this
    # role, so tests that ran as owner would silently pass while a missing
    # grant broke the deployed service.
    await db.init_pool(APP_DSN)

    app = FastAPI()
    app.include_router(license_module.router)

    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(
        transport=transport, base_url="http://test"
    ) as c:
        yield c

    await db.close_pool()


@pytest_asyncio.fixture
async def seeded(migrated_conn):
    """One active and one deactivated licence."""
    await migrated_conn.execute(
        """
        insert into licenses (email, full_name, country, license_key, sale_id, is_active)
        values ('active@example.com', 'Active User', 'IN', 'AAAA-BBBB', 'sale_1', true),
               ('gone@example.com',   'Gone User',   'US', 'CCCC-DDDD', 'sale_2', false)
        """
    )
```

- [ ] **Step 2: Write the failing tests**

Append to `api/test_license.py`:

```python
@pytest.mark.asyncio
async def test_validate_accepts_known_active_key(client, seeded):
    r = await client.post("/license/validate", json={"key": "AAAA-BBBB"})
    assert r.status_code == 200
    body = r.json()
    assert body["valid"] is True
    assert body["name"] == "Active User"
    assert body["email"] == "active@example.com"
    assert body["country"] == "IN"
    assert body["has_completed_onboarding"] is False
    assert body["created_at"] is not None


@pytest.mark.asyncio
async def test_validate_rejects_unknown_key(client, seeded):
    r = await client.post("/license/validate", json={"key": "NOPE-NOPE"})
    assert r.status_code == 200
    assert r.json() == {
        "valid": False,
        "error": "Invalid license key",
        "name": None,
        "email": None,
        "country": None,
        "created_at": None,
        "has_completed_onboarding": None,
    }


@pytest.mark.asyncio
async def test_validate_rejects_deactivated_key(client, seeded):
    r = await client.post("/license/validate", json={"key": "CCCC-DDDD"})
    assert r.json()["valid"] is False
    assert r.json()["error"] == "License is not active"


@pytest.mark.asyncio
@pytest.mark.parametrize("variant", ["aaaa-bbbb", "AAAABBBB", "aa_aa_bbbb", "AaAa-BbBb"])
async def test_validate_normalises_key_variants(client, seeded, variant):
    r = await client.post("/license/validate", json={"key": variant})
    assert r.json()["valid"] is True, f"{variant} should resolve to the same licence"


@pytest.mark.asyncio
async def test_validate_updates_last_login(client, seeded, migrated_conn):
    before = await migrated_conn.fetchval(
        "select last_login from licenses where license_key = 'AAAA-BBBB'"
    )
    assert before is None

    await client.post("/license/validate", json={"key": "AAAA-BBBB"})

    after = await migrated_conn.fetchval(
        "select last_login from licenses where license_key = 'AAAA-BBBB'"
    )
    assert after is not None
```

- [ ] **Step 3: Run to verify they fail**

Run: `python3 -m pytest test_license.py -k validate -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'license'`.

- [ ] **Step 4: Implement**

Create `api/license.py`:

```python
"""Licence validation, deactivation, onboarding and the Gumroad webhook.

Replaces the Supabase plpgsql RPCs. The behaviour is carried over; the debris
is not — the original logged every licence key in the table on every call,
built its lookup SQL with format() and execute(), and threaded a dead
p_device_id parameter through three functions.
"""

import logging
import os

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

import db

logger = logging.getLogger(__name__)

router = APIRouter()


class ValidateRequest(BaseModel):
    key: str


class ValidateResponse(BaseModel):
    valid: bool
    error: str | None = None
    name: str | None = None
    email: str | None = None
    country: str | None = None
    created_at: str | None = None
    has_completed_onboarding: bool | None = None


# Field names match the Swift Codable decoders in LicenseModels.swift and are
# not free to change.
LOOKUP_SQL = """
    select id, full_name, email, country, is_active, created_at,
           has_completed_onboarding
    from licenses
    where normalize_license_key(license_key) = normalize_license_key($1)
"""


@router.post("/license/validate", response_model=ValidateResponse)
async def validate_license(payload: ValidateRequest) -> ValidateResponse:
    pool = db.get_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow(LOOKUP_SQL, payload.key)

        if row is None:
            logger.info("licence validation: unknown key")
            return ValidateResponse(valid=False, error="Invalid license key")

        if not row["is_active"]:
            logger.info("licence validation: inactive licence %s", row["id"])
            return ValidateResponse(valid=False, error="License is not active")

        await conn.execute(
            "update licenses set last_login = now() where id = $1", row["id"]
        )

        logger.info("licence validation: ok for %s", row["id"])
        return ValidateResponse(
            valid=True,
            name=row["full_name"],
            email=row["email"],
            country=row["country"],
            # timespec="seconds" is load-bearing, not cosmetic. The shipped
            # Swift decoder tries ISO8601DateFormatter with default options
            # and three DateFormatter patterns, none fractional-seconds
            # aware, so microseconds make the whole response undecodable.
            # Supabase returns "2025-01-20T09:47:01+00:00"; match it exactly.
            created_at=row["created_at"].isoformat(timespec="seconds"),
            has_completed_onboarding=row["has_completed_onboarding"],
        )
```

- [ ] **Step 5: Run to verify they pass**

Run: `python3 -m pytest test_license.py -v`
Expected: 15 passed.

- [ ] **Step 6: Commit**

```bash
cd Server
git add api/license.py api/conftest.py api/test_license.py
git commit -m "feat: add licence validation endpoint

Preserves the two distinct failure messages the app depends on: an unknown
key and a deactivated licence are not the same answer."
```

---

### Task 4: Deactivate and onboarding endpoints

**Files:**
- Modify: `api/license.py`
- Test: `api/test_license.py`

**Interfaces:**
- Consumes: `db.get_pool()`, `LOOKUP_SQL`.
- Produces: `POST /license/deactivate`, `POST /license/onboarding`.

- [ ] **Step 1: Write the failing tests**

Append to `api/test_license.py`:

```python
@pytest.mark.asyncio
async def test_deactivate_marks_licence_inactive(client, seeded, migrated_conn):
    r = await client.post(
        "/license/deactivate",
        json={"key": "AAAA-BBBB", "email": "active@example.com"},
    )
    assert r.status_code == 200
    assert r.json()["success"] is True

    still_active = await migrated_conn.fetchval(
        "select is_active from licenses where license_key = 'AAAA-BBBB'"
    )
    assert still_active is False


@pytest.mark.asyncio
async def test_deactivate_requires_matching_email(client, seeded, migrated_conn):
    """The email is the authorisation check: holding the key alone must not be
    enough to deactivate someone else's licence."""
    r = await client.post(
        "/license/deactivate",
        json={"key": "AAAA-BBBB", "email": "attacker@example.com"},
    )
    assert r.json()["success"] is False
    assert r.json()["error"] == "License not found"

    still_active = await migrated_conn.fetchval(
        "select is_active from licenses where license_key = 'AAAA-BBBB'"
    )
    assert still_active is True


@pytest.mark.asyncio
async def test_onboarding_flag_round_trips(client, seeded):
    r = await client.post(
        "/license/onboarding", json={"key": "AAAA-BBBB", "completed": True}
    )
    assert r.json()["success"] is True

    check = await client.post("/license/validate", json={"key": "AAAA-BBBB"})
    assert check.json()["has_completed_onboarding"] is True


@pytest.mark.asyncio
async def test_onboarding_unknown_key_reports_failure(client, seeded):
    r = await client.post(
        "/license/onboarding", json={"key": "NOPE", "completed": True}
    )
    assert r.json()["success"] is False
    assert r.json()["error"] == "License not found"
```

- [ ] **Step 2: Run to verify they fail**

Run: `python3 -m pytest test_license.py -k "deactivate or onboarding" -v`
Expected: FAIL with 404s — the routes do not exist.

- [ ] **Step 3: Implement**

Append to `api/license.py`:

```python
class DeactivateRequest(BaseModel):
    key: str
    email: str


class MutationResponse(BaseModel):
    success: bool
    message: str = ""
    error: str | None = None


class OnboardingRequest(BaseModel):
    key: str
    completed: bool


@router.post("/license/deactivate", response_model=MutationResponse)
async def deactivate_license(payload: DeactivateRequest) -> MutationResponse:
    pool = db.get_pool()
    async with pool.acquire() as conn:
        # Email is matched alongside the key so that possession of a key alone
        # cannot deactivate a licence.
        updated = await conn.fetchval(
            """
            update licenses
            set is_active = false
            where normalize_license_key(license_key) = normalize_license_key($1)
              and lower(email) = lower($2)
            returning id
            """,
            payload.key,
            payload.email,
        )

    if updated is None:
        return MutationResponse(success=False, error="License not found")
    logger.info("licence deactivated: %s", updated)
    return MutationResponse(success=True, message="License deactivated")


@router.post("/license/onboarding", response_model=MutationResponse)
async def update_onboarding(payload: OnboardingRequest) -> MutationResponse:
    pool = db.get_pool()
    async with pool.acquire() as conn:
        updated = await conn.fetchval(
            """
            update licenses
            set has_completed_onboarding = $2
            where normalize_license_key(license_key) = normalize_license_key($1)
            returning id
            """,
            payload.key,
            payload.completed,
        )

    if updated is None:
        return MutationResponse(success=False, error="License not found")
    return MutationResponse(success=True, message="Onboarding status updated")
```

- [ ] **Step 4: Run to verify they pass**

Run: `python3 -m pytest test_license.py -v`
Expected: 19 passed.

- [ ] **Step 5: Commit**

```bash
cd Server
git add api/license.py api/test_license.py
git commit -m "feat: add licence deactivation and onboarding endpoints

Deactivation matches on email as well as key, so holding a key alone is not
authorisation to deactivate it."
```

---

### Task 5: Gumroad webhook

**Files:**
- Modify: `api/license.py`
- Test: `api/test_license.py`

**Interfaces:**
- Consumes: `db.get_pool()`.
- Produces: `POST /webhooks/gumroad/{secret}`.

Gumroad posts `application/x-www-form-urlencoded`, not JSON — the existing Cloudflare Worker confirms this. The endpoint reads the raw form.

> **Corrections applied during execution.** Review of this task found four Important
> defects in the code below, all of which shipped fixes. If you re-run this plan, apply
> these rather than the literal code in Steps 1 and 3:
>
> 1. `secrets.compare_digest` raises `TypeError` on non-ASCII `str`, and Starlette
>    percent-decodes the path segment. `POST /webhooks/gumroad/%C3%A9` therefore 500s while
>    every other bad path 404s — an oracle that defeats the 404-not-403 rule. Compare
>    **bytes**: `compare_digest(secret.encode(), expected_secret.encode())`.
> 2. The `seller_id` check lacks the `not expected_seller or` fail-closed clause the secret
>    check has. With `GUMROAD_SELLER_ID` unset, a posted empty `seller_id=` compares equal
>    and passes, silently removing the second factor.
> 3. `ON CONFLICT (sale_id)` cannot fire when `sale_id` is NULL, and `license_key` carries
>    its own UNIQUE plus a unique normalised index. A replay then raises
>    `UniqueViolationError` → 500 → Gumroad retries forever. Validate `sale_id` is present,
>    and catch `UniqueViolationError` to return **200** with `success=False` — Gumroad stops
>    retrying only on a 2xx, so a permanent conflict must not look transient.
> 4. `test_webhook_replay_creates_exactly_one_licence` asserts only the row count, so it
>    passes against the unconditional-INSERT regression its own docstring names. Assert the
>    second response is 200 with `success=True` as well.

- [ ] **Step 1: Write the failing tests**

Append to `api/test_license.py`:

```python
GUMROAD_SALE = {
    "email": "buyer@example.com",
    "full_name": "Buyer Person",
    "seller_id": "test-seller",
    "sale_id": "sale_new_1",
    "license_key": "EEEE-FFFF",
    "country_code": "IN",
}


@pytest.mark.asyncio
async def test_webhook_creates_licence(client, migrated_conn):
    r = await client.post("/webhooks/gumroad/test-secret", data=GUMROAD_SALE)
    assert r.status_code == 200
    assert r.json()["success"] is True

    row = await migrated_conn.fetchrow(
        "select email, full_name, country, is_active from licenses "
        "where license_key = 'EEEE-FFFF'"
    )
    assert row["email"] == "buyer@example.com"
    assert row["full_name"] == "Buyer Person"
    assert row["country"] == "IN"
    assert row["is_active"] is True


@pytest.mark.asyncio
async def test_webhook_replay_creates_exactly_one_licence(client, migrated_conn):
    """Gumroad retries on non-2xx. The original handler inserted
    unconditionally, so a retry duplicated the licence."""
    await client.post("/webhooks/gumroad/test-secret", data=GUMROAD_SALE)
    await client.post("/webhooks/gumroad/test-secret", data=GUMROAD_SALE)

    count = await migrated_conn.fetchval(
        "select count(*) from licenses where sale_id = 'sale_new_1'"
    )
    assert count == 1


@pytest.mark.asyncio
async def test_webhook_rejects_wrong_seller(client, migrated_conn):
    payload = dict(GUMROAD_SALE, seller_id="impostor")
    r = await client.post("/webhooks/gumroad/test-secret", data=payload)
    assert r.json()["success"] is False

    count = await migrated_conn.fetchval("select count(*) from licenses")
    assert count == 0


@pytest.mark.asyncio
async def test_webhook_rejects_wrong_secret_path(client):
    r = await client.post("/webhooks/gumroad/wrong-secret", data=GUMROAD_SALE)
    assert r.status_code == 404


@pytest.mark.asyncio
async def test_webhook_logs_every_payload_including_rejected(client, migrated_conn):
    await client.post(
        "/webhooks/gumroad/test-secret", data=dict(GUMROAD_SALE, seller_id="impostor")
    )
    count = await migrated_conn.fetchval("select count(*) from webhook_logs")
    assert count >= 1
```

- [ ] **Step 2: Run to verify they fail**

Run: `python3 -m pytest test_license.py -k webhook -v`
Expected: FAIL with 404s.

- [ ] **Step 3: Implement**

Append to `api/license.py`:

```python
import json
import secrets


@router.post("/webhooks/gumroad/{secret}", response_model=MutationResponse)
async def gumroad_webhook(secret: str, request: Request) -> MutationResponse:
    """Gumroad sale notification.

    Two independent factors guard this: an unguessable path segment and a
    seller_id check. Gumroad does not sign its pings, so the secret path is
    what stands in for a signature.
    """
    expected_secret = os.environ.get("GUMROAD_WEBHOOK_SECRET", "")
    # compare_digest so the path segment cannot be recovered by timing.
    if not expected_secret or not secrets.compare_digest(secret, expected_secret):
        # 404 rather than 403: an attacker probing paths learns nothing about
        # whether this route exists.
        raise HTTPException(status_code=404, detail="Not found")

    form = await request.form()
    payload = dict(form)

    pool = db.get_pool()
    async with pool.acquire() as conn:
        # Logged before any validation, so a rejected webhook is still
        # evidence. The original design got this right.
        await conn.execute(
            "insert into webhook_logs (payload, success) values ($1::jsonb, $2)",
            json.dumps(payload),
            True,
        )

        expected_seller = os.environ.get("GUMROAD_SELLER_ID", "")
        if payload.get("seller_id") != expected_seller:
            logger.warning("gumroad webhook: seller_id mismatch")
            await conn.execute(
                "insert into webhook_logs (payload, success, error) "
                "values ($1::jsonb, false, $2)",
                json.dumps({"event": "seller_verification_failed"}),
                "Invalid seller ID",
            )
            return MutationResponse(success=False, error="Invalid seller ID")

        email = payload.get("email")
        license_key = payload.get("license_key")
        if not email or not license_key:
            await conn.execute(
                "insert into webhook_logs (payload, success, error) "
                "values ($1::jsonb, false, $2)",
                json.dumps({"event": "missing_fields"}),
                "Missing email or license_key",
            )
            return MutationResponse(success=False, error="Missing email or license_key")

        full_name = payload.get("full_name") or email.split("@")[0]

        # Upsert on sale_id makes Gumroad retries idempotent.
        await conn.execute(
            """
            insert into licenses (email, full_name, country, license_key, sale_id)
            values ($1, $2, $3, $4, $5)
            on conflict (sale_id) do update
            set email      = excluded.email,
                full_name  = excluded.full_name,
                country    = excluded.country,
                license_key = excluded.license_key
            """,
            email,
            full_name,
            payload.get("country_code") or "Unknown",
            license_key,
            payload.get("sale_id"),
        )

    logger.info("gumroad webhook: licence created or updated")
    return MutationResponse(success=True, message="License created")
```

Move the `import json` and `import secrets` lines up to the module's import block rather than leaving them mid-file.

- [ ] **Step 4: Run to verify they pass**

Run: `python3 -m pytest test_license.py -v`
Expected: 24 passed.

- [ ] **Step 5: Commit**

```bash
cd Server
git add api/license.py api/test_license.py
git commit -m "feat: add Gumroad webhook with idempotent upsert

Replays now update one row instead of inserting a duplicate. Every payload
is logged before validation, so rejected webhooks remain evidence."
```

---

### Task 6: Rate limiting on validate

**Files:**
- Modify: `api/license.py`
- Test: `api/test_license.py`

**Interfaces:**
- Produces: `license.RateLimiter` with `allow(key: str) -> bool`.

- [ ] **Step 1: Write the failing test**

Append to `api/test_license.py`:

```python
def test_rate_limiter_allows_then_blocks():
    import license as license_module

    limiter = license_module.RateLimiter(capacity=3, refill_per_second=0.0)
    assert [limiter.allow("1.2.3.4") for _ in range(3)] == [True, True, True]
    assert limiter.allow("1.2.3.4") is False


def test_rate_limiter_is_per_key():
    import license as license_module

    limiter = license_module.RateLimiter(capacity=1, refill_per_second=0.0)
    assert limiter.allow("1.1.1.1") is True
    assert limiter.allow("1.1.1.1") is False
    assert limiter.allow("2.2.2.2") is True


def test_rate_limiter_refills_over_time():
    import license as license_module

    clock = {"now": 1000.0}
    limiter = license_module.RateLimiter(
        capacity=1, refill_per_second=1.0, clock=lambda: clock["now"]
    )
    assert limiter.allow("1.1.1.1") is True
    assert limiter.allow("1.1.1.1") is False
    clock["now"] += 2.0
    assert limiter.allow("1.1.1.1") is True
```

- [ ] **Step 2: Run to verify it fails**

Run: `python3 -m pytest test_license.py -k rate_limiter -v`
Expected: FAIL with `AttributeError: module 'license' has no attribute 'RateLimiter'`.

- [ ] **Step 3: Implement**

Add to `api/license.py` (imports at the top: `import time`, `from collections import defaultdict`, `from typing import Callable`):

```python
class RateLimiter:
    """Per-key token bucket.

    In-process, so it protects a single instance only. If this service ever
    runs more than one replica this needs to move to shared state.
    """

    def __init__(
        self,
        capacity: int,
        refill_per_second: float,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.capacity = capacity
        self.refill_per_second = refill_per_second
        self.clock = clock
        self._buckets: dict[str, tuple[float, float]] = {}

    def allow(self, key: str) -> bool:
        now = self.clock()
        tokens, last = self._buckets.get(key, (float(self.capacity), now))
        tokens = min(self.capacity, tokens + (now - last) * self.refill_per_second)

        if tokens < 1.0:
            self._buckets[key] = (tokens, now)
            return False

        self._buckets[key] = (tokens - 1.0, now)
        return True


# 30 validations per minute per IP. The app validates once a day; anything
# near this ceiling is not a real client.
_validate_limiter = RateLimiter(capacity=30, refill_per_second=0.5)
```

Change the `validate_license` signature to take the request and apply the limiter as its first action:

```python
@router.post("/license/validate", response_model=ValidateResponse)
async def validate_license(payload: ValidateRequest, request: Request) -> ValidateResponse:
    client_ip = request.client.host if request.client else "unknown"
    if not _validate_limiter.allow(client_ip):
        raise HTTPException(status_code=429, detail="Too many requests")
    ...
```

- [ ] **Step 4: Run to verify they pass**

Run: `python3 -m pytest test_license.py -v`
Expected: 27 passed.

- [ ] **Step 5: Commit**

```bash
cd Server
git add api/license.py api/test_license.py
git commit -m "feat: rate-limit licence validation per IP"
```

---

### Task 7: Wire the router into main.py without breaking the bundled app

**Files:**
- Modify: `api/main.py`

**Interfaces:**
- Consumes: `license.router`, `db.init_pool`, `db.close_pool`.

This is the task where the two-backend hazard bites. `main.py` is also the file bundled into the .app, and its working tree carries uncommitted yt-dlp endpoints that must not reach Railway.

- [ ] **Step 1: Record what must not be committed**

```bash
cd Server
git diff --stat api/main.py
grep -n "stream-url\|song-info" api/main.py
```

Note the line ranges. Those hunks stay unstaged for the rest of this plan.

- [ ] **Step 2: Add the conditional registration**

In `api/main.py`, immediately after `app = FastAPI(title="DropBeat Music API")` and its CORS block, add:

```python
# The licensing router is registered only when a database is configured.
# This same file runs bundled inside the macOS .app on port 4002, where there
# is no database and no asyncpg — hence the import inside the branch rather
# than at module scope.
LICENSING_ENABLED = bool(os.getenv("DATABASE_URL"))

if LICENSING_ENABLED:
    from license import router as license_router

    app.include_router(license_router)
```

- [ ] **Step 3: Add pool lifecycle to the existing startup handler**

Inside the existing `startup_event`, after the `logger.info(f"Starting DropBeat Music API in {environment} mode")` line:

```python
    if LICENSING_ENABLED:
        import db

        await db.init_pool()
        logger.info("✅ Licensing enabled (database pool ready)")
    else:
        logger.info("ℹ️ Licensing disabled (no DATABASE_URL) — bundled/local mode")
```

And add a shutdown handler next to it:

```python
@app.on_event("shutdown")
async def shutdown_event():
    if LICENSING_ENABLED:
        import db

        await db.close_pool()
```

- [ ] **Step 4: Verify the bundled path is genuinely unaffected**

This is the regression that would ship a broken .app, so test it directly. With no `DATABASE_URL`:

```bash
cd Server/api
env -u DATABASE_URL ../../build/python_bundle/python/bin/python3 -B \
    -m uvicorn main:app --host 127.0.0.1 --port 4013 &
sleep 8
curl -s --max-time 5 http://127.0.0.1:4013/health
curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 \
    -X POST http://127.0.0.1:4013/license/validate
kill %1
```

Expected: `/health` returns `{"status":"healthy",...}`, and `/license/validate` returns `404`. The bundled Python has no asyncpg installed, so if the import were unconditional this step would fail at boot — which is exactly what it is checking.

- [ ] **Step 5: Verify licensing mode still boots**

```bash
cd Server/api
export PATH="/opt/homebrew/opt/postgresql@15/bin:$PATH"
DATABASE_URL=postgresql://localhost/dropbeats_test \
GUMROAD_SELLER_ID=test-seller GUMROAD_WEBHOOK_SECRET=test-secret \
  python3 -m uvicorn main:app --port 4014 &
sleep 8
curl -s -X POST http://127.0.0.1:4014/license/validate \
     -H 'content-type: application/json' -d '{"key":"nope"}'
kill %1
```

Expected: `{"valid":false,"error":"Invalid license key",...}`.

- [ ] **Step 6: Stage ONLY the licensing hunks**

```bash
cd Server
git add -p api/main.py
```

Accept only the three licensing hunks from Steps 2 and 3. Reject every hunk touching `get_ytdlp_command`, `/stream-url` or `/song-info`.

- [ ] **Step 7: Hard gate — prove no yt-dlp code is staged**

```bash
cd Server
git diff --cached api/main.py | grep -c "stream-url\|song-info\|yt_dlp"
```

Expected: `0`. **If this is not zero, unstage and redo Step 6.** Do not proceed.

- [ ] **Step 8: Commit**

```bash
cd Server
git commit -m "feat: register licensing router when DATABASE_URL is set

Conditional so the copy of this file bundled inside the macOS app, which has
no database and no asyncpg, keeps booting unchanged."
git show --stat HEAD
```

Confirm the commit contains only `api/main.py` and only the licensing lines.

---

### Task 8: Provision Railway Postgres and apply migrations

**Files:** none — infrastructure.

**Interfaces:**
- Produces: a `DATABASE_URL` on the Railway service, and a migrated schema.

Prerequisite already satisfied: `railway whoami` reports `sudhanva.udupi55@gmail.com` and `Server/` is linked to project `DropBeats - Server` (`9081d0fe-4029-4f80-8e70-038520151695`).

- [ ] **Step 1: Add a Postgres service**

Use the Railway MCP `create_service` against project `9081d0fe-4029-4f80-8e70-038520151695` with the Postgres template, or in the dashboard: **New → Database → PostgreSQL**.

- [ ] **Step 2: Wire two separate connection variables**

The application and the migration runner must not use the same role. Railway's
`${{Postgres.DATABASE_URL}}` is the **superuser** DSN; pointing the app at it
would make the least-privilege role and the RLS policies decorative.

On the `DropBeats-Server` service set:

```
ADMIN_DATABASE_URL     = ${{Postgres.DATABASE_URL}}
APP_DB_PASSWORD        = <generate a long random string>
GUMROAD_SELLER_ID      = 1MCDeB0zEW1je0kaXIy40Q==
GUMROAD_WEBHOOK_SECRET = <generate a long random string>
```

`DATABASE_URL` is set in Step 5, once the role exists and its password is known.
Record both generated values in a password manager — they are needed in Task 9
and in the app-cutover plan.

- [ ] **Step 3: Point the migration runner at the admin DSN**

Modify `api/migrate.py` so `main()` reads the admin variable, falling back to
`DATABASE_URL` for local use where the developer is already superuser:

```python
    dsn = os.environ.get("ADMIN_DATABASE_URL") or os.environ.get("DATABASE_URL")
    if not dsn:
        print("neither ADMIN_DATABASE_URL nor DATABASE_URL is set", file=sys.stderr)
        return 1
```

Commit:

```bash
cd Server
git add api/migrate.py
git commit -m "fix: run migrations as the admin role, not the app role"
```

- [ ] **Step 4: Apply migrations against Railway**

```bash
cd Server/api
railway run python3 migrate.py
```

Expected output: `applied: ['001_licenses.sql', '002_roles_rls.sql']`.

Run it a second time and expect `already up to date`.

- [ ] **Step 5: Set the application DSN to the least-privilege role**

Take the host, port and database name from `${{Postgres.DATABASE_URL}}`, and
build the app's DSN with the `dropbeats_app` role and the `APP_DB_PASSWORD`
chosen in Step 2. Use the private-network host (`postgres.railway.internal`)
rather than the public proxy:

```
DATABASE_URL = postgresql://dropbeats_app:<APP_DB_PASSWORD>@postgres.railway.internal:5432/railway
```

- [ ] **Step 6: Prove the app role is genuinely constrained in production**

```bash
cd Server/api
railway run python3 -c "
import asyncio, asyncpg, os
async def main():
    c = await asyncpg.connect(os.environ['DATABASE_URL'])
    print('connected as:', await c.fetchval('select current_user'))
    try:
        await c.execute('delete from licenses')
        print('FAIL: delete was permitted')
    except asyncpg.InsufficientPrivilegeError:
        print('OK: delete refused')
    await c.close()
asyncio.run(main())
"
```

Expected: `connected as: dropbeats_app` and `OK: delete refused`. If it reports
`postgres`, `DATABASE_URL` is still the superuser DSN — fix before continuing.

- [ ] **Step 7: Verify the schema landed**

```bash
cd Server/api
railway run python3 -c "
import asyncio, asyncpg, os
async def main():
    c = await asyncpg.connect(os.environ['DATABASE_URL'])
    print(await c.fetch(\"select tablename from pg_tables where schemaname='public'\"))
    print(await c.fetchval(\"select count(*) from pg_policies where tablename='licenses'\"))
    await c.close()
asyncio.run(main())
"
```

Expected: `licenses`, `webhook_logs`, `schema_migrations` present, and 3 policies on `licenses`.

---

### Task 9: Migrate the 39 licences

**Files:**
- Create: `api/export_supabase.py`

**Interfaces:**
- Produces: a verified copy of the Supabase `licenses` rows in Railway Postgres.

Supabase is read over PostgREST because there is no `psql` client configured against it and no Supabase CLI installed. Service-role credentials are in `Supabase/.env` in the outer repo.

- [ ] **Step 1: Write the exporter**

Create `api/export_supabase.py`:

```python
"""One-shot export of Supabase licences to JSON, for loading into Railway.

Kept in the repo rather than run ad hoc so the migration is auditable after
the fact. Reads credentials from the environment; nothing is hardcoded.
"""

import json
import os
import sys
import urllib.request

COLUMNS = (
    "email,full_name,phone_number,country,license_key,sale_id,"
    "is_active,is_beta,has_completed_onboarding,last_login,created_at"
)


def main() -> int:
    base = os.environ["SUPABASE_URL"]
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]

    request = urllib.request.Request(
        f"{base}/rest/v1/licenses?select={COLUMNS}&order=created_at.asc",
        headers={"apikey": key, "Authorization": f"Bearer {key}"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        rows = json.load(response)

    json.dump(rows, sys.stdout, indent=2)
    print(f"\nexported {len(rows)} licences", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Export**

```bash
cd Server/api
set -a; . ../../Supabase/.env; set +a
python3 export_supabase.py > /tmp/dropbeats_licences.json
```

Expected on stderr: `exported 39 licences`. If the count is not 39, stop — the source changed since scoping and the plan needs revisiting.

- [ ] **Step 3: Load into Railway**

```bash
cd Server/api
railway run python3 -c "
import asyncio, asyncpg, json, os
rows = json.load(open('/tmp/dropbeats_licences.json'))
async def main():
    c = await asyncpg.connect(os.environ['DATABASE_URL'])
    for r in rows:
        await c.execute('''
            insert into licenses (email, full_name, phone_number, country,
                                  license_key, sale_id, is_active, is_beta,
                                  has_completed_onboarding, last_login, created_at)
            values (\$1,\$2,\$3,\$4,\$5,\$6,\$7,\$8,\$9,\$10::timestamptz,\$11::timestamptz)
            on conflict (license_key) do nothing
        ''', r['email'], r['full_name'], r['phone_number'], r['country'],
             r['license_key'], r['sale_id'], r['is_active'], r['is_beta'],
             r['has_completed_onboarding'], r['last_login'], r['created_at'])
    print('rows now:', await c.fetchval('select count(*) from licenses'))
    await c.close()
asyncio.run(main())
"
```

Expected: `rows now: 39`.

- [ ] **Step 4: Verify with a checksum, not just a count**

A matching row count does not prove the keys survived intact. Compare a checksum of the normalised keys on both sides.

```bash
cd Server/api
python3 -c "
import hashlib, json
rows = json.load(open('/tmp/dropbeats_licences.json'))
keys = sorted(k.upper().replace('-','').replace('_','') for k in (r['license_key'] for r in rows))
print('source:', hashlib.sha256('|'.join(keys).encode()).hexdigest())
"
railway run python3 -c "
import asyncio, asyncpg, hashlib, os
async def main():
    c = await asyncpg.connect(os.environ['DATABASE_URL'])
    keys = sorted(r['k'] for r in await c.fetch('select normalize_license_key(license_key) as k from licenses'))
    print('railway:', hashlib.sha256('|'.join(keys).encode()).hexdigest())
    await c.close()
asyncio.run(main())
"
```

Expected: the two hashes are identical. If they differ, do not proceed.

- [ ] **Step 5: Commit the exporter**

```bash
cd Server
git add api/export_supabase.py
git commit -m "chore: add one-shot Supabase licence exporter

Kept in the repo so the migration remains auditable. Credentials come from
the environment."
```

---

### Task 10: Deploy and verify in production

**Files:** none.

- [ ] **Step 1: Final check before pushing**

Pushing deploys to Railway, so verify once more that no yt-dlp code is about to ship to a datacenter IP:

```bash
cd Server
git log --oneline origin/main..HEAD
git diff origin/main..HEAD -- api/main.py | grep -c "stream-url\|song-info\|yt_dlp"
```

Expected: `0`. **If not zero, stop.**

- [ ] **Step 2: Push**

```bash
cd Server
git push origin main
```

If the session's permission classifier blocks the push, hand the command to the user rather than working around it.

- [ ] **Step 3: Watch the deploy**

Use the Railway MCP `list_deployments` and `get_logs` for service `bb57327f-838c-45ca-a067-7e9457d07ddf`. Expected in the logs: `✅ Licensing enabled (database pool ready)`.

- [ ] **Step 4: Verify search still works**

The whole point of one service is that licensing must not disturb search.

```bash
cd Server/api
python3 smoke_test.py
```

Expected: `SMOKE TEST PASSED`.

- [ ] **Step 5: Verify licensing against production with a real key**

Take any `license_key` from `/tmp/dropbeats_licences.json`:

```bash
B=https://dropbeats-server-production.up.railway.app
curl -s -X POST "$B/license/validate" \
     -H 'content-type: application/json' \
     -d '{"key":"<a real key from the export>"}'
```

Expected: `{"valid":true,...}` with the matching name and email.

- [ ] **Step 6: Cross-check against Supabase**

Supabase is still live and still authoritative for the shipped app. Both backends must agree on the same key before the app is ever repointed.

```bash
cd /Users/sudhanvaacharya/Desktop/Code-Projects/DropBeat-Stable-New
set -a; . ./Supabase/.env; set +a
curl -s -X POST "$SUPABASE_URL/rest/v1/rpc/validate_license" \
     -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
     -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
     -H 'content-type: application/json' \
     -d '{"p_license_key":"<the same key>","p_device_id":null}'
```

Expected: same `valid`, `name`, `email`, `country` as Railway returned.

- [ ] **Step 7: Verify an unknown key is rejected in production**

```bash
B=https://dropbeats-server-production.up.railway.app
curl -s -X POST "$B/license/validate" \
     -H 'content-type: application/json' -d '{"key":"TOTALLY-FAKE"}'
```

Expected: `{"valid":false,"error":"Invalid license key",...}`.

- [ ] **Step 8: Confirm the webhook path is not guessable**

```bash
B=https://dropbeats-server-production.up.railway.app
curl -s -o /dev/null -w "%{http_code}\n" -X POST "$B/webhooks/gumroad/guess"
```

Expected: `404`.

---

## Out of scope — the follow-up plan

These are **not** done by this plan and are written up separately once the above is verified in production:

- Rewriting `LicenseService.swift` against `URLSession` and deleting `SupabaseConfig.swift`.
- Removing the `supabase-swift` SPM dependency.
- The cold-launch lockout fix, with its 14-day offline grace window.
- Repointing the Gumroad webhook in the Gumroad dashboard.
- Deleting the Cloudflare Worker and the four Supabase edge functions.
- Deleting the drifted SQL files in `Supabase/`.
- Pausing the Supabase project after a final export.

The split is deliberate. When this plan finishes, Railway serves licensing correctly against real data while the shipped app still talks to Supabase, so nothing user-facing has changed and the new backend can be exercised at leisure. The cutover then becomes a single, reversible decision rather than a step buried in the middle of a long plan.
