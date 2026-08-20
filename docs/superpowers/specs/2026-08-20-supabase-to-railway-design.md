# Migrating licensing from Supabase to Railway

Date: 2026-08-20
Status: awaiting review

## Goal

Consolidate DropBeats' licensing onto Railway, where the search backend already
runs and where the bill is already being paid. When this is done, Supabase and
the Cloudflare Worker are both switched off, and one Railway project holds the
whole server side.

## Non-goals

- User accounts, passwords, sessions, magic links. Licensing stays what it is
  today: a Gumroad key pasted once at onboarding, revalidated periodically.
- Device-bound seat limits. The `device_id` column and its checks were
  deliberately removed earlier; they stay removed.
- Moving `/stream-url` or `/song-info` to Railway. Those shell out to yt-dlp,
  which YouTube blocks from datacenter IPs. They remain bundled in the .app.

## Current state

**Railway** (`dropbeats-server-production.up.railway.app`) runs one FastAPI app
from the `DropBeats-Server` repo via Nixpacks. Endpoints, read from its live
OpenAPI schema:

```
/health  /search/{query}  /watch-playlist/{video_id}  /test-ytmusic
/playlist/{id}  /playlist/{id}/first-song  /playlist/{id}/refresh
```

Stateless, no database, no auth. In-memory caches only.

**Supabase** (`trtxfdsssreqhuajpvqk`) holds two tables and thirteen RPCs. The
macOS app calls three of them through the `supabase-swift` SDK:
`validate_license`, `deactivate_license`, `update_onboarding_status`.

**Cloudflare Worker** (`dropbeats-webhook-proxy`) receives the Gumroad sale
webhook and forwards it to Supabase using the service-role key.

### Live schema (source of truth)

Introspected over PostgREST on 2026-08-20. **The checked-in SQL files have
drifted and must not be trusted.** `Supabase/Webhook Logs and Table Handler`
inserts into `payment_provider`, `payment_id`, `amount`, `currency` and
`is_test`, none of which exist on the live table.

```
licenses:      id uuid, email text, full_name text, phone_number text,
               country text, license_key text, sale_id text,
               created_at timestamptz, device_id text, is_active bool,
               is_beta bool, has_completed_onboarding bool,
               last_login timestamptz, last_country text

webhook_logs:  id uuid, received_at timestamptz, payload jsonb,
               success bool, error text
```

### Two defects found while scoping

1. **The purchase pipeline is probably dead.** 39 licenses, all active, newest
   `2025-11-26`. `webhook_logs` has zero rows, even though the handler's first
   statement logs every inbound payload before any validation. Combined with the
   column mismatch above, the likely reading is that Gumroad sales have not been
   creating licenses. Needs confirmation against the Gumroad dashboard. Not
   caused by this migration, but the rebuild fixes it by construction.

2. **Cold-launch lockout.** `AppStateManager` initialises `licenseStatus` to
   `.unknown` and `licenseInfo` to `nil` on every launch, restoring neither from
   `UserDefaults`. The network-error fallback only preserves a licence already
   valid *in memory*, so on a cold launch that branch is unreachable and the app
   falls through to `.invalid`. Any licensing outage locks out every paying
   customer at their next restart. Fixed as part of this work.

## Target architecture

One Railway project, two services:

- **`dropbeats-server`** — the existing FastAPI app, extended with a licensing
  router.
- **`Postgres`** — new Railway Postgres instance, reachable only over the
  project's private network.

```
macOS app ──HTTPS──> dropbeats-server ──private──> Postgres
Gumroad   ──HTTPS──> dropbeats-server (secret webhook path)
```

The Cloudflare Worker and all four Supabase edge functions are deleted.

### Code layout

`Server/api/main.py` is ~760 lines already mixing search, playlists and the
bundled-only yt-dlp endpoints. Licensing goes in new modules rather than growing
it further:

- `api/db.py` — asyncpg pool, lifecycle bound to FastAPI startup/shutdown.
- `api/license.py` — `APIRouter` with the licensing endpoints and their logic.
- `api/migrations/` — plain numbered `.sql` files, applied by a small runner.

### The bundled-app constraint

`main.py` is also what runs inside the .app on port 4002. It must not require
asyncpg or a database there. Therefore:

```python
if os.getenv("DATABASE_URL"):
    from license import router as license_router   # import inside the branch
    app.include_router(license_router)
```

Railway sets `DATABASE_URL`; the bundled app does not, so it never imports the
DB layer. `bundle_python.sh` needs no new dependencies. A startup log line states
which mode the process is in, so the app log makes it obvious.

## Data model

The schema carries over as-is, minus the thirteen RPCs. Two changes:

- Drop `device_id` and `last_country`. Both are dead — `device_id` is never
  written and `last_country` is never read.
- Add `updated_at timestamptz`, maintained by a trigger.

Indexes on `email` and on `normalize_license_key(license_key)`. The second is
the one that matters: validation looks keys up *normalised*, so a plain index on
`license_key` cannot serve it. Today's code has no such index and does a
sequential scan — invisible at 39 rows, worth fixing while we are here.

`normalize_license_key` (upper-case, strip `-` and `_`) stays in SQL as an
`IMMUTABLE` function, because the index expression depends on it.

### RLS

Worth stating plainly what this buys. Under Supabase the app talks straight to
Postgres with an anon key compiled into the binary, so row policies *are* the
security boundary. With FastAPI in front, only the API holds credentials and the
boundary becomes the endpoint logic. RLS becomes containment for a
SQL-injection bug or a leaked `DATABASE_URL` — real, but secondary. It is only
worth implementing in its least-privilege form; `ENABLE ROW LEVEL SECURITY` with
a `USING (true)` policy is theatre.

- Migrations run as the Postgres owner role. The application never does DDL.
- The app connects as `dropbeats_app`, which owns nothing.
- Both tables get `ENABLE` **and** `FORCE ROW LEVEL SECURITY`, so the owner is
  subject to policies too.
- `dropbeats_app` gets `SELECT, INSERT, UPDATE` on `licenses` and `INSERT` on
  `webhook_logs`. No `DELETE` anywhere, no `UPDATE` on `webhook_logs` — the
  audit log is append-only at the privilege level.
- The `SELECT` policy on `licenses` is unrestricted for `dropbeats_app`. An
  earlier draft scoped it to `is_active = true`, which is wrong: validation has
  to tell "unknown key" apart from "License is not active" to preserve today's
  error messages, and a policy that hides inactive rows collapses the two. The
  containment value here comes from the grants — no `DELETE`, no `UPDATE` on the
  audit log — not from row filtering.

## Endpoints

All under `/license`, plus the webhook. Responses keep today's JSON field names
so the Swift decoders need no reshaping.

| Method | Path | Purpose |
|---|---|---|
| POST | `/license/validate` | `{key}` → `{valid, name, email, country, created_at, has_completed_onboarding, error}` |
| POST | `/license/deactivate` | `{key, email}` → `{success, error}` |
| POST | `/license/onboarding` | `{key, completed}` → `{success, error}` |
| POST | `/webhooks/gumroad/{secret}` | Gumroad sale notification |

Behaviour carried over from the plpgsql, minus the debris (`raise notice` of
every key in the table on every call, `format()`+`execute` string-built SQL, the
dead `p_device_id` parameters, and the `debug_license` / `test_key_matching`
scaffolding, none of which are ported):

- Keys are compared normalised.
- Unknown key → `{valid: false, error: "Invalid license key"}`.
- Inactive licence → `{valid: false, error: "License is not active"}`.
- Successful validation updates `last_login`.

**Auth.** `/license/validate` is public and rate-limited — the licence key is
itself the secret, exactly as today, minus the extractable anon key. The webhook
is protected by two independent factors: an unguessable path segment from
`GUMROAD_WEBHOOK_SECRET`, and verification of `seller_id` against
`GUMROAD_SELLER_ID`. Both live in Railway variables, neither in the repo.

Rate limiting is in-process (per-IP token bucket on the validate endpoint).
Adequate for one instance; if the service ever scales horizontally this needs
revisiting.

### Webhook behaviour

The current handler inserts unconditionally, so a Gumroad retry would duplicate
a licence. The rebuild upserts on `sale_id`, making retries idempotent. Every
inbound payload is logged to `webhook_logs` before validation — that part of the
original design was right and is kept.

## macOS app changes

- Delete `Config/SupabaseConfig.swift`.
- Rewrite `Services/LicenseService.swift` against `URLSession`. Same three public
  methods, same return types; only the transport changes.
- Remove the `supabase-swift` SPM dependency from the project.
- Add `licenseBaseURL` to `BackendConfig`, alongside `searchBaseURL` and
  `streamBaseURL`. Per the repo's own convention, call sites do not learn
  which backend serves what.

### Cold-launch fix

On a successful validation, persist to `UserDefaults`: validity, a
`lastSuccessfulValidation` timestamp, and the `LicenseInfo` fields. On launch,
restore that state *before* the first network call, so the app starts in
`.valid` rather than `.unknown` when it has previously validated.

Then apply a grace window: if the last success is under 14 days old, a network
failure leaves the licence valid. Past 14 days offline, fall through to today's
behaviour and demand a live check. An explicit `valid: false` from the server
still invalidates immediately — the distinction between "server says no" and
"cannot reach server" is the one piece of the current logic that is correct and
must be preserved.

## Migration and cutover

1. Provision Railway Postgres; set `DATABASE_URL` (private network),
   `GUMROAD_WEBHOOK_SECRET`, `GUMROAD_SELLER_ID`.
2. Apply migrations: schema, roles, RLS policies.
3. Export the 39 licences from Supabase over PostgREST (no psql on this
   machine); load into Railway; verify row count and a checksum of normalised
   keys on both sides.
4. Deploy the extended service. Verify `/health` still passes and the search
   endpoints are unaffected.
5. Validate a known-good key against Railway while Supabase is still live.
   Both must return the same answer.
6. Repoint the Gumroad webhook to the Railway URL. **Manual step in the Gumroad
   dashboard — cannot be automated from here.** Send a test sale and confirm a
   row lands in `webhook_logs` and a licence is created.
7. Ship the DMG with the new `LicenseService`.
8. Delete the Cloudflare Worker.
9. Keep a `pg_dump`-equivalent JSON export of both tables in a private location,
   then pause the Supabase project. Do not delete it for 30 days.

Existing installs are hard-wired to Supabase and break at step 9. This is an
accepted decision: the user will issue coupon codes to anyone who emails, and
the 39 rows are carried over so that any existing customer who downloads the new
build simply works.

## Testing

There is no test suite in this repo and no linter; verification is by exercising
the service. Following the pattern `Server/api/smoke_test.py` already
establishes, add `Server/api/license_smoke_test.py`: boot the app against a
throwaway database, then assert across a seeded fixture set.

- Valid key returns `valid: true` and the expected profile fields.
- Unknown key returns `Invalid license key`.
- Deactivated licence returns `License is not active`.
- Keys differing only in case, dashes or underscores all resolve to one licence.
- Onboarding flag round-trips.
- Webhook with a wrong `seller_id` is rejected and logged.
- Webhook replayed twice creates exactly one licence.
- `dropbeats_app` is refused a `DELETE` on `licenses` — asserts RLS and grants
  are actually in force, rather than assuming the migration applied.

The Swift side has no test target, so the cold-launch fix is verified manually:
validate once, kill the app, take the network down, relaunch, confirm the app
stays licensed; then set the stored timestamp beyond the grace window and
confirm it demands a live check.

## Risks

| Risk | Mitigation |
|---|---|
| Old installs lock out at cutover | Accepted. Coupon codes; data carried over so the new build works. |
| Railway becomes a single point of failure for licensing | The 14-day grace window means an outage is invisible to users. |
| Repo SQL has drifted from live schema | Live introspection is the source of truth; drifted files are deleted, not ported. |
| Gumroad pipeline may already be broken | Confirm against the Gumroad dashboard before cutover, so a pre-existing fault is not misread as a regression. |
| DB import loses or mangles rows | Row count plus normalised-key checksum compared on both sides before Supabase is paused. |
| Adding a DB layer breaks the bundled app | The router is registered only when `DATABASE_URL` is set, with the import inside that branch. Covered by launching the built .app and confirming playback. |

## Prerequisites before implementation

1. **Railway account.** The CLI and MCP on this machine are authenticated as
   `llm.experiments@scaler.com`, which has no DropBeats project. Needs
   `railway logout && railway login` against the account that owns
   `dropbeats-server-production`, then `railway link`.
2. **Rotate Railway tokens.** Access and refresh tokens for all three cached
   profiles were printed to a session transcript on 2026-08-20 in error.
3. **Gumroad dashboard access**, to confirm whether sales have occurred since
   2025-11-26 and to repoint the webhook at cutover.
4. **`workflow` scope on the GitHub token**, unrelated to this migration but
   still blocking `refresh-extractors.yml`.
