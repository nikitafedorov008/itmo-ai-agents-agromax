# AGROMAX API

Hono/TypeScript, port `8787`. Production persistence is exclusively Supabase Postgres/Auth/Storage. There is no JSON-file or in-memory production fallback. All contract routes in `CONTRACT.md` are implemented, plus authenticated `GET /api/photos/:id` (binary). Unknown routes return JSON 404. JSON validation failures return 400; downstream provider failures return 502, timeouts 504; missing model configuration returns 503.

## Local run

From repository root with Docker running:

```sh
npm install
npx supabase start
npx supabase db reset
npx supabase status
cp apps/api/.env.example apps/api/.env
```

Populate `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` from the local Supabase status output, without committing them. Add provider keys only to this ignored file. `npm run dev:api` runs in the API workspace and loads `apps/api/.env` with Node's `--env-file-if-exists`. `npm run typecheck -w @agromax/api` and `npm run test -w @agromax/api` verify the API.

Local Auth disables email confirmation, enables anonymous sign-in and uses a 24-hour JWT for the MVP. Signup creates a chief role and a new empty farm. A chief can create a real field with `POST /api/fields {operationId,confirmed:true,name,crop,areaHa,center,boundary}`. `boundary:[]` records only the supplied center and invents no polygon; otherwise a simple valid contour of 3–200 points must contain the center. This uses the same atomic idempotency ledger as other mutations (`field.create` in sync). Demo uses anonymous Auth and creates a different persisted farm for every call, with three explicitly synthetic fields around Moscow. No shared demo account, user password or real-farm seed exists. Reuse the returned token to retain the session. Demo tokens have no membership in real farms. For hosted Supabase requiring confirmation, signup returns `{confirmationRequired:true,email}`; login after confirmation initializes the farm. Reauthentication obtains a fresh token; the v1 contract has no refresh-token flow.

## Database and atomic operations

`supabase/migrations/202610230001_core.sql` creates tenant tables, PostGIS boundaries, the private `field-photos` bucket, RLS, and checked security-definer RPCs. Authenticated clients can read only their farm; ordinary direct table writes are blocked. Domain requests use an individual validated JWT and an anon-key client, never the service role. The private background runner and agent finalization use the service key. Agent finalization accepts the user id verified by Auth, derives its farm in SQL and is not executable by authenticated or anonymous users; direct callers cannot forge conversation roles or model provenance. All domain record writes still use the user JWT. Chiefs can approve; both roles can record observations and complete tasks. Multi-user invitation/role management is outside the v1 contract; no API accepts an arbitrary role/farm id.

`apply_operation` wraps an observation upsert, approval with optional task, or completion in one Postgres transaction. Advisory locks serialize operation ids and new client-generated record ids; row locks and an expected version protect updates. Successful results are stored with an exact normalized payload fingerprint. An identical retry returns the original result even when the record has moved on. Reusing an operation id for a different payload returns `IDEMPOTENCY_MISMATCH` (409); stale versions and attempts to edit an approved record return 409 plus `current`. Unknown and cross-farm ids are 404. New observations emit notifications in the same transaction. Each `/sync` entry calls this transaction separately and reports applied/conflict/error; successful entries survive failure of other entries.

Photos are limited to JPEG/PNG/WebP, checked for MIME/signature and 10 MiB max, uploaded to a tenant-prefixed private object and registered under RLS. Registration checks that the exact tenant object exists, with the same MIME and valid size. Registration failure removes the uploaded object. Direct Storage deletion is denied for photos referenced by any observation. Retrieval checks the tenant metadata and Storage RLS, responds with private/no-store headers, and requires Bearer auth. Photos are never exposed as public URLs. The text-only agent does not claim to inspect their pixels.

`supabase/seed.sql` seeds only three curated FAO references. `supabase/rollback.sql` is an explicit destructive developer rollback; Storage objects must be removed through Storage API first. `supabase db reset` is the normal local clean-rebuild procedure. Do not execute rollback against production without a backup.

## Model agent

`DEEPSEEK_API_KEY` / `MIMO_API_KEY` are server-only. Defaults checked against official docs on 2026-10-23:

- [DeepSeek first API call](https://api-docs.deepseek.com/): `https://api.deepseek.com/chat/completions`, `deepseek-flash`.
- [Xiaomi MiMo OpenAI-compatible chat](https://mimo.mi.com/docs/zh-CN/api/chat/openai-api): `https://api.xiaomimimo.com/v1/chat/completions`, `mimo-v2.6-pro`.

Model/base URLs can be overridden via each provider's `_MODEL` and `_BASE_URL` environment variables. Requests use the OpenAI chat-completions tool protocol, thinking disabled, 2,000 max output tokens; DeepSeek uses JSON-object response format, MiMo uses plain text with strictly validated JSON content because JSON mode interferes with its tool calling, no streaming. Tool schema and model final JSON are validated by Zod; SQL also strictly checks JSON types and whitelisted keys for every mutation so direct RPC calls cannot bypass validation. Historical roles are filtered to user/assistant before a model call. The server permits at most four model calls and eight read-only tool calls total with a bounded total timeout (default 60 seconds, configurable 1–60 seconds). Each answer receives actual scoped field history and curated-source excerpts before the first model call; the model can then request additional read-only data. Tools: field history, field tasks, real Open-Meteo weather and seeded curated-source search. Field scope is bound by the server, not model arguments. Only source ids actually returned by the source tool can appear in reply sources. Tasks in artifacts must bind to the requested existing observation's exact id/version. Tool names/arguments, invalid JSON, invalid artifact bindings, unknown citations, errors and timeouts abort with a typed error; no invented completion or provider fallback exists.

The model never receives write tools and cannot approve or complete records. An artifact is only a proposal, and the server computes `requiresConfirmation` independently of the model. Separate confirmation endpoints require literal `confirmed:true` plus expected version and authenticated authorization. A user's confirmation phrase in chat never performs a domain write.

`agent_runs` persists each attempt and reserves operation ids before provider requests. Completed retries return the stored conversation/reply. Failed requests and interrupted pending requests never silently invoke the paid model twice; they require a new operation id after the user initiates a fresh attempt. Per-farm hourly quotas are atomically enforced across server replicas: 12 attempts for demo, 120 for real farms. Conversation append and completed run persistence are atomic, including concurrent turns. Errors store only an error code, not provider keys or raw upstream responses. Old in-flight runs are marked interrupted after five minutes by the scheduler.

## Background

Server starts an internal runner every `SCHEDULER_INTERVAL_MS` (minimum 10 seconds, default 60 seconds) only when `SUPABASE_SERVICE_ROLE_KEY` is present. There is no public cron endpoint. `run_scheduler` is executable by service role only, not authenticated/anonymous roles. It emits one overdue notification per task and one daily digest per tenant/day after 08:00 Europe/Moscow. Unique `(farm_id,dedupe_key)` protects against multiple workers, repeated ticks and restarts. A local non-overlap guard avoids running two ticks in one process. Notifications remain persisted and scoped by RLS; read marks update only the matching tenant. No push service is claimed by this MVP; clients receive them in bootstrap.

## Validation scope

`test/api.test.ts` injects a bounded test repository to verify route auth, confirmation, version/conflict/error transport, retry behavior, isolation handling, source/binding validation, read-only tools, provider failure, timeout, loop bounds, persistence calls and scheduler overlap prevention. SQL-level transaction/RLS/idempotency behavior must additionally be exercised against the real local stack; these unit tests do not prove Postgres/RLS correctness on their own.
