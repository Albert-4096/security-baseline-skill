#!/usr/bin/env bash
# Read-only security + freshness inventory of a Linux Docker host.
# Usage: bash audit-docker-host.sh [--remote-digests]
#   --remote-digests  also ask each registry for the current digest of every
#                     running image's tag (network, ~1-3 s per image).
#                     Each lookup counts against Docker Hub's anonymous pull
#                     quota (~100 per 6 h per IP): run 'docker login' first, or
#                     the later 'docker compose pull' fails with 429.
# Changes nothing. Needs no sudo (uses it only if passwordless sudo exists).
# Never prints secret values: env vars and mounts are listed by name/path only.

set -u
REMOTE=0; [ "${1:-}" = "--remote-digests" ] && REMOTE=1
SUDO=""; sudo -n true 2>/dev/null && SUDO="sudo -n"
h() { printf '\n===== %s =====\n' "$*"; }

h "HOST"
. /etc/os-release 2>/dev/null; echo "os: ${PRETTY_NAME:-unknown}  kernel: $(uname -r)  uptime: $(uptime -p)"
[ -f /var/run/reboot-required ] && echo "REBOOT REQUIRED: $(cat /var/run/reboot-required.pkgs 2>/dev/null | tr '\n' ' ')"
echo "passwordless sudo: $([ -n "$SUDO" ] && echo yes || echo no)"

h "OS PACKAGES (from the local apt cache; cache age shown)"
if command -v apt >/dev/null; then
  echo "apt lists last updated: $(stat -c %y /var/lib/apt/lists/partial 2>/dev/null | cut -d. -f1)"
  up=$(apt list --upgradable 2>/dev/null | tail -n +2)
  echo "upgradable: $(printf '%s' "$up" | grep -c . )   security: $(printf '%s' "$up" | grep -c -- '-security')"
  printf '%s\n' "$up" | grep -- '-security' | head -40
  systemctl is-enabled unattended-upgrades 2>/dev/null | sed 's/^/unattended-upgrades: /'
  grep -h 'Unattended-Upgrade "' /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null
  ls -t /var/log/unattended-upgrades/*.log 2>/dev/null | head -1 | xargs -r tail -n 3
fi

h "LISTENING SOCKETS (bind address matters: 0.0.0.0/[::] = all interfaces)"
ss -Htlnu 2>/dev/null | awk '{print $1, $5}' | sort -u -k2

h "FIREWALL"
if [ -n "$SUDO" ]; then $SUDO ufw status verbose 2>&1 | head -30; $SUDO iptables -S DOCKER-USER 2>&1 | head
else echo "ufw/iptables need root: not readable. NOTE: Docker-published ports bypass ufw unless DOCKER-USER rules exist."; fi
systemctl is-active fail2ban crowdsec 2>/dev/null | paste -sd' ' | sed 's/^/fail2ban crowdsec (host services): /'

h "SSH DAEMON CONFIG (effective lines)"
cat /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null \
  | grep -iE '^\s*(PermitRootLogin|PasswordAuthentication|KbdInteractiveAuthentication|PubkeyAuthentication|Port|AllowUsers|MaxAuthTries)\b'
echo "(first occurrence wins in sshd; files in sshd_config.d are read first via Include)"

if command -v docker >/dev/null; then
  h "DOCKER ENGINE"
  docker version --format 'server {{.Server.Version}}  client {{.Client.Version}}'
  [ -S /var/run/docker.sock ] && ls -l /var/run/docker.sock
  echo "users in docker group (== root on host): $(getent group docker | cut -d: -f4)"

  h "CONTAINERS: exposure and privilege"
  echo "name | image | user | privileged | netmode | caps | docker.sock | published(hostIp:port) | memlimit | restart"
  for c in $(docker ps -q); do
    docker inspect "$c" --format '{{.Name}} | {{.Config.Image}} | {{if .Config.User}}{{.Config.User}}{{else}}ROOT?{{end}} | {{.HostConfig.Privileged}} | {{.HostConfig.NetworkMode}} | {{.HostConfig.CapAdd}} | {{range .Mounts}}{{if eq .Source "/var/run/docker.sock"}}SOCK{{end}}{{end}} | {{range $p,$b := .NetworkSettings.Ports}}{{range $b}}{{.HostIp}}:{{.HostPort}}->{{$p}} {{end}}{{end}} | {{.HostConfig.Memory}} | {{.HostConfig.RestartPolicy.Name}}' | sed 's#^/##'
  done
  echo "(ROOT? = image sets no USER; the process may still drop privileges itself. Check before reporting.)"

  h "CONTAINERS: env var NAMES that look secret (values never printed)"
  for c in $(docker ps -q); do
    n=$(docker inspect "$c" --format '{{.Name}}' | sed 's#^/##')
    docker inspect "$c" --format '{{range .Config.Env}}{{println .}}{{end}}' \
      | cut -d= -f1 | grep -iE 'pass|secret|token|key|auth' | paste -sd, | sed "s#^#$n: #"
  done

  h "IMAGE FRESHNESS (image build date, tag, and optional remote digest compare)"
  echo "container | image ref | image built | local digest == remote?"
  for c in $(docker ps -q); do
    n=$(docker inspect "$c" --format '{{.Name}}' | sed 's#^/##')
    ref=$(docker inspect "$c" --format '{{.Config.Image}}')
    iid=$(docker inspect "$c" --format '{{.Image}}')
    built=$(docker image inspect "$iid" --format '{{.Created}}' 2>/dev/null | cut -dT -f1)
    rd=$(docker image inspect "$iid" --format '{{range .RepoDigests}}{{.}} {{end}}' 2>/dev/null)
    status="local-build"
    if [ -n "$rd" ]; then
      status="not-checked"
      if [ $REMOTE = 1 ]; then
        err=$(mktemp)
        remote=$(timeout 20 docker buildx imagetools inspect "$ref" --format '{{json .Manifest.Digest}}' 2>"$err" | tr -d '"')
        if [ -z "$remote" ]; then
          why=$(grep -oiE 'toomanyrequests|429|unauthorized|denied|not found|timeout|no such host' "$err" | head -1)
          status="lookup-failed(${why:-timeout})"
          [ "$why" = "toomanyrequests" ] || [ "$why" = "429" ] && { echo "!! registry rate limit hit: stop remote checks; run 'docker login' or retry in 6h"; REMOTE=0; }
        elif printf '%s' "$rd" | grep -q "$remote"; then status="UP-TO-DATE"
        else status="OUTDATED (remote ${remote:7:12})"; fi
        rm -f "$err"
      fi
    fi
    echo "$n | $ref | $built | $status"
  done
  echo "(local-build = no registry digest: rebuild from source to update base image + deps.)"
fi

h "WORLD-READABLE SECRET FILES under \$HOME (depth 4, names only)"
find "$HOME" -maxdepth 4 \( -name '.env' -o -name '*.env' -o -name '*.pem' -o -name '*.key' -o -name '*.pass' -o -name 'credentials*.json' \) \
  -perm -o=r -not -path '*/node_modules/*' 2>/dev/null | head -40

h "CRON (current user)"
crontab -l 2>/dev/null | grep -v '^#' | grep .
echo; echo "done: $(date -Is)"
