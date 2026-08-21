# Client cutover to Railway, behind a Cloudflare proxy

Date: 2026-08-21
Status: awaiting review
Follows: `2026-08-20-supabase-to-railway-design.md` (backend, shipped)

## Goal

Move the macOS app off Supabase and onto the Railway licensing backend that is now
live — and route every app→backend call through a Cloudflare Worker, because
Jio blocks Railway.

## The discovery that reshapes this

Jio blocking Railway is not a licensing problem. `BackendConfig.searchBaseURL`
points straight at `dropbeats-server-production.up.railway.app`, so for users on
Jio **search and autoplay are already broken today** — this predates all the
licensing work and has nothing to do with it.

Two consequences:

1. The proxy is not something licensing needs; it is an existing outage for a
   segment of paying users, and fixing it is the more valuable half of this work.
2. Pointing the rewritten `LicenseService` at Railway directly would ship a third
   broken feature to the same users. Licensing must go through the proxy from the
   start.

The Cloudflare Worker therefore changes role: from a Gumroad webhook forwarder
(a job it no longer has — Gumroad posts to Railway directly now, verified with a
live ping on 2026-08-21) to a reverse proxy fronting the whole API.

## Non-goals

- Moving `/stream-url` or `/song-info`. They run on `127.0.0.1:4002` inside the
  app and never touch the network path this document is about.
- Caching, request coalescing, or edge logic in the Worker. It forwards and
  returns. Anything cleverer is a later decision.
- User accounts. Licensing stays a Gumroad key, as settled previously.

## Architecture

```
macOS app ──HTTPS──> Cloudflare Worker ──HTTPS──> Railway ──private──> Postgres
                     (workers.dev)                (search + licensing)

Gumroad   ──HTTPS──────────────────────────────> Railway   (direct; not on Jio)
macOS app ──localhost:4002──> bundled Python     (yt-dlp; unchanged)
```

### The Worker

A single reverse proxy. For any request it receives:

- Rebuild the URL against the Railway origin, preserving path and query.
- Forward method, headers and body unchanged, minus hop-by-hop headers.
- Return the origin's status, headers and body unchanged.

**The one detail that must not be got wrong:** the Worker has to send the real
client IP as `X-Forwarded-For`, taken from Cloudflare's `CF-Connecting-IP`.
The backend's rate limiter keys on the leftmost `X-Forwarded-For` entry and falls
back to the peer address. If the Worker omits it, every user in the world collapses
into a single bucket at the Railway end — 30 validations then one per two seconds,
globally. That is exactly the bug the backend work already found and fixed once,
and proxying without this header reintroduces it one layer up.

Origin stays `https://dropbeats-server-production.up.railway.app`, in a Worker
variable rather than a literal, so it can be repointed without a code edit.

### The app

- `BackendConfig` gains `licenseBaseURL`; `searchBaseURL` moves to the Worker.
  Call sites do not learn which backend serves what — that is the file's existing
  convention and it holds here.
- `LicenseService` is rewritten against `URLSession`: same three public methods,
  same return types, only the transport changes. `SupabaseConfig.swift` is deleted
  and the `supabase-swift` SPM dependency removed.
- `SearchServerKeepAlive` pings through the Worker, since that is now the path
  whose warmth matters.

Request/response shapes are fixed by the deployed backend and the existing Swift
decoders: `POST /license/validate` `{key}`, `/license/deactivate` `{key,email}`,
`/license/onboarding` `{key,completed}`.

Two response shapes the current client does not expect and must handle as
**transport errors, not licence verdicts**:

- `429` `{"detail": "Too many requests"}` from the rate limiter.
- `503` `{"detail": "Licensing temporarily unavailable"}` when the pool is down.

Decoding either as a licence answer would turn a transient blip into a lockout.

### Cold-launch fix

Carried over unchanged from the previous spec, and now more load-bearing, because
after cutover the whole chain — Worker, Railway, Postgres — sits between a user
and their licence.

`AppStateManager` initialises `licenseStatus` to `.unknown` and `licenseInfo` to
`nil` on every launch and restores neither, so its network-error fallback is
unreachable on a cold start and the app falls through to `.invalid`.

Fix: persist validity, a `lastSuccessfulValidation` timestamp and the
`LicenseInfo` fields on every successful validation; restore them before the first
network call; and allow a 14-day offline grace window during which a network
failure leaves the licence valid. An explicit `valid: false` from the server still
invalidates immediately — the distinction between "server says no" and "cannot
reach server" is the one piece of the current logic that is correct.

## Cutover

1. Rebuild the Worker as a proxy; deploy; verify it serves `/health`, `/search`
   and `/license/validate` identically to Railway, and that `X-Forwarded-For`
   arrives correctly.
2. Repoint the app at the Worker, rewrite `LicenseService`, drop the Supabase
   dependency, add the cold-launch fix.
3. Ship the DMG.
4. Leave Supabase running. Old installs still depend on it, and it costs nothing
   to leave up.
5. Retire Supabase once traffic to it stops — or accept the coupon-code fallback
   already agreed for stragglers.

Note the asymmetry that exists **right now**: purchases since 2026-08-21 land only
in Railway, while shipped apps validate only against Supabase. Every day before
step 3 is a day a new customer holds a key their app cannot verify. This is the
argument for shipping the DMG promptly rather than batching more work into it.

## Risks

| Risk | Mitigation |
|---|---|
| The `workers.dev` URL gets compiled into the DMG, recreating exactly the Supabase lock-in this project is escaping | Accepted for now, explicitly. A custom domain would fix it permanently for ~$10/yr and is the recommended follow-up. |
| Jio (or another ISP) later blocks `workers.dev` too | Same fix: a custom domain, repointable without a new DMG. |
| Worker becomes a single point of failure for search as well as licensing | Cloudflare's availability is far better than the status quo for Jio users, who currently have no service at all. |
| Missing `X-Forwarded-For` collapses the rate limiter | Explicit requirement above, with a test that asserts the header arrives at the origin. |
| Free-tier Worker limit (100k requests/day) | At ~40 licences and a handful of calls per session, this is orders of magnitude clear. Worth an alert if the install base grows. |
| Added latency on every search | One extra hop, Cloudflare-to-Railway. Measure before and after; abandon the proxy for search only if it proves material, which is unlikely. |

## Prerequisites

1. **Wrangler is broken locally.** `npx wrangler` fails with a workerd platform
   mismatch (`@cloudflare/workerd-darwin-arm64` present but rejected — the classic
   symptom of a copied or moved `node_modules`). Needs
   `rm -rf node_modules package-lock.json && npm install` before anything can be
   deployed.
2. **The Worker's `workers.dev` hostname must be confirmed** — it gets baked into
   the shipped app, so it has to be right the first time.
3. **A Jio connection to verify against.** Every claim in this document about what
   Jio does or does not block is the user's report; none of it is testable from
   this machine, and shipping a DMG on an unverified assumption is the main way
   this work fails.
