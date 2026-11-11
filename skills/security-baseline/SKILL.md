---
name: security-baseline
description: Use when reviewing, auditing, threat-modeling or planning the security of a web app, API, dashboard, MCP server, automation (n8n), self-hosted service, Docker host or homelab; when deciding how much security a project needs; when hunting vulnerabilities (BOLA/IDOR, broken RLS, leaked secrets, exposed admin UIs, outdated images or packages); before a launch or deploy; after a suspected breach; or when writing AGENTS.md/CLAUDE.md rules for an AI-built project.
---

# Security Baseline

## Overview

A full reference lives in `references/baseline.md` (sections §0–§18, grep by `## N.`). This file is the operating procedure. Core principle: **match rigour to the threat tier, then prove each finding with evidence.** Three laws: never trust the client, never trust the model's code, never trust defaults.

## Pick the mode

| Request | Mode | Read in baseline.md |
|---|---|---|
| "Plan / start a project securely", write agent rules | **Plan** | §0, §2, §3, §16 |
| "Review / audit this app / repo / PR" | **Code review** | §1.3, §4–§11, §15.2 |
| "Audit my server / homelab / VPS", "is it up to date" | **Host audit** | §3.3, §8.3, §12, §13 |
| "We got hacked / leaked a key" | **Incident** | §17, §8.2 |

A host audit includes a short code review of each internet-facing app that holds accounts or personal data.

## Step 1 — Classify the tier (always first, state it in the report)

Decide from observable facts, not from what the owner calls it:

| Tier | Predicate | Apply |
|---|---|---|
| T0 Toy | No real users or data AND not reachable from the internet (LAN only, or behind SSO) | §2, §8 |
| T1 Public, no accounts | Internet-reachable, no login, no personal data stored | T0 + §9, §10 |
| T2 Accounts / user data | Any login, any personal data (names, emails, guest lists), any API key or token it holds | Everything |
| T3 Money / PII at scale / regulated | Payments, health, credentials vaults, finance, >1k people's data, client contracts | T2 + external review + §14 |

A homelab host is rated at the **highest tier of anything it runs**. A credential aggregator (password manager, n8n, Home Assistant, Portainer, docker.sock holder) is T3 by blast radius.

## Step 2 — Collect evidence (read-only)

Run the bundled scripts through bash. On a remote host, stream them over SSH: `ssh host 'bash -s -- --remote-digests' < scripts/audit-docker-host.sh` and `ssh host 'bash -s -- <project-dir>' < scripts/scan-code.sh`.

- `bash scripts/audit-docker-host.sh --remote-digests` — OS patches, reboot flag, listening sockets, firewall, sshd, every container's user/privilege/published ports/docker.sock, secret-looking env var NAMES, image freshness (UP-TO-DATE / OUTDATED / local-build).
- `bash scripts/scan-code.sh <project-dir>` — grep leads for secrets, injection, XSS, mass assignment, client-supplied tenant IDs, fail-open catches, weak crypto, lockfiles, Dockerfile/compose risks, route inventory.

Then do what scripts cannot:
1. **Reverse-proxy inventory**: list every public hostname, its target, and whether auth sits in front (NPM DB / Caddy / Traefik labels). Admin UIs (§3.3 list) on a public hostname without SSO/access list = finding.
2. **External view**: from outside the LAN path, `curl -sI https://<host>` for headers (§10.2), and probe `/.env`, `/.git/config`, `/admin`, `/api` with GET only.
3. **Authorization trace** for each T2+ app: for every route, name the authz check and where the principal/tenant ID comes from (§4.3). Apply the §1.3 question.
4. **Proxy trust**: if an app reads `X-Forwarded-For`, check which hop it trusts (`$proxy_add_x_forwarded_for` appends; the first value is attacker-controlled).
5. **Credential strength per role**: for every role (admin, staff, volunteer, API/MCP token), find how its secret is set, including seed, legacy and migration paths that skip the normal length check. Check the real length of `.env` values with `awk -F= '{print $1, length($2)}'`, never by printing them. A weak secret plus a bypassable rate limit is one finding, not two.
6. **Versions vs advisories**: for each internet-facing app, compare the running version against current release and known CVEs. Use web search for the product's security advisories.

## Host gate (the §16 checklist is per project; use this for a host)

- [ ] Every public hostname is listed, and each admin UI (§3.3) has SSO, an access list or VPN in front, or is not public
- [ ] Hypervisor, Docker, NPM/proxy admin, password vault admin: never public
- [ ] Open sign-up disabled on every self-hosted app that does not need it (Vaultwarden, Open WebUI, Gitea, Immich, …)
- [ ] WAN-reachable ports = only 80/443 (+ VPN). Docker-published ports bypass ufw: check router forwards and `DOCKER-USER`
- [ ] Proxy passes a client IP that apps cannot be fooled by (§4.5, X-Forwarded-For)
- [ ] docker group members listed; each is root-equivalent
- [ ] Secret files mode 600; no world-readable `.env`/keys
- [ ] OS patched, no pending reboot older than 7 days; images current (freshness table)
- [ ] Backups ran recently and a restore was tested (§13.4)

## Rules of engagement

- Read-only by default. No writes, restarts, updates, POSTs that change data, brute force, or scanning hosts the owner does not own.
- Never print secret values. Report the variable name and file:line only.
- Inspect config stores (DB config tables, JSON settings, `docker inspect` env) by **keys and lengths only**: `jq 'paths'`, `SELECT key FROM …`, `awk -F= '{print $1, length($2)}'`. Never dump a whole config row or file to look at it: it will contain API keys.
- Changes (updates, chmod, config fixes) happen only after the report, and only when the requester asked for them. For updates follow "Updating safely" below.

## Step 3 — Report (this exact shape)

1. **Scope and tier**: what was examined, the tier, and the one-line reason.
2. **Verdict**: one sentence — ship / fix-first / stop.
3. **Findings**, ranked Critical → Low. Each finding has: title, `CONFIRMED` (you reproduced it or read the exact code/config path) or `LEAD` (plausible, not proven), evidence (file:line, command + output excerpt), impact in one sentence, fix.
4. **Freshness table** (host audit): component, running version, latest, risk of updating.
5. **Coverage**: the §16 gate sections you checked, and the ones you did not check and why. Silence is not a pass.
6. **Next actions**, numbered, smallest-effort-highest-risk first.

## Updating safely ("make sure everything is up to date")

1. Confirm a backup exists and is recent (§13.4). Record each container's current image ID so rollback is `image: <repo>@<old digest>`.
2. Stateless = no named volume or bind mount that the app writes to, and no database. Static nginx sites, gotenberg, flaresolverr are stateless. If unsure, treat it as data-bearing.
3. Classify: data-bearing or schema-migrating (databases, Immich, Paperless, Vaultwarden, Firefly, n8n, Home Assistant) → one at a time, read the release notes for breaking changes first. Stateless (nginx static sites, tools) → batch.
4. Never jump a database major version (postgres 15→17) through `docker pull`. That needs a dump/restore.
5. `docker compose pull && docker compose up -d` per project, then check health: container status, logs for errors, and an HTTP check of the public URL.
6. Local builds (`local-build`) update by rebuilding with `--pull`. OS packages need sudo; if you have none, report the list and the reboot flag.
7. If pulls fail with `429 toomanyrequests`, stop. Ask for `docker login` on the host, or retry after 6 h. Do not loop.

## Common mistakes

| Mistake | Correct |
|---|---|
| Report everything as "High" | Severity = exploitability × tier × blast radius |
| Treat a script hit as a finding | Script output is a LEAD until you read the code |
| "Container runs as root" without checking | Many images drop privileges in the entrypoint; check `ps` inside |
| "Port 9000 is open" on a LAN host | Say who can reach it: LAN only, WAN via router forward, or via proxy |
| Skip the tier and audit a static site like a bank | Tier first; T1 needs headers and dependencies, not RLS |
| Update everything with `:latest` in one shot | One data-bearing service at a time, with a rollback digest |
| Fix by disabling the control (RLS off, CORS `*`) | Fix the policy, never remove it (§7.2) |
