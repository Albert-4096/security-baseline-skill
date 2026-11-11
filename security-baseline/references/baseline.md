# The Vibe-Coding Security & Architecture Baseline

**Version 1.1 — November 2026**
Standing reference for any AI-assisted project: services, websites, dashboards, internal tools, client work.

---

## 0. How to use this document

This is not a document to read once. It has four operating modes:

| When | What you use |
|---|---|
| **Starting a project** | §2 — paste the Agent Constitution into `AGENTS.md` / `CLAUDE.md` / the Lovable system prompt. Pick your stack from §3. |
| **While building** | §4–§13 as reference. Grep for the subsystem you're touching. |
| **Before every deploy** | §16 — the Pre-Launch Gate. Nothing ships red. |
| **After something breaks** | §17 — incident checklist. |

**Threat tiers.** Not every project deserves the same rigour. Classify first, then apply:

- **T0 — Toy.** No real users, no real data, localhost or a private subdomain behind SSO. Apply §2 and §8 (secrets) only.
- **T1 — Public, no accounts.** Marketing site, portfolio, public dashboard. Apply T0 + §10 (frontend/headers) + §9 (supply chain).
- **T2 — Public with accounts / user data.** Anything with a login. Apply everything. This is the default for client work.
- **T3 — Money, PII at scale, or regulated data.** T2 + external review before launch, plus §14 (compliance) taken seriously.

The failure mode to avoid: building a T2 system with T0 discipline because it started as a weekend prototype. Prototypes become production. Decide the tier on day one and revisit it every time you add a feature.

---

## 1. The core mental model

### 1.1 Why vibe-coded systems fail

The model is not writing bad code. The model is writing code that satisfies the request — and security is almost never part of the request. "Build me a dashboard where users can see their invoices" contains no instruction to check that user A can't fetch user B's invoice by changing an ID. So that check doesn't get written.

Three compounding effects:

1. **Training-data averaging.** Generated code reflects the average of public code, including a decade of insecure patterns that were normal before better alternatives existed. Roughly 40–45% of AI-generated code in independent studies contains at least one exploitable weakness, most mapping to the CWE Top 25.
2. **Removed friction.** Code review, writing tests, documenting decisions — that friction is where mistakes get caught. When you can rebuild a whole feature by editing a prompt, the incentive to read the diff disappears.
3. **Automation complacency.** After the model is right ten times, you stop checking the eleventh. Studies consistently find that developers using AI assistants *rate their own code as more secure* than developers who wrote it by hand — regardless of whether it actually is.

### 1.2 The three laws

Everything in this document is a consequence of three rules. If you remember nothing else:

> **1. Never trust the client.** Anything running in a browser — validation, role checks, hidden UI, disabled buttons, "admin only" routes — is a suggestion, not a control. The real check happens server-side, every time, on every request.
>
> **2. Never trust the model.** Generated code is a draft by a fast contractor with no knowledge of your threat model. Every auth path, every query, every dependency name is unverified until you verify it.
>
> **3. Never trust defaults.** Frameworks, databases, and hosting platforms optimise their defaults for a working demo, not a secure deployment. RLS off, CORS `*`, debug on, no rate limit, admin UI on a public port — these are all *defaults* somewhere.

### 1.3 The one question that catches the most bugs

For every endpoint, query, and mutation, ask:

> *"If I take this exact request, change the ID to someone else's, and send it with a valid token from a different account — what happens?"*

If the answer isn't "403 before any data is touched," you have the #1 vulnerability class in the world (OWASP A01) sitting in your app. This is the single highest-yield test you can run manually, and AI-generated code fails it constantly.

---

## 2. The Agent Constitution

Paste this into `AGENTS.md` / `CLAUDE.md` / `.cursorrules`, or the top of your Lovable/Bolt system prompt. Trim it to the stack you're using. Security prompting measurably reduces the vulnerability rate in generated code — it doesn't eliminate it, so this supplements review rather than replacing it.

```markdown
# Project Constitution — read before generating any code

## Non-negotiables
1. Authorization is enforced server-side on EVERY request. Never rely on
   hidden UI, client-side route guards, or middleware alone.
2. Every DB query that touches user-owned data filters by the authenticated
   principal's ID from the server-side session — never from a request body,
   query param, or header the client controls.
3. All external input is validated against an explicit schema (Zod/Pydantic)
   at the boundary. Allow-list, not block-list. Reject unknown fields.
4. Parameterized queries only. Never build SQL/NoSQL/shell/LDAP strings by
   concatenation or template interpolation.
5. No secret is ever written into source, committed, logged, or sent to the
   client. Secrets come from env vars at runtime.
6. Errors returned to clients are generic. Stack traces, SQL text, internal
   paths, and library versions never leave the server.
7. Fail closed. If an authz check, a token parse, or an external call errors,
   deny the request. Never `catch { return next() }`.

## Dependencies
- Prefer the standard library and packages already in the lockfile.
- Before adding ANY new dependency: state its name, why it's needed, and
  confirm it exists on the registry with real download volume and recent
  releases. If you are not certain the package exists, say so — do not guess.
- Never add a dependency to solve something a few lines of code would.

## Output requirements
- After generating any endpoint, list: the authz check, the input schema,
  the rate limit, and what is logged. If any is missing, say so explicitly.
- Flag anything you generated that you are not confident is secure.
- Do not silently "fix" a failing authorization check by removing it or
  broadening a policy. Explain the failure instead.

## Style
- TypeScript strict mode. No `any` on data crossing a trust boundary.
- Server code and client code live in clearly separated directories.
```

**Add per-project:** the threat tier, the tenancy model (single-tenant / row-level multi-tenant / schema-per-tenant), and the list of roles with what each may do. Ambiguity about roles is where authorization bugs are born.

### 2.1 Prompts that earn their keep

- **Adversarial pass** (run after every feature, in a *fresh* context so the model isn't defending its own work):
  > *"You are a penetration tester reviewing this code for a bug bounty. Ignore that it works. Enumerate every way a logged-in user could access or modify data belonging to another user, escalate privileges, or cause the server to make requests on their behalf. For each, give the exact HTTP request that exploits it."*
- **Threat model before building:**
  > *"Before writing code: list the trust boundaries in this feature, what data crosses each, who the principals are, and the three most likely abuse cases."*
- **Dependency justification:**
  > *"List every third-party package this change adds, direct and transitive, and what each is used for."*

Feed the output of your scanner (§15) back into the model as context. Scanner + structured self-review catches materially more than either alone.

---

## 3. Stack defaults

Choosing boring, well-trodden components is a security decision. Obscure frameworks have fewer eyes on them, fewer secure examples in training data, and worse generated code.

### 3.1 Frontend

| Layer | Default | Why |
|---|---|---|
| Framework | **Next.js (App Router)** or **Vite + React** for pure SPA | Largest secure-example corpus; SSR lets you keep secrets and authz server-side |
| Language | **TypeScript, strict** | Catches a real class of bugs; makes schema-derived types free |
| Styling | **Tailwind** | No runtime, no CSS injection surface |
| Components | **shadcn/ui** (copied into repo, auditable) over heavy UI libs | You own the code; no opaque dependency tree |
| Forms | **react-hook-form + Zod** | Same schema reused server-side — one source of truth |
| Data fetching | **TanStack Query** (SPA) or Server Components / Server Actions (Next) | Avoids hand-rolled fetch/cache bugs |
| Charts | **Recharts** (simple) / **visx** or **ECharts** (dense dashboards) | Avoid anything requiring `innerHTML` for labels |
| Tables | **TanStack Table** | Headless; you control rendering and escaping |
| Rich text | **Tiptap** + server-side sanitisation (DOMPurify) | Never trust client sanitisation alone |

**Next.js-specific traps:**

- **Middleware is not an authorization boundary.** CVE-2025-29927 let attackers skip Next.js middleware entirely with a single spoofed `x-middleware-subrequest` header, bypassing every auth check that lived there. The lesson outlives the patch: middleware is for redirects, locale, and cheap early rejection. The authoritative check goes *inside* the route handler / server action / data-access function.
- **`NEXT_PUBLIC_` inlines the value into the browser bundle.** Anything with that prefix is public forever. Grep for it before every deploy.
- **Server Actions are public HTTP endpoints.** They get an obfuscated ID, not authentication. Every action starts with a session check and input validation. "It's only called from a form the admin sees" is not a control.
- **Keep `next` patched.** It has had multiple auth-relevant CVEs; subscribe to the advisories.

### 3.2 Backend

| If you want… | Use | Notes |
|---|---|---|
| One codebase, fastest path | **Next.js route handlers / server actions** | Fine up to real load; beware conflating UI and API concerns |
| A real, separable API | **Fastify (TS)** or **FastAPI (Python)** | Both schema-first; FastAPI gives OpenAPI + Pydantic validation free |
| Heavy data / ML adjacency | **FastAPI + Pydantic v2** | Matches the Python data/ML ecosystem |
| Long-running / queue work | **BullMQ (Redis)** or **Celery** | Never do slow work in the request path |
| Automation glue | **n8n** (see §12) | Great for orchestration, dangerous as an unguarded ingress |

**Database:** PostgreSQL, always, unless there's a specific reason not to. It gives you row-level security, JSONB, full-text search, `pgvector`, and Apache AGE if you need graphs — one system instead of four.

**ORM:** Drizzle (TS) or SQLAlchemy 2.x / Prisma. All parameterize by default. The danger is the raw-SQL escape hatch — `sql.raw()`, `$queryRawUnsafe`, `text()` with f-strings. Grep for those names in every review; they are where injection lives in an otherwise safe codebase.

**Auth — do not build this.** Pick one and use it as designed:

| Option | Best for | Watch out for |
|---|---|---|
| **Authentik** (self-hosted) | Internal tools, client dashboards, anything on your infra | Keep it patched; it holds every identity you have |
| **Better Auth / Auth.js** | Next.js apps where you want to own the DB | You still own session security — read the hardening docs |
| **Supabase Auth** | Supabase-backed apps | RLS is what makes it safe (§7) |
| **Keycloak** | Enterprise client requirements | Heavy; only when the client asks for it |

Never store passwords with anything but **argon2id** (preferred) or **bcrypt** at a current work factor. If generated code reaches for SHA-256, MD5, or a hand-rolled salt scheme, delete it.

### 3.3 Hosting and deployment

For a self-hosted, auditable setup:

- **Own infra:** Docker Compose per project → reverse proxy (Nginx Proxy Manager / Caddy / Traefik) → TLS via Let's Encrypt → SSO in front of anything internal. Compose files in git, secrets not.
- **Client-facing production where uptime is contractual:** consider managed (Hetzner + Coolify/Dokploy is the cost-conscious middle ground; it keeps you self-hosted with a deploy pipeline).
- **Static/marketing:** any static host is fine; the attack surface is headers and dependencies.

**Never on the public internet without auth in front:** database ports, Redis, admin UIs (n8n, Portainer, Grafana, Proxmox, pgAdmin), `/actuator`, `/debug`, `.git`, `.env`, backup dumps. Assume everything is scanned within hours of exposure — because it is.

---

## 4. API design and security

This section applies whether the "API" is a set of Next.js route handlers, a FastAPI service, or a productised endpoint you sell access to.

### 4.1 Design rules

**Spec first.** Write the OpenAPI schema (or the Zod/Pydantic models that generate it) before the implementation. It gives you: generated types, generated validation, generated docs, and a contract the model can't drift from. It also forces you to enumerate every endpoint — which is how you avoid shadow endpoints nobody remembers (OWASP API9).

**Versioning.** `/v1/` in the path from day one. Retiring `/v1` later is a business decision; adding it later is a migration.

**Resource naming.** Plural nouns, no verbs: `GET /v1/invoices`, `POST /v1/invoices`, `GET /v1/invoices/{id}`. Verbs in paths (`/getInvoice`, `/doExport`) are a smell that authorization is ad hoc.

**IDs.** Use UUIDv7 or ULID, not sequential integers. Sequential IDs make enumeration trivial and turn one authorization bug into a full database dump. This is defence in depth, *not* a substitute for the ownership check — never treat an unguessable ID as authorization.

**Status codes that don't leak.** `404` for "exists but you may not see it" and for "doesn't exist" — identical responses. Returning `403` for one and `404` for the other is an oracle that lets an attacker enumerate what exists.

**Pagination is mandatory** on every collection endpoint. Cursor-based, with a hard server-side max page size. An unbounded `GET /users` is both a data-exposure and a denial-of-service bug.

### 4.2 Authentication

- **Session cookies** for first-party web apps: `HttpOnly`, `Secure`, `SameSite=Lax` (or `Strict`), server-side session store, rotation on privilege change, absolute + idle expiry. Prefer this over JWT-in-localStorage for anything with a browser front end — localStorage is readable by any XSS.
- **JWTs** only when you actually need stateless cross-service auth. If you use them: pin the algorithm server-side (reject `alg: none` and algorithm confusion), short expiry (≤15 min) with refresh rotation, and a revocation story. "We'll add revocation later" means "compromised tokens are valid until expiry, forever."
- **API keys** for machine-to-machine: long random, prefixed for identification (`acme_live_…`), stored as a hash (never plaintext), scoped, rotatable, with last-used timestamps.
- **MFA** on anything administrative. TOTP at minimum; passkeys/WebAuthn if the audience tolerates it.
- **Rate-limit the auth endpoints specifically** — login, signup, password reset, OTP verify — per-IP *and* per-account. Generic API rate limiting is not credential-stuffing protection.
- **Uniform responses on login failure and password reset.** "No such user" vs "wrong password" is a user-enumeration API.

### 4.3 Authorization — the part that actually breaks

Three failure modes, all top-5 OWASP API risks, all classic AI-generated-code bugs:

**BOLA (object level).** `GET /v1/invoices/{id}` returns the invoice without checking it belongs to the caller. Roughly 40% of observed API attacks. The fix is not "check in the handler" — it's structural:

```ts
// Bad: authorization is optional, developer must remember
const invoice = await db.invoice.findUnique({ where: { id } });

// Better: ownership is part of the query, unavoidable
const invoice = await db.invoice.findFirst({
  where: { id, orgId: session.orgId },   // from server session ONLY
});
if (!invoice) return notFound();          // same response as "doesn't exist"
```

Best of all: a **data access layer** that physically cannot be called without a principal. Every query goes through `withAuth(session).invoices.get(id)`. If the only path to the database requires a session, the model can't generate a query that forgets one.

**BFLA (function level).** `POST /v1/admin/users` is reachable by a normal user because the route was never role-gated — the button was just hidden in the UI. Gate by role at the route level *and* assert inside the handler. Deny by default: unknown route + unknown role = 403.

**BOPLA (property level).** Two halves:
- *Over-exposure:* the handler returns the whole DB row — `password_hash`, `stripe_customer_id`, `internal_notes`, `is_admin`. Never serialize entities directly. Define an explicit response DTO/schema listing exactly the fields that go out. `return user` is a bug; `return UserPublic.parse(user)` is not.
- *Mass assignment:* `PATCH /v1/users/me` with `{"is_admin": true}` works because the handler spreads the request body into the update. Validate against a schema with `.strict()` and an explicit field allow-list. Never `{...req.body}` into a write.

### 4.4 Input validation and injection

- One schema per endpoint, parsed at the boundary, before any logic. Nothing downstream accepts unvalidated types.
- Validate: type, length, format, range, enum membership. Reject unknown properties.
- Parameterized queries everywhere. Never interpolate into SQL, shell commands, file paths, or regexes.
- **Path traversal:** any user-supplied filename gets normalised and confirmed to resolve inside the intended directory. `../../etc/passwd` is still, in 2026, a working attack against freshly generated file-download handlers.
- **SSRF** (now folded into OWASP A01): if your API fetches a user-supplied URL — webhook testing, image import, "fetch metadata from this link" — enforce an allow-list of schemes and hosts, resolve DNS and block private/link-local ranges (10/8, 172.16/12, 192.168/16, 127/8, 169.254.169.254, IPv6 equivalents), disable redirects or re-validate each hop, and set a tight timeout. A cloud metadata endpoint is one careless fetch away from your credentials.
- **File uploads:** validate by content sniffing, not extension or client-supplied MIME; cap size; generate a new random filename; store outside the web root or in object storage; serve from a separate domain with `Content-Disposition: attachment` and `X-Content-Type-Options: nosniff`; scan if you accept documents from strangers.

### 4.5 Rate limiting, quotas, and abuse

- Global per-IP limit at the edge (reverse proxy / Cloudflare) **and** per-principal limits in the app. Edge-only limits fall to distributed abuse; app-only limits let junk traffic reach your runtime.
- Tighter limits on expensive endpoints: search, export, report generation, anything calling an LLM or a paid third-party API.
- Return `429` with `Retry-After`. Publish limits in your docs if you sell the API.
- **Cost-based limiting** for anything that spends money per request (LLM tokens, SMS, third-party lookups). Count credits, not requests. An unmetered LLM endpoint is a way for a stranger to spend your budget.
- **Idempotency keys** on any POST that creates a paid or irreversible object. Client sends `Idempotency-Key`, server stores the result for 24h and replays it on retry.
- **Business-flow abuse** (OWASP API6): the endpoint works exactly as designed, and that's the problem — bulk-buying limited inventory, scraping your whole catalogue one legitimate request at a time, mass account creation. Defend at the flow level: device fingerprinting, velocity checks, human verification on sensitive flows.

### 4.6 Webhooks

**Outbound** (you calling a client's URL): sign the payload with HMAC-SHA256 over `timestamp + body`, send in a header, document the verification. Retry with exponential backoff and a dead-letter queue. Treat the destination URL as SSRF-relevant (§4.4).

**Inbound** (someone calling you): verify the signature *before parsing the body*, using a timing-safe comparison. Reject timestamps older than ~5 minutes to stop replays. Store processed event IDs for deduplication. Never trust an `event.type` field to decide privilege.

```ts
const raw = await req.text();                       // raw body, pre-JSON
const expected = crypto.createHmac('sha256', secret)
  .update(`${ts}.${raw}`).digest('hex');
const a = Buffer.from(expected), b = Buffer.from(sig ?? '');
if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return 401;  // timingSafeEqual throws on unequal length
if (Math.abs(Date.now()/1000 - Number(ts)) > 300) return 401;
```

### 4.7 If you're selling the API

Relevant to a productised, monetisable endpoint:

- Key issuance, scoping, rotation, and revocation in the dashboard from v1 — retrofitting is painful.
- Per-key quotas enforced *before* the expensive work happens, not in a nightly reconciliation.
- Usage metering that you'd be willing to show a customer during a billing dispute: request ID, timestamp, endpoint, units consumed, response code.
- Publish an OpenAPI spec, a status page, a changelog, and a deprecation policy. B2B buyers evaluate these before they evaluate your output quality.
- Separate the free tier by capability, not just volume — free tiers throttled only by volume attract exactly the abuse you don't want.

---

## 5. OWASP Top 10 (2025) — mapped to what vibe coding actually produces

The 2025 edition (finalised January 2026) reordered things in ways that matter here: misconfiguration jumped to #2, supply chain entered at #3, and error handling entered at #10. All three are *exactly* where AI-assisted development is weakest.

| # | Category | How it shows up in a vibe-coded app | The fix |
|---|---|---|---|
| **A01** | **Broken Access Control** (incl. SSRF) | Handler fetches by ID with no ownership check; role checks only in the UI; RLS never enabled; `/admin` guarded by middleware only | Server-side ownership filter in every query; deny-by-default routing; data access layer that requires a principal; §4.3 |
| **A02** | **Security Misconfiguration** | Debug mode on; CORS `*` with credentials; default admin creds; no security headers; verbose errors; storage bucket public; DB port exposed | Hardened config committed as code; §10.2 headers; §16 gate; scan the deployed surface, not just the repo |
| **A03** | **Software Supply Chain Failures** | Hallucinated packages; unpinned deps; no lockfile; abandoned libraries; install scripts running arbitrary code | §9 — lockfiles, existence verification, `--ignore-scripts`, Renovate, SBOM |
| **A04** | **Cryptographic Failures** | Plain HTTP internally; secrets in plaintext; SHA-256 for passwords; hand-rolled crypto; PII unencrypted at rest | TLS everywhere; argon2id; libsodium/WebCrypto, never DIY; encrypt sensitive columns |
| **A05** | **Injection** (incl. XSS) | Raw SQL escape hatches; `dangerouslySetInnerHTML`; `exec()` with user input; unescaped template rendering | Parameterized queries; escape by default; sanitise HTML server-side; CSP as backstop |
| **A06** | **Insecure Design** | No threat model; auth flows invented ad hoc; no rate limits by design; secrets in the architecture | Threat model prompt before building; §2 constitution; reuse standard patterns |
| **A07** | **Authentication Failures** | Weak reset flows; no lockout; sessions that never expire; tokens in localStorage; predictable reset tokens | Use a maintained auth library as designed; §4.2 |
| **A08** | **Software/Data Integrity Failures** | Unsigned CI artifacts; `curl \| bash` in Dockerfiles; unpinned base images; insecure deserialization | Pin by digest; verify checksums; signed commits; never deserialize untrusted data into objects |
| **A09** | **Security Logging & Alerting Failures** | No audit log; no alerts; secrets and PII *in* the logs; logs never read | Log auth events, authz denials, admin actions with correlation IDs; alert on anomalies; §13.3 |
| **A10** | **Mishandling of Exceptional Conditions** | `try { authz() } catch { /* continue */ }`; errors returning 200; stack traces to the client; race conditions on retries | Fail closed; explicit error taxonomy; generic client messages; idempotency |

**A10 deserves special attention for AI-generated code.** Models produce optimistic happy-path code and then wrap it in a `try/catch` that swallows the error to make the demo work. Every `catch` block in generated code should be read with the question: *"if this fires, does the user end up with more access than they should have?"*

---

## 6. OWASP API Security Top 10 (2023) — the short version

The general Top 10 doesn't cover API-specific authorization granularity. This list does, and three of its top five are authorization failures.

| # | Risk | One-line defence |
|---|---|---|
| API1 | **BOLA** — object-level authz | Ownership filter in the query, every time (§4.3) |
| API2 | **Broken Authentication** | Standard library, rate-limited, uniform failure responses |
| API3 | **BOPLA** — property-level authz | Explicit response DTOs + strict input schemas (no mass assignment) |
| API4 | **Unrestricted Resource Consumption** | Rate limits, payload caps, pagination, cost quotas, timeouts |
| API5 | **BFLA** — function-level authz | Deny-by-default routing; role assertion inside every handler |
| API6 | **Unrestricted Access to Sensitive Business Flows** | Velocity/abuse controls on flows, not just endpoints |
| API7 | **SSRF** | Scheme + host allow-list, private-range blocking, no redirects |
| API8 | **Security Misconfiguration** | Hardened defaults as code; headers; no debug in prod |
| API9 | **Improper Inventory Management** | One OpenAPI spec as the source of truth; kill old versions, staging APIs, and forgotten subdomains |
| API10 | **Unsafe Consumption of Third-Party APIs** | Validate *responses* from upstreams the same way you validate requests; timeouts; don't forward raw upstream data to clients |

API9 is the quiet one and it's the one vibe coding makes worse: rapid iteration leaves behind `/api/v0/`, a staging deployment with production credentials, a preview URL that never got taken down. Keep an inventory. Scan your own domains quarterly.

---

## 7. The data layer: Postgres, Supabase, and RLS

This is the single highest-frequency catastrophic failure in vibe-coded applications, so it gets its own section.

### 7.1 What went wrong, at scale

Supabase auto-generates a REST API from your Postgres schema. Every table in the `public` schema is reachable at `https://<project>.supabase.co/rest/v1/<table>`, using the `anon` key — which is *designed to be public* and sits in your JavaScript bundle. Row Level Security is what makes that safe, and RLS is **off by default** on new tables.

In 2025, a researcher scanned apps generated by an AI builder and found 303 endpoints across 170 projects with tables readable by anyone holding the anon key — emails, addresses, payment details, and in some cases API keys. It became CVE-2025-48757 (CVSS 9.3). The platform argued it was developer configuration, not a platform flaw. Both are true, and the data was still readable.

The mechanism generalises beyond Supabase: **any auto-generated API over a schema is only as safe as the row-level policy you remembered to write.**

Why AI generators fail at this specifically: writing a schema is a mechanical task; writing a policy requires understanding the app's authorization model. Generators get the schema right and skip the policy. Worse, when they add tables *later* for new features, the policy step often doesn't re-run — so an app that was audited at launch develops holes as it grows.

### 7.2 Rules

1. **Turn on the project-level "Enable RLS on new tables" toggle** before you create a single table. Default-secure beats remembering.
2. **Every table in `public` has RLS enabled and at least one policy.** Junction tables, settings tables, audit logs, lookup tables — all of them. One missed table is a full exposure of that table.
3. **The `service_role` key bypasses RLS entirely.** It never appears in client code, in a `NEXT_PUBLIC_` variable, in a mobile app, or in an AI agent's toolset. Server-side only, and only where you genuinely need to act as the system.
4. **Never "fix" a blocked query by disabling RLS.** If a query fails under RLS, the policy is wrong or the query is wrong. Turning RLS off re-opens the table to the entire internet. This is the most common bad suggestion an AI assistant will make when you paste it an RLS error — refuse it.
5. **Write the policy for reads AND writes.** A read policy with no insert/update/delete policy is common in generated code; without them the defaults may still let an attacker write. Be explicit per operation.
6. **Assume table names are guessable.** Generators converge on the same names — `users`, `profiles`, `orders`, `messages`, `invoices`. Attackers enumerate exactly that list. Obscure naming is not a control, but it tells you where to look first when auditing.

### 7.3 Verification (run this before every launch)

```sql
-- Any table returned here is reachable with the public anon key.
SELECT tablename FROM pg_tables
WHERE schemaname = 'public' AND NOT rowsecurity;

-- Tables with RLS on but NO policies: also effectively broken.
SELECT t.tablename FROM pg_tables t
LEFT JOIN pg_policies p ON p.tablename = t.tablename AND p.schemaname = 'public'
WHERE t.schemaname = 'public' AND t.rowsecurity AND p.policyname IS NULL
GROUP BY t.tablename;
```

Then test from the outside, as an anonymous attacker would:

```bash
curl -s "https://<project>.supabase.co/rest/v1/profiles?select=*" \
  -H "apikey: <ANON_KEY>" | head
# Rows returned == exposure. Empty array or 401 == correct.
```

Repeat for every table name in your schema, and for the obvious guesses even if you don't think they exist.

### 7.4 Policy patterns

```sql
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;

-- Owner-only read. Note the (select auth.uid()) form: it's evaluated once
-- per query instead of once per row, which matters a lot on large tables.
CREATE POLICY "own invoices: read" ON invoices FOR SELECT
  USING ((select auth.uid()) = user_id);

CREATE POLICY "own invoices: insert" ON invoices FOR INSERT
  WITH CHECK ((select auth.uid()) = user_id);

CREATE POLICY "own invoices: update" ON invoices FOR UPDATE
  USING ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);
```

For B2B multi-tenant, scope by organisation membership rather than user:

```sql
CREATE POLICY "org read" ON invoices FOR SELECT USING (
  org_id IN (
    SELECT org_id FROM memberships WHERE user_id = (select auth.uid())
  )
);
```

Index `user_id` / `org_id`. An RLS policy that does a sequential scan per query becomes a denial-of-service vector at scale.

### 7.5 If you're not on Supabase

The same discipline applies with a normal Postgres + backend:

- The app's DB user is **not** the owner and **not** superuser. Grant only the tables and operations it needs.
- Separate read-only credentials for analytics, reporting, and BI dashboards.
- Migrations are versioned files in git (Drizzle Kit, Alembic, Flyway). Never `ALTER TABLE` by hand in production — undocumented schema drift is where policies go missing.
- Tenant scoping still belongs in a data access layer, and consider RLS as a second net even when the app is the only client. Defence in depth means the bug in your handler doesn't become a breach.
- Backups encrypted, stored off-box, **and restore-tested** (§13.4).

---

## 8. Secrets

### 8.1 Rules

- Secrets live in environment variables injected at runtime, sourced from a `.env` that is in `.gitignore` from the first commit — not from the commit where you noticed.
- Commit a `.env.example` with keys and empty values. It's documentation *and* it stops the "what env vars does this need" prompt that leads to someone pasting real ones into a chat.
- **Anything the browser can read is not a secret.** `NEXT_PUBLIC_*`, `VITE_*`, and anything in client bundle code is published the moment you deploy. If a third-party API key must be used from the browser, it needs its own domain restrictions and scoping — otherwise proxy the call through your server.
- Different secrets per environment. A staging deployment with production credentials is a production breach waiting for a staging bug.
- Rotation is a procedure you've actually run, not a plan. Rotate on any suspicion, on contributor departure, and on a schedule for high-value keys.
- Never paste real secrets into a chat with any AI, including this one. Use placeholders.

### 8.2 Detection and prevention

- **Pre-commit hook** running `gitleaks protect --staged`. This is the highest-value 5-minute setup in this whole document.
- **CI scan** with `gitleaks detect` or `trufflehog` over full history on every PR.
- **A secret committed to git is compromised**, including in a private repo, including if you delete it in the next commit — git history keeps it, and forks/clones/CI caches keep it too. The response is *rotate the credential*, then optionally clean history. Never just delete the line.
- Enable push protection / secret scanning on your remote if available.

### 8.3 Storage

For a self-hosted setup, in ascending order of rigour: `.env` with `600` perms owned by the service user → Docker secrets → SOPS + age (encrypted secrets committed to git, decryptable only with the key) → Infisical or Vault self-hosted. SOPS+age is the sweet spot for a solo operator: auditable, versioned, no extra service to run.

---

## 9. Supply chain (OWASP A03)

New to the Top 10 in 2025, and the risk category most directly amplified by AI-generated code.

### 9.1 Slopsquatting

An academic study of 576,000 AI-generated code samples across 16 models found that **~19.7% of recommended packages did not exist** — over 205,000 unique fabricated names. Commercial models hallucinated at around 5%; open-weight models much higher. Critically, the hallucinations are **repeatable**: roughly 43% of fake names recurred across every run, and 58% appeared again within ten runs.

That repeatability is the attack. An adversary runs common prompts, collects the names that keep appearing, registers them on npm or PyPI with a malicious payload, and waits for someone to paste the install command. It isn't typosquatting — the names aren't misspellings, so registry similarity heuristics don't catch them.

**Defence:**
- Before installing anything the model suggested: check the registry page. Real download volume, a repository link that actually exists, releases over time, a maintainer with other work. A package created three weeks ago with 40 downloads that happens to do exactly what you need is a red flag, not a lucky find.
- Never run a suggested `npm install` / `pip install` line without reading the package names in it.
- `npm ci --ignore-scripts` in CI. Install scripts are arbitrary code execution at install time and are the primary payload delivery mechanism.

### 9.2 General hygiene

- **Commit the lockfile.** `package-lock.json` / `pnpm-lock.yaml` / `uv.lock` / `poetry.lock`. Install with `npm ci`, not `npm install`, everywhere.
- **Fewer dependencies.** Every package is a trust relationship with strangers and their compromised npm accounts. If it's under ~50 lines to write yourself, write it.
- **Pin Docker base images by digest**, not by `:latest` or even `:22-slim`.
- **Automated updates:** Renovate or Dependabot, grouped weekly, with CI gating merges. Unpatched known-vulnerable dependencies remain one of the most exploited entry points.
- **`npm audit --audit-level=high` / `pip-audit` in CI**, failing the build on high/critical.
- **SBOM** (`syft`) for anything you deliver to a client — increasingly asked for in B2B procurement, and it's a differentiator when the buyer is a mid-market firm with a compliance checklist.
- Review the *diff* of dependency updates on anything security-relevant. Compromised maintainer accounts push malicious minor versions.

---

## 10. Frontend security

### 10.1 XSS and rendering

React escapes by default. The ways generated code breaks that:

- `dangerouslySetInnerHTML` — the only real one. If you must render HTML (rich text, markdown, CMS content), sanitise **server-side** with DOMPurify/`sanitize-html` and an allow-list of tags and attributes. Client-side sanitisation alone is bypassable.
- `href={userInput}` — allows `javascript:` URLs. Validate the scheme.
- `eval`, `new Function`, `setTimeout("string")` — never with anything user-influenced.
- Third-party scripts: analytics, chat widgets, embeds. Each one runs with full DOM access on your origin. Use Subresource Integrity where possible; audit what you actually need.

Store session tokens in `HttpOnly` cookies, not `localStorage`. This is the difference between "XSS defaced the page" and "XSS stole every session."

### 10.2 Security headers

Set these at the reverse proxy so they apply regardless of what the app does:

| Header | Value | Purpose |
|---|---|---|
| `Content-Security-Policy` | `default-src 'self'; script-src 'self' 'nonce-{random}'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'` | The single most effective XSS mitigation. Nonce-based, not `unsafe-inline`. |
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains; preload` | Forces HTTPS |
| `X-Content-Type-Options` | `nosniff` | Stops MIME confusion attacks |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Stops URL/token leakage to third parties |
| `Permissions-Policy` | `camera=(), microphone=(), geolocation=()` | Drops unused browser capabilities |
| `X-Frame-Options` | `DENY` (or rely on `frame-ancestors`) | Clickjacking |
| `Cross-Origin-Opener-Policy` | `same-origin` | Cross-origin isolation |

CSP is the one that takes effort. Start in `Content-Security-Policy-Report-Only`, collect violations for a week, then enforce. Do not ship `script-src 'unsafe-inline' 'unsafe-eval'` and call it done — that's a CSP header with no CSP.

Verify externally with `curl -sI https://yourdomain` and a scanner like Mozilla Observatory before launch.

### 10.3 CORS

The pattern generated code produces, and why it's wrong:

```js
// WRONG — with credentials this is a cross-origin free-for-all
app.use(cors({ origin: '*', credentials: true }));

// RIGHT — explicit allow-list, no wildcard reflection
app.use(cors({
  origin: ['https://app.example.com'],
  credentials: true,
  methods: ['GET', 'POST', 'PATCH', 'DELETE'],
}));
```

Never reflect the `Origin` header back unconditionally — that's a wildcard with extra steps. If your API is public and unauthenticated by design, `*` without credentials is fine; the danger is `*` plus cookies.

### 10.4 Dashboards specifically

Dashboards are where authorization bugs hide, because the UI implies the boundary:

- Every widget makes its own request; every one of those requests needs its own authz check. "The user can't see the admin tab" does not stop them from calling the endpoint that feeds it.
- **Export endpoints** (CSV/PDF/XLSX) are frequently written after the auth work is done and inherit none of it. They are also unbounded by nature — cap rows, apply the same tenant filter, rate-limit hard.
- **Filter and sort parameters** that flow into SQL are a classic injection vector. Map `?sort=name` to an allow-listed column name; never interpolate it.
- **Aggregate queries can leak individual records** in small-N situations. If a filter can narrow a "team average" to one person, it's a data disclosure.
- Multi-tenant dashboards: the tenant ID comes from the session, never from a query param or a client-set header. An `X-Org-Id` header the client controls is an authorization bypass with a professional-looking name.

---

## 11. AI features inside your product

If your app calls an LLM, you inherit a second threat model on top of the web one.

### 11.1 The lethal trifecta

Simon Willison's framing, and the most useful architectural rule in this space. An AI system is exploitable when it has all three of:

1. **Access to private data** — your DB, files, inbox, customer records.
2. **Exposure to untrusted content** — user input, web pages, emails, uploaded PDFs, third-party API responses, ticket text.
3. **An exfiltration channel** — outbound HTTP, rendering images/links, sending email, writing to a shared location.

With all three present, no amount of system-prompt hardening fixes it. Prompt injection isn't the model malfunctioning; it's the model doing its job on text an attacker wrote. **Design the trifecta apart** — that's the control, and everything else is mitigation:

- Remove the exfiltration leg: no arbitrary outbound requests, no auto-rendering of remote images, no auto-clickable model-generated links, CSP restricting `img-src`/`connect-src`.
- Or remove the private-data leg: the agent that reads untrusted content runs with no credentials and returns structured data to a separate, trusted process.
- Or gate the untrusted-content leg: no untrusted text reaches the agent that holds credentials.

### 11.2 Practical controls

- **Treat all model output as untrusted user input.** Never `eval` it, never pass it to a shell, never interpolate it into SQL, never render it as raw HTML. If it drives an action, the action goes through the same validation and authorization as a request from a stranger.
- **Human confirmation for irreversible or outbound actions** — sending email, deleting records, making payments, posting publicly.
- **Scope credentials to the user, not the system.** If the assistant answers questions about "your invoices," it queries with the *user's* permissions, not a service account. Otherwise you've built a BOLA vulnerability with a chat interface.
- **RAG leakage:** the retrieval layer must filter by tenant *before* embedding search, not after. A vector store containing every tenant's documents, filtered post-hoc, will eventually return the wrong one.
- **Cost abuse:** unauthenticated or unmetered LLM endpoints are free compute for anyone who finds them. Auth + per-user token quotas + max output length + timeout, all enforced before the call.
- **Log prompts and completions** with correlation IDs for incident response — but scrub PII and secrets, and set a retention limit. Those logs are now sensitive data you're responsible for.
- **Don't put secrets in the system prompt.** It's extractable. Assume users will read it.

### 11.3 Third-party AI risk

If you ship AI features for clients, know and document: which provider, what data leaves your infrastructure, whether it's retained or trained on, and where it's processed. For EU B2B clients this is a contractual question, not a technical one, and being able to answer it crisply is a sales advantage — especially if the answer is "it runs on our own hardware."

---

## 12. Automation platforms (n8n) as an attack surface

Relevant because automation is often the actual product, and n8n is a **credential aggregator by design**: a single instance may hold Stripe, Google, SMTP, database, and CRM credentials at once. Its blast radius is the union of everything it can reach.

**Deployment:**
- Never expose the editor UI to the internet. Bind it internally and reach it through your SSO/VPN. Route only `/webhook/*` publicly through the reverse proxy; block admin paths at the proxy.
- Set a stable `N8N_ENCRYPTION_KEY`. Without it, stored credentials aren't properly protected — and if you lose it, they become unrecoverable. Back it up separately from the database.
- `N8N_BLOCK_ENV_ACCESS_IN_NODE=true` — otherwise Code and Execute Command nodes can read your environment, including the DB password and encryption key.
- Postgres, not SQLite, for anything that matters. `N8N_SECURE_COOKIE=true`, `N8N_PROTOCOL=https`, `WEBHOOK_URL` matching your real domain.
- Complete the owner setup wizard immediately on first boot — until you do, whoever reaches the port becomes the owner.
- Don't blind-auto-update production. Back up, update, test critical workflows.

**Workflows:**
- Every public webhook gets authentication — header auth at minimum, HMAC signature verification for anything from a known vendor (Stripe, GitHub) or anything financial. The default is *no auth*.
- Treat webhook URLs as secrets even with auth in place; don't shorten the generated paths.
- Validate and schema-check inbound payloads before they drive logic. A webhook that triggers on any POST is an unauthenticated RPC into your infrastructure.
- Separate credentials per workflow with minimum scopes. One over-scoped Google credential shared across twelve workflows means one compromised workflow owns the whole account.
- Execution logs retain payload data — customer records, API responses, financial data. Set retention (`EXECUTIONS_DATA_MAX_AGE`) and treat the log store as sensitive.
- Rate-limit webhook endpoints at the proxy. n8n won't do it for you.
- For **client-facing** automations: separate instance or at minimum separate credentials per client. Never share one n8n across clients — a single misconfigured workflow becomes a cross-client data breach, which is a business-ending event, not a bug.

**MCP servers and AI agent tools:** audit which servers you connect, never expose them to untrusted networks, and read tool descriptions — hidden instructions in a tool description ("tool poisoning") are read by the model as commands. Any tool with write access to production is the exfiltration leg of §11.1.

---

## 13. Infrastructure, deployment, and operations

### 13.1 Host hardening

SSH keys only, password auth disabled, root login disabled. Firewall default-deny inbound; only 80/443 (and SSH, ideally restricted by source). Unattended security upgrades. `fail2ban` or CrowdSec on SSH and the proxy. Separate non-root user per service.

### 13.2 Containers

Non-root `USER` in every Dockerfile. Read-only root filesystem where possible. Drop capabilities. No `--privileged`. Never mount the Docker socket into a container that processes untrusted input — that's root on the host. Multi-stage builds so build tooling and source don't ship. Resource limits on every container, so one runaway workload doesn't take the box down. Scan images with `trivy` in CI.

Network segmentation: databases on an internal Docker network with no published ports. If you can `psql` to it from your laptop over the internet, so can everyone else.

### 13.3 Logging and alerting (A09)

**Log:** authentication successes and failures, authorization denials, admin actions, privilege changes, password/email changes, payment events, data exports — each with timestamp, principal, source IP, and a correlation ID.

**Never log:** passwords, tokens, session IDs, API keys, full card numbers, or raw request bodies from sensitive endpoints. Generated logging code will happily `console.log(req.body)` on a login handler.

**Alert on:** authz denial spikes (someone probing for BOLA), login failure spikes, first-ever admin action from a new IP, error-rate spikes, unusual data-export volume, unexpected outbound connections. The 2025 rename to "Logging & *Alerting* Failures" is the point: logs nobody reads have no security value.

Minimum viable stack, self-hosted: structured JSON logs → Loki + Grafana, Uptime Kuma for availability, and alerts to a channel you actually check.

### 13.4 Backups

3-2-1: three copies, two media, one off-site. Encrypted at rest. Automated and monitored — a backup job that has been silently failing for six weeks is the norm, not the exception.

**Restore-test quarterly.** Write down how long it took. An untested backup is a hypothesis. For client work, the restore time *is* your RTO and you should know it before someone asks.

### 13.5 CI/CD

Pipeline gates, in order: install with lockfile → lint + typecheck → tests → `gitleaks` → `semgrep` → dependency audit → container scan → build → deploy. Fail the build on high/critical findings; don't make the report advisory or nobody will read it.

Deployment credentials scoped to deployment only. Protect the main branch. Never let CI logs print environment variables. Signed commits if you're delivering to clients who care.


---

## 14. Legal and compliance baseline

Not legal advice — this is an engineering checklist. For anything with real regulatory exposure, get a lawyer. If you or your users are in the EU, GDPR applies to essentially everything with a user in it.

- **Data minimisation.** Don't collect what you don't need. The cheapest way to survive a breach is to have had nothing interesting to steal. This is also the easiest thing to get wrong with generated schemas, which love adding `phone`, `address`, `date_of_birth` fields nobody asked for.
- **Lawful basis and privacy notice.** What you collect, why, how long you keep it, who you share it with, and how to request deletion. A real page, not a placeholder.
- **Retention limits** implemented as an actual deletion job, not a sentence in a policy.
- **Data subject rights:** export and deletion need to be *possible* in your schema design. Hard-deleting a user whose ID is a foreign key in nine tables with no cascade plan is a rough afternoon.
- **Processor agreements (DPAs)** with every subprocessor — hosting, email, analytics, LLM provider. Keep a list. B2B clients will ask for it during procurement, and having it ready is a sales advantage.
- **Breach notification: 72 hours** to the supervisory authority. Which means you need §17 written *before* you need it.
- **Cookie consent** before any non-essential cookie or analytics script fires. Loading analytics on page load and asking afterwards is the standard, non-compliant pattern.
- **Contracts:** for client work, be explicit about who owns the code, who is the data controller vs processor, what your security obligations are, and what happens after the engagement ends. "AI-assisted development" should be disclosed if the client has IP or provenance requirements.
- **Delivery hygiene:** when you hand a system to a client, hand over the credentials properly (a password manager share, not email), rotate anything you used, and document what you'd expect them to maintain.

---

## 15. Testing and verification

### 15.1 Automated

| Tool | What it catches | Where |
|---|---|---|
| **Semgrep** (`--config auto`) | Insecure patterns, injection, auth mistakes | Pre-commit + CI |
| **gitleaks** | Secrets in code and history | Pre-commit + CI |
| **npm audit / pip-audit / osv-scanner** | Known-vulnerable dependencies | CI |
| **Trivy** | Container image and IaC issues | CI |
| **TypeScript strict + ESLint security plugins** | Type-confusion and unsafe patterns | Editor + CI |
| **OWASP ZAP baseline scan** | Missing headers, obvious web issues on the deployed app | Pre-launch |
| **Mozilla Observatory / securityheaders.com** | Header configuration on the live site | Pre-launch |
| **Nuclei** | Known CVEs and exposures on your own domains | Quarterly, on your own infra only |

Static analysis plus structured LLM self-review catches meaningfully more than either alone — run the scanner, then hand the findings back to the model for remediation, then re-scan.

### 15.2 Manual — the tests that actually find the bugs

Automated tools do not find broken authorization. You do. For every project, do this by hand with two test accounts (A and B) and one unauthenticated session:

1. **Horizontal BOLA.** Log in as A, capture a request for A's resource, replay it with B's ID. Repeat for every resource type. Expect 403/404.
2. **Vertical BFLA.** Take an admin-only request, replay it with a normal user's token. Expect 403.
3. **Unauthenticated sweep.** Replay every request with no token at all. Expect 401.
4. **Mass assignment.** Add `{"role":"admin","is_verified":true,"orgId":"<other org>"}` to a profile update body. Expect rejection or silent field-drop — never acceptance.
5. **Direct database probe.** Query your data API with the public/anon key from a clean browser profile (§7.3).
6. **Response inspection.** Read the raw JSON of every endpoint. Look for fields the UI doesn't display: hashes, internal IDs, flags, other users' data embedded in a list.
7. **Rate limit check.** Hammer login and one expensive endpoint. Confirm 429.
8. **Error probing.** Send malformed JSON, wrong types, huge payloads, null bytes, a 10MB string. Look for stack traces and 500s that leak.
9. **Client bundle grep.** `curl` the built JS and search for `key`, `secret`, `token`, `sk_`, `service_role`, internal hostnames.
10. **Header check** against the live domain, not localhost.

This takes about an hour. It has a higher hit rate than every scanner combined, and it is the concrete deliverable that separates "I built you a dashboard" from "I built you a dashboard and here's the security test report."

---

## 16. The Pre-Launch Gate

Nothing goes to production with an unchecked box. Copy this into the project repo as `SECURITY-CHECKLIST.md` and fill it in per deployment.

**Access control**
- [ ] Every endpoint has an explicit server-side authz check
- [ ] Tenant/owner ID comes from the session, never from client input
- [ ] Manual BOLA / BFLA / unauthenticated tests passed (§15.2 items 1–3)
- [ ] Admin functions gated by role, not by UI visibility
- [ ] Default-deny on unknown routes and unknown roles

**Data**
- [ ] RLS enabled + policies on every public-schema table (verification query run)
- [ ] `service_role` / admin DB credentials nowhere near client code
- [ ] Anonymous REST probe against real table names returns nothing
- [ ] App DB user is least-privilege, not owner/superuser
- [ ] Backups automated, encrypted, off-site, and restore-tested

**Secrets**
- [ ] `.env` gitignored; `gitleaks detect` clean over full history
- [ ] No `NEXT_PUBLIC_`/`VITE_` variable holds anything sensitive
- [ ] Client bundle grepped for keys and internal hostnames
- [ ] Separate credentials per environment
- [ ] Anything ever committed has been rotated

**Input / output**
- [ ] Schema validation on every endpoint, unknown fields rejected
- [ ] No string-built SQL / shell / path anywhere (`grep` for raw-query escape hatches)
- [ ] Explicit response DTOs — no entity serialised directly
- [ ] File uploads: type-sniffed, size-capped, renamed, served safely
- [ ] SSRF controls on any user-supplied URL fetch

**Auth**
- [ ] Standard library, not hand-rolled
- [ ] argon2id/bcrypt; sessions in HttpOnly+Secure+SameSite cookies
- [ ] Rate limits on login / signup / reset / OTP, per-IP and per-account
- [ ] Uniform responses (no user enumeration)
- [ ] MFA available on admin accounts

**Transport / headers**
- [ ] HTTPS enforced, HSTS set, HTTP redirects
- [ ] CSP enforced without `unsafe-inline`/`unsafe-eval`
- [ ] Full header set verified against the live domain
- [ ] CORS allow-listed, no wildcard-with-credentials

**Supply chain**
- [ ] Lockfile committed; CI installs with `ci`/frozen lockfile
- [ ] Every AI-suggested package verified to exist with real usage history
- [ ] Dependency audit clean at high/critical
- [ ] Base images pinned by digest
- [ ] Renovate/Dependabot enabled

**Operations**
- [ ] Debug mode off; generic error responses; no stack traces to clients
- [ ] Auth and admin events logged with correlation IDs; no secrets in logs
- [ ] At least one alert configured and tested end to end
- [ ] Uptime monitoring live
- [ ] Admin UIs (n8n, Grafana, Portainer, DB tools) not publicly reachable
- [ ] Every `catch` block reviewed for fail-open behaviour

**AI features**
- [ ] Lethal trifecta broken at at least one leg
- [ ] Model output never eval'd, shell'd, or rendered as raw HTML
- [ ] Per-user token quotas and output caps
- [ ] RAG retrieval filtered by tenant before search
- [ ] Human confirmation on irreversible actions

**Compliance**
- [ ] Privacy notice live; cookie consent gates non-essential scripts
- [ ] Retention and deletion implemented, not just documented
- [ ] Subprocessor list maintained
- [ ] Incident plan written with contacts

---

## 17. Incident response (the one-page version)

Write the contact list *now*, while nothing is on fire.

1. **Contain.** Revoke sessions and API keys, disable the affected endpoint or feature, take the service offline if the alternative is ongoing exfiltration. Availability is worth less than containment.
2. **Preserve.** Snapshot logs, DB, and container state *before* you start fixing. You cannot reconstruct scope from a system you've already patched and restarted.
3. **Assess.** What data, whose data, how many records, over what window, and is the vector still open? Be honest about uncertainty — "we can't rule out X" is a legitimate finding.
4. **Eradicate and rotate.** Fix the vulnerability. Rotate every credential in the blast radius, not just the one you think was used.
5. **Notify.** GDPR: supervisory authority within 72 hours of becoming aware, where the breach risks people's rights; affected individuals without undue delay if the risk is high. Client contracts usually specify tighter notification terms — check them.
6. **Post-mortem.** Blameless, written, with a concrete change to this document or your checklist. If nothing in your process changes, the incident will repeat.

**Keep on file:** hosting provider support contact, domain registrar, the client's technical and legal contact, your DPA obligations, and your data-protection supervisory authority's reporting channel (in the EU: the national DPA of your main establishment).

---

## 18. Tooling reference

| Category | Pick |
|---|---|
| Secret scanning | gitleaks, trufflehog |
| SAST | Semgrep, CodeQL (free on public repos) |
| Dependency scanning | osv-scanner, npm audit, pip-audit, Renovate |
| Container scanning | Trivy, Grype |
| SBOM | Syft |
| DAST / external | OWASP ZAP baseline, Nuclei, Mozilla Observatory |
| Validation | Zod (TS), Pydantic v2 (Python) |
| Auth | Authentik (self-hosted), Better Auth, Auth.js, Supabase Auth |
| Rate limiting | Nginx `limit_req`, `@upstash/ratelimit`, SlowAPI |
| Sanitisation | DOMPurify, sanitize-html, bleach |
| Secrets at rest | SOPS + age, Infisical, Docker secrets |
| Logs / monitoring | Loki + Grafana, Uptime Kuma, Sentry (self-hosted) |
| Reference | OWASP ASVS, OWASP Cheat Sheet Series, OWASP API Top 10 |

**OWASP ASVS** is worth a mention on its own: when a client asks "how do you know it's secure," ASVS Level 1 is a defensible, citable answer and a far better artifact than "we used best practices."

---

## Appendix A — Snippets

### A.1 Zod boundary validation (strict, no mass assignment)

```ts
import { z } from 'zod';

const UpdateProfile = z.object({
  displayName: z.string().min(1).max(80),
  bio: z.string().max(500).optional(),
}).strict();  // unknown keys => error, so {"role":"admin"} is rejected

export async function PATCH(req: Request) {
  const session = await requireSession();          // throws 401
  const parsed = UpdateProfile.safeParse(await req.json());
  if (!parsed.success) return json({ error: 'invalid_input' }, 400);

  const updated = await db.user.update({
    where: { id: session.userId },                  // never from the body
    data: parsed.data,
    select: { id: true, displayName: true, bio: true },  // explicit DTO
  });
  return json(updated);
}
```

### A.2 Next.js security headers

```js
// next.config.js
const csp = [
  "default-src 'self'",
  "script-src 'self'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: https:",
  "connect-src 'self'",
  "object-src 'none'",
  "base-uri 'none'",
  "frame-ancestors 'none'",
].join('; ');

module.exports = {
  poweredByHeader: false,
  async headers() {
    return [{
      source: '/:path*',
      headers: [
        { key: 'Content-Security-Policy', value: csp },
        { key: 'Strict-Transport-Security', value: 'max-age=31536000; includeSubDomains; preload' },
        { key: 'X-Content-Type-Options', value: 'nosniff' },
        { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
        { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=()' },
        { key: 'X-Frame-Options', value: 'DENY' },
      ],
    }];
  },
};
```

### A.3 Nginx: rate limit, headers, and blocking the n8n admin UI

```nginx
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=auth:10m rate=5r/m;

server {
    listen 443 ssl http2;
    server_name api.example.com;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    server_tokens off;
    client_max_body_size 10M;

    # Defence in depth against middleware-bypass style header spoofing
    proxy_set_header x-middleware-subrequest "";

    location /auth/ { limit_req zone=auth burst=5 nodelay; proxy_pass http://app; }
    location /      { limit_req zone=api burst=20 nodelay; proxy_pass http://app; }
}

server {
    listen 443 ssl http2;
    server_name n8n.example.com;

    location /webhook/ { proxy_pass http://n8n:5678; }   # public
    location / { return 403; }                            # editor UI: internal only
}
```

### A.4 Pre-commit hooks

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.28.0
    hooks: [{ id: gitleaks }]
  - repo: https://github.com/semgrep/semgrep
    rev: v1.94.0
    hooks: [{ id: semgrep, args: ['--config', 'auto', '--error', '--skip-unknown-extensions'] }]
```

### A.5 CI security gate (GitHub Actions)

```yaml
name: security
on: [push, pull_request]
jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }        # full history for secret scanning
      - uses: gitleaks/gitleaks-action@v2
      - uses: returntocorp/semgrep-action@v1
        with: { config: p/security-audit }
      - run: npm ci --ignore-scripts
      - run: npm audit --audit-level=high
      - uses: aquasecurity/trivy-action@<full-commit-sha>   # pin actions by SHA, never @master
        with: { scan-type: fs, severity: 'HIGH,CRITICAL', exit-code: '1' }
```

### A.6 The `.gitignore` opening lines

```gitignore
.env
.env.*
!.env.example
*.pem
*.key
*.p12
secrets/
credentials.json
service-account*.json
*.sqlite
*.dump
```

---

## Appendix B — Sources and further reading

- OWASP Top 10:2025 — https://owasp.org/Top10/2025/
- OWASP API Security Top 10:2023 — https://owasp.org/API-Security/editions/2023/en/0x11-t10/
- OWASP ASVS — https://owasp.org/www-project-application-security-verification-standard/
- OWASP Cheat Sheet Series — https://cheatsheetseries.owasp.org/
- Simon Willison on the lethal trifecta — https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/
- CVE-2025-29927 (Next.js middleware bypass) analysis — https://securitylabs.datadoghq.com/articles/nextjs-middleware-auth-bypass/
- CVE-2025-48757 (Supabase RLS exposure at scale) — https://www.guardlayer.io/blog/supabase-security-breaches
- Package hallucination / slopsquatting research — https://www.bleepingcomputer.com/news/security/ai-hallucinated-code-dependencies-become-new-supply-chain-risk/
- Databricks on secure prompting for generated code — https://www.databricks.com/blog/passing-security-vibe-check-dangers-vibe-coding
- n8n hardening — https://docs.n8n.io/hosting/securing/

---

*Revision log*
*v1.0 — 2026-08-11 — initial baseline.*
*v1.1 — 2026-11-11 — packaged as an agent skill; fixed the webhook `timingSafeEqual` length bug and the unpinned `trivy-action@master` in A.5; generalized org-specific references.*
