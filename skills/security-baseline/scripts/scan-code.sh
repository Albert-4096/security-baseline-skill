#!/usr/bin/env bash
# Fast grep sweep for the sinks that vibe-coded apps ship by default.
# Usage: bash scan-code.sh <project-dir>
# Read-only. Every hit is a LEAD, not a finding: open the file and confirm.
# Section numbers (§) point into references/baseline.md.

set -u
D="${1:?usage: scan-code.sh <project-dir>}"
cd "$D" || exit 1
EX=(--exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=build
    --exclude-dir=.next --exclude-dir=.venv --exclude-dir=venv --exclude-dir=__pycache__
    --exclude-dir=vendor --exclude-dir=coverage --exclude-dir=test --exclude-dir=tests --exclude-dir=__tests__ --exclude=*.test.* --exclude=*.spec.* --exclude=*.min.js --exclude=*.map
    --exclude=package-lock.json --exclude=pnpm-lock.yaml --exclude=yarn.lock)
# Files to grep: text sources under 300 KB (skips minified/vendored bundles).
LIST=$(mktemp); trap 'rm -f "$LIST"' EXIT
find . \( -name node_modules -o -name .git -o -name dist -o -name build -o -name .next -o -name .venv -o -name venv \
  -o -name __pycache__ -o -name vendor -o -name coverage -o -name test -o -name tests -o -name __tests__ \) -prune \
  -o -type f -size -300k -not -name '*.min.*' -not -name '*.map' -not -name '*.bundle.js' -not -name '*.chunk.js' \
  -not -name '*lock*' -not -name '*.test.*' -not -name '*.spec.*' -print0 > "$LIST"
s() { # s "<label> (§x)" "<ERE>"
  out=$(xargs -0 -r grep -nIE -e "$2" < "$LIST" 2>/dev/null | cut -c1-220 | head -25)
  [ -n "$out" ] && printf '\n--- %s\n%s\n' "$1" "$out"
}

echo "== project: $(pwd)"
echo "== files: $(find . -type f -not -path './node_modules/*' -not -path './.git/*' | wc -l)"

echo; echo "== SECRETS (§8)"
if git rev-parse --git-dir >/dev/null 2>&1; then
  echo "tracked env/key files:"; git ls-files | grep -E '(^|/)\.env($|\.)|\.pem$|\.key$|credentials.*\.json$|service-account' | grep -v '\.example$' | sed 's/^/  TRACKED: /'
  echo "ever committed (history):"; git log --all --name-only --format= 2>/dev/null | grep -E '(^|/)\.env($|\.)|\.pem$|\.key$' | grep -v example | sort -u | sed 's/^/  HISTORY: /'
  grep -qE '^\.env' .gitignore 2>/dev/null || echo "  .gitignore does not ignore .env"
else echo "  not a git repo (no history, no rollback)"; fi
command -v gitleaks >/dev/null && gitleaks detect --no-banner --redact -s . 2>&1 | tail -5
s "hardcoded secret-looking literals" "(api[_-]?key|secret|passw(or)?d|token|bearer)['\"]?\s*[:=]\s*['\"][A-Za-z0-9_\-\.\/+]{12,}"
s "provider key prefixes" "(sk_live_|sk-[A-Za-z0-9]{20}|sk-ant-|ghp_|github_pat_|xox[bp]-|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30}|-----BEGIN [A-Z ]*PRIVATE KEY)"
s "public-bundle env vars (§3.1, §8.1) — check none is secret" "(NEXT_PUBLIC_|VITE_|REACT_APP_|PUBLIC_)[A-Z_]*(KEY|SECRET|TOKEN|PASS|SERVICE)"
s "service_role key (§7.2)" "service_role|SERVICE_ROLE"

echo; echo "== INJECTION (§4.4, §5 A05)"
s "raw SQL escape hatches" "\\\$queryRawUnsafe|\\\$executeRawUnsafe|sql\.raw\(|\.raw\(|text\(f['\"]|execute\(f['\"]|execute\([^)]*%|execute\([^)]*\+|cursor\.execute\([^,)]*\.format\("
s "SQL built with template/concat" "(SELECT|INSERT|UPDATE|DELETE)[^;]{0,80}(\\\$\{|['\"] *\+ *[a-zA-Z_])"
s "shell exec" "child_process|execSync\(|(^|[^.[:alnum:]_])exec\(|spawn\([^)]*shell: *true|subprocess\.[a-z_]+\([^)]*shell=True|os\.system\(|os\.popen\("
s "eval / dynamic code" "\beval\(|new Function\(|setTimeout\(['\"]|pickle\.loads|yaml\.load\((?!.*SafeLoader)|marshal\.loads"
s "XSS sinks (§10.1)" "dangerouslySetInnerHTML|\.innerHTML *=|outerHTML *=|insertAdjacentHTML|v-html|\|safe\b|mark_safe\(|document\.write\("
s "user-controlled path / file serving (path traversal)" "(sendFile|createReadStream|readFile|open)\([^)]*(req\.|params|query|body|request\.)"
s "outbound fetch of possibly user URL (SSRF §4.4)" "(fetch|axios\.(get|post)|requests\.(get|post)|httpx\.(get|post)|urlopen)\([^)]*(req\.|params|query|body|url\b)"

echo; echo "== ACCESS CONTROL (§4.3, §5 A01)"
s "lookups by id only — confirm the caller filters by owner/tenant from the session" "findUnique\(\{ *where: *\{ *id *\}|findById\(|(params|query)\.(id|[a-z]+Id)\b"
s "mass assignment: request body spread into writes" "\.\.\.(req\.body|body|request\.json|data)\b|\*\*(request\.json|payload|body|data)\)|Object\.assign\([^)]*req\.body"
s "tenant/user id taken from client input" "(req\.(body|query|headers)|searchParams\.get|request\.(args|json|headers))[^\n]{0,40}(user_?id|userId|org_?id|orgId|tenant|role|is_?admin)"
s "client IP from proxy headers (§4.5) — first X-Forwarded-For value is attacker-controlled" "x-forwarded-for|X-Forwarded-For|x-real-ip|trust ?proxy|TRUST_PROXY|ProxyFix|forwarded_allow_ips"
s "auth in middleware only (§3.1) — confirm handlers re-check" "middleware\.(ts|js)|matcher:"
s "CORS (§10.3)" "origin: *['\"]\*['\"]|Access-Control-Allow-Origin['\"]?[:,] *['\"]\*|allow_origins=\[['\"]\*|origin: *true|credentials: *true"

echo; echo "== FAIL-OPEN / ERRORS (§5 A10)"
s "empty or pass-through catch blocks" "catch *(\([^)]*\))? *\{ *\}|catch *(\([^)]*\))? *\{ *(return )?next\(\)|except[^:]*: *pass|except: *$"
s "stack traces / debug to client" "DEBUG *= *True|debug: *true|app\.run\([^)]*debug=True|res\.(send|json)\([^)]*(err|error)\.(stack|message)|traceback\.format_exc"
s "logging bodies/secrets (§13.3)" "console\.log\([^)]*(req\.body|password|token|secret)|logger?\.[a-z]+\([^)]*(password|token|req\.body)"

echo; echo "== AUTH / CRYPTO (§4.2, §5 A04/A07)"
s "weak password hashing" "createHash\(['\"](md5|sha1|sha256)['\"]\)[^\n]{0,60}pass|hashlib\.(md5|sha1|sha256)\([^)]*pass|md5\(|sha1\("
s "JWT pitfalls" "algorithms: *\[[^]]*none|verify: *false|jwt\.decode\([^)]*verify|ignoreExpiration"
s "tokens in localStorage" "localStorage\.setItem\([^)]*(token|jwt|session|auth)"
s "insecure randomness for tokens" "Math\.random\(\)[^\n]{0,40}(token|id|code|secret)|random\.(random|randint)\([^\n]{0,40}(token|code)"
s "cookie flags" "httpOnly: *false|secure: *false|sameSite: *['\"]?none"
s "TLS verification disabled" "rejectUnauthorized: *false|verify=False|NODE_TLS_REJECT_UNAUTHORIZED|InsecureSkipVerify"

echo; echo "== SUPPLY CHAIN / CONTAINERS (§9, §13.2)"
for f in package.json requirements.txt pyproject.toml; do [ -f "$f" ] && echo "manifest: $f"; done
[ -f package.json ] && grep -qE '"(dev)?[dD]ependencies" *: *\{ *[^} ]' package.json && { ls package-lock.json pnpm-lock.yaml yarn.lock bun.lockb 2>/dev/null || echo "  NO JS LOCKFILE"; }
[ -f requirements.txt ] && grep -vcE '==|^#|^$' requirements.txt | sed 's/^/  unpinned python reqs: /'
for f in $(find . -maxdepth 3 -name 'Dockerfile*' -not -path './node_modules/*'); do
  echo "$f: FROM $(grep -m1 -iE '^FROM' "$f" | cut -d' ' -f2) | USER: $(grep -iE '^USER' "$f" | tail -1 | cut -d' ' -f2 || true)"
  grep -nE 'curl[^|]*\| *(ba)?sh|wget[^|]*\| *(ba)?sh' "$f" | sed 's/^/  pipe-to-shell: /'
done
for f in $(find . -maxdepth 2 -name 'docker-compose*.y*ml' -o -maxdepth 2 -name 'compose*.y*ml'); do
  grep -nE 'privileged: *true|docker\.sock|network_mode: *host|cap_add|"?[0-9]+:[0-9]+"?$|- "?0\.0\.0\.0:|image: [^:]+(:latest)?$' "$f" | sed "s#^#  $f: #"
done
[ -f package-lock.json ] && { command -v npm >/dev/null && npm audit --omit=dev --audit-level=high 2>/dev/null | tail -6 || echo "  npm not installed here: run npm audit where npm exists, or docker run --rm -v \"$PWD\":/a -w /a node:22-alpine npm audit --omit=dev"; }
command -v pip-audit >/dev/null && [ -f requirements.txt ] && pip-audit -r requirements.txt 2>/dev/null | tail -8

echo; echo "== ROUTE INVENTORY (every one needs an authz decision, §4.1 API9)"
s "routes/handlers" "(app|router|server)\.(get|post|put|patch|delete|all)\(['\"]|@(app|router)\.(get|post|put|patch|delete)\(|export (async )?function (GET|POST|PUT|PATCH|DELETE)\b|'use server'|\bon\(['\"](GET|POST|PUT|PATCH|DELETE)['\"]|route\(['\"](GET|POST|PUT|PATCH|DELETE)"
echo; echo "done. Confirm every lead by reading the code before reporting it."
