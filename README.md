# security-baseline — an agent skill for security review and planning

A skill for Claude Code (and other agents that read `SKILL.md` skills) that turns an agent into a structured security reviewer for AI-assisted ("vibe-coded") projects and self-hosted servers.

It makes the agent:

1. **Decide how much security the project needs** — a threat tier (T0 toy → T3 money / PII / credential stores) from observable facts.
2. **Collect evidence read-only** — bundled scripts for a Docker host audit and a code sink sweep.
3. **Hunt the bugs AI-generated code ships by default** — BOLA/IDOR, missing RLS, client-supplied tenant IDs, mass assignment, spoofable `X-Forwarded-For`, fail-open `catch`, secrets in bundles, exposed admin UIs, stale images.
4. **Report in a fixed shape** — tier, verdict, findings tagged `CONFIRMED` or `LEAD` with evidence, freshness table, coverage (what was *not* checked), next actions.
5. **Update safely** — stateless vs data-bearing, rollback digests, registry rate limits.

## Contents

```
security-baseline/
  SKILL.md                    # the operating procedure the agent follows
  references/baseline.md      # full reference: OWASP 2025 + API Top 10 mapping, RLS, secrets,
                              # supply chain, headers, AI features, n8n, ops, pre-launch gate
  scripts/audit-docker-host.sh  # read-only host + container + image-freshness inventory
  scripts/scan-code.sh          # grep sweep for injection/authz/secret/crypto sinks
```

## Install

```bash
git clone https://github.com/Albert-4096/security-baseline-skill
cp -r security-baseline-skill/security-baseline ~/.claude/skills/
```

Then ask your agent things like *"audit my server"*, *"review this repo for security"*, *"how secure does this project need to be?"*, or *"plan auth for this app"*.

Run the scripts directly too:

```bash
bash security-baseline/scripts/audit-docker-host.sh                 # local host
ssh host 'bash -s -- --remote-digests' < security-baseline/scripts/audit-docker-host.sh
bash security-baseline/scripts/scan-code.sh path/to/project
```

`--remote-digests` asks the registry for each image's current digest. On Docker Hub this counts against the anonymous pull quota: `docker login` first.

## Safety

Both scripts are read-only and never print secret values (names and paths only). The skill tells the agent to stay read-only until the report is done and to change things only when asked. Only run it against systems you own or are authorized to test.

## License

MIT. Not legal advice; the compliance section is an engineering checklist.
