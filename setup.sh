#!/usr/bin/env bash
# =================================================================
# VMREMOTEAGENT — Installateur UNE COMMANDE
# CloudCLI (Claude Code + Codex) + code-server + Caddy + backups auto
# Backend : Ollama Cloud.
#
# Usage :
#   curl -fsSL https://raw.githubusercontent.com/Tiij/VMREMOTEAGENT/main/setup.sh | bash
#
# Ou avec une clé Ollama pré-remplie, sans interaction :
#   curl -fsSL https://.../setup.sh | OLLAMA_API_KEY=sk-ollama-xxx bash
#
# Variables d'environnement supportées :
#   INSTALL_DIR       (défaut: /opt/multi-agents)
#   OLLAMA_API_KEY    (si non défini = demande interactive)
#   HOSTNAME_PUBLIQUE (IP publique ou domaine ; si non défini = détection auto)
#   BIND_IFACE        (interface utilisée pour détecter l'IP, défaut: la première)
#   NO_BUILD          ("1" pour ne pas lancer docker compose à la fin)
# =================================================================
set -euo pipefail

# ---------- Variables ----------
INSTALL_DIR="${INSTALL_DIR:-/opt/multi-agents}"
LOG_FILE="$INSTALL_DIR/install.log"
RED='\033[0;31m'; GREEN='\033[0;32m'; YEL='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

banner() { echo -e "${CYAN}
╔══════════════════════════════════════════════════════════╗
║   VMREMOTEAGENT — CloudCLI + Claude Code + Codex         ║
║   code-server + Caddy HTTPS + sauvegardes automatiques   ║
╚══════════════════════════════════════════════════════════╝${NC}"; }

step()    { echo -e "${GREEN}▶${NC} $*"; }
warn()    { echo -e "${YEL}⚠${NC}  $*"; }
die()     { echo -e "${RED}✘${NC}  $*" >&2; exit 1; }
ok()      { echo -e "${GREEN}✔${NC} $*"; }

# ---------- Pré-requis ----------
banner

if [ "$(id -u)" -ne 0 ]; then
  die "Ce script doit être lancé en ROOT (utilise sudo ou connecte-toi en root)."
fi

# Création répertoire d'install
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
: > "$LOG_FILE"
log() { echo "$*" | tee -a "$LOG_FILE" >/dev/null; }

step "Détection du système..."
ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
case "$ARCH" in
  amd64|x86_64) ARCH_ALT="x86_64" ;;
  arm64|aarch64) ARCH_ALT="aarch64" ;;
  *) die "Architecture non supportée : $ARCH (amd64 et arm64 uniquement)." ;;
esac

if [ -r /etc/os-release ]; then
  . /etc/os-release
else
  die "Impossible de détecter l'OS (/etc/os-release absent)."
fi

case "$ID" in
  debian|ubuntu) ;;
  *) warn "OS détecté : $ID — ce script est testé sur Debian 12 et Ubuntu 22.04/24.04." ;;
esac
ok "OS : $ID $VERSION_ID  •  Architecture : $ARCH"

# ---------- Clé API Ollama Cloud ----------
if [ -z "${OLLAMA_API_KEY:-}" ]; then
  echo
  echo -e "${CYAN}🔑 Clé API Ollama Cloud${NC}"
  echo "   Crée-la sur : https://ollama.com/settings/keys"
  echo -n "   Colle ta clé (sk-ollama-...) : "
  stty -echo 2>/dev/null || true
  IFS= read -r OLLAMA_API_KEY
  stty echo 2>/dev/null || true
  echo
  if [ -z "$OLLAMA_API_KEY" ]; then
    die "Clé API vide, annulation."
  fi
fi
ok "Clé API Ollama Cloud configurée"

# ---------- Adresse publique ----------
if [ -z "${HOSTNAME_PUBLIQUE:-}" ]; then
  step "Détection de l'IP publique..."
  HOSTNAME_PUBLIQUE=$(curl -4 -fsSL --max-time 5 https://api.ipify.org 2>/dev/null \
                 || curl -4 -fsSL --max-time 5 https://ifconfig.me   2>/dev/null \
                 || hostname -I 2>/dev/null | awk '{print $1}' \
                 || echo "localhost")
  ok "IP/host détecté : $HOSTNAME_PUBLIQUE"
  echo -n "   → Appuyez sur Entrée pour valider, ou entrez un autre host/domaine : "
  IFS= read -r CUSTOM_HOST
  [ -n "$CUSTOM_HOST" ] && HOSTNAME_PUBLIQUE="$CUSTOM_HOST"
fi

# ---------- Outils de base ----------
step "Mise à jour des paquets et installation des outils de base..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates curl git wget sudo nano gnupg lsb-release \
  vim-common cron coreutils procps jq
ok "Outils système installés"

# ---------- Docker ----------
if command -v docker >/dev/null 2>&1; then
  ok "Docker déjà installé : $(docker --version)"
else
  step "Installation de Docker (officiel)..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${ID}/gpg" 2>/dev/null | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes || \
  curl -fsSL https://download.docker.com/linux/debian/gpg | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io \
                     docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  ok "Docker installé"
fi

# Vérification docker fonctionnel
if ! docker info >/dev/null 2>&1; then
  die "Docker ne répond pas. Vérifie avec 'systemctl status docker'."
fi

# ---------- Écriture des fichiers ----------
step "Écriture des fichiers de configuration dans $INSTALL_DIR ..."

mkdir -p "$INSTALL_DIR"/{cloudcli,scripts,backups}

# .env
SECRET=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 64)
BASIC_AUTH_PASS=$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 16)
cat > "$INSTALL_DIR/.env" <<EOF
# Généré automatiquement par setup.sh le $(date -Iseconds)
OLLAMA_API_KEY=${OLLAMA_API_KEY}
WEBUI_URL=https://${HOSTNAME_PUBLIQUE}
ENABLE_SIGNUP=true
WEBUI_SECRET_KEY=${SECRET}
BASIC_AUTH_USER=agent
BASIC_AUTH_PASS=${BASIC_AUTH_PASS}
OPEN_TERMINAL_KEY=${SECRET}
EOF
chmod 600 "$INSTALL_DIR/.env"

# docker-compose.yml
cat > "$INSTALL_DIR/docker-compose.yml" <<'EOF'
services:
  cloudcli:
    build: ./cloudcli
    image: multi-agents-cloudcli:latest
    container_name: cloudcli
    restart: unless-stopped
    environment:
      - OLLAMA_API_KEY=${OLLAMA_API_KEY}
      - SERVER_PORT=3001
      - HOST=0.0.0.0
    volumes:
      - cloudcli-data:/home/agent/.cloudcli
      - claude-data:/home/agent/.claude
      - codex-data:/home/agent/.codex
      - codeserver-data:/home/agent/.local/share/code-server
      - codeserver-config:/home/agent/.config/code-server
      - projects:/home/agent/workspace
    shm_size: "2g"
    networks: [agent-net]
    expose: ["3001", "8080"]

  caddy:
    image: caddy:2-alpine
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data
      - caddy-config:/config
    networks: [agent-net]
    depends_on: [cloudcli]

volumes:
  cloudcli-data:
  claude-data:
  codex-data:
  codeserver-data:
  codeserver-config:
  projects:
  caddy-data:
  caddy-config:

networks:
  agent-net:
    driver: bridge
EOF

# Caddyfile
cat > "$INSTALL_DIR/Caddyfile" <<'EOF'
:80, :443 {
    request_body { max_size 500MB }

    handle_path /ide/* {
        rewrite /ide/* /{uri_slice[2:]}
        reverse_proxy cloudcli:8080 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-Proto {scheme}
            header_up X-Forwarded-Prefix /ide/
            header_up Upgrade {>Upgrade}
            header_up Connection {>Connection}
            transport http { response_header_timeout 0 }
        }
    }

    handle /* {
        reverse_proxy cloudcli:3001 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-Proto {scheme}
            header_up Upgrade {>Upgrade}
            header_up Connection {>Connection}
            transport http { response_header_timeout 0 }
        }
    }

    header {
        X-Content-Type-Options nosniff
        X-Frame-Options SAMEORIGIN
        Referrer-Policy strict-origin-when-cross-origin
        -Server
    }

    tls internal
    flush_interval -1
}
EOF

# cloudcli/Dockerfile
cat > "$INSTALL_DIR/cloudcli/Dockerfile" <<'EOF'
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 LC_ALL=C.UTF-8 TZ=Europe/Paris

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget git unzip zip jq sudo htop tmux neovim ripgrep fd-find \
      build-essential python3 python3-pip python3-venv pipx \
      openssh-client gnupg procps xz-utils supervisor tini \
      chromium fonts-noto-color-emoji \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g npm@latest

RUN npm install -g @anthropic-ai/claude-code @openai/codex @cloudcli-ai/cloudcli

RUN curl -fsSL https://code-server.dev/install.sh | sh \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 1000 agent -s /bin/bash \
    && echo "agent ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agent \
    && mkdir -p /home/agent/.cloudcli /home/agent/.claude /home/agent/.codex \
                 /home/agent/.local/share/code-server \
                 /home/agent/.config/code-server \
                 /home/agent/workspace /home/agent/.cache \
    && chown -R agent:agent /home/agent

RUN cat > /home/agent/.codex/config.toml <<'CODEOF'
model_provider = "ollama_cloud"
model = "qwen3-coder:cloud"

[model_providers.ollama_cloud]
name = "Ollama Cloud"
base_url = "https://ollama.com/v1"
env_key = "OLLAMA_API_KEY"

oss_provider = "ollama_cloud"
CODEOF

RUN cat > /home/agent/.config/code-server/config.yaml <<'CODEOF'
bind-addr: 0.0.0.0:8080
auth: none
disable-telemetry: true
disable-update-check: true
CODEOF
RUN chown -R agent:agent /home/agent/.config

ENV ANTHROPIC_BASE_URL=https://ollama.com \
    ANTHROPIC_AUTH_TOKEN=__OLLAMA_API_KEY__ \
    ANTHROPIC_API_KEY="" \
    ANTHROPIC_MODEL=qwen3-coder:cloud \
    ANTHROPIC_SMALL_FAST_MODEL=qwen3-coder:cloud \
    ANTHROPIC_DEFAULT_SONNET_MODEL=qwen3-coder:cloud \
    ANTHROPIC_DEFAULT_HAIKU_MODEL=qwen3-coder:cloud \
    ANTHROPIC_DEFAULT_OPUS_MODEL=qwen3-coder:cloud \
    OPENAI_BASE_URL=https://ollama.com/v1 \
    OPENAI_API_KEY=__OLLAMA_API_KEY__ \
    CHROME_BIN=/usr/bin/chromium \
    SERVER_PORT=3001 \
    HOST=0.0.0.0 \
    DATABASE_PATH=/home/agent/.cloudcli/auth.db

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

WORKDIR /home/agent/workspace
USER agent

COPY --chown=agent:agent entrypoint.sh /home/agent/entrypoint.sh
USER root
RUN chmod +x /home/agent/entrypoint.sh && chown agent:agent /home/agent/entrypoint.sh
USER agent

EXPOSE 3001 8080
ENTRYPOINT ["/usr/bin/tini", "--", "/home/agent/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
EOF

# cloudcli/entrypoint.sh
cat > "$INSTALL_DIR/cloudcli/entrypoint.sh" <<'EOF'
#!/bin/bash
set -e

KEY="${OLLAMA_API_KEY:-ollama}"
export ANTHROPIC_AUTH_TOKEN="$KEY"
export OPENAI_API_KEY="$KEY"

cat >> /home/agent/.bashrc <<BASHEOF
export OLLAMA_API_KEY="$KEY"
export ANTHROPIC_BASE_URL=https://ollama.com
export ANTHROPIC_AUTH_TOKEN="$KEY"
export ANTHROPIC_API_KEY=""
export ANTHROPIC_MODEL=qwen3-coder:cloud
export ANTHROPIC_SMALL_FAST_MODEL=qwen3-coder:cloud
export ANTHROPIC_DEFAULT_SONNET_MODEL=qwen3-coder:cloud
export ANTHROPIC_DEFAULT_HAIKU_MODEL=qwen3-coder:cloud
export ANTHROPIC_DEFAULT_OPUS_MODEL=qwen3-coder:cloud
export OPENAI_BASE_URL=https://ollama.com/v1
export OPENAI_API_KEY="$KEY"
BASHEOF

mkdir -p /home/agent/.claude
cat > /home/agent/.claude/settings.json <<JSONEOF
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://ollama.com",
    "ANTHROPIC_AUTH_TOKEN": "$KEY",
    "ANTHROPIC_API_KEY": "",
    "ANTHROPIC_MODEL": "qwen3-coder:cloud",
    "ANTHROPIC_SMALL_FAST_MODEL": "qwen3-coder:cloud",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "qwen3-coder:cloud",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "qwen3-coder:cloud",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "qwen3-coder:cloud"
  }
}
JSONEOF

sudo chown -R agent:agent /home/agent/.cloudcli /home/agent/.claude \
                           /home/agent/.codex /home/agent/workspace \
                           /home/agent/.config /home/agent/.local 2>/dev/null || true

cd /home/agent/workspace
exec "$@"
EOF
chmod +x "$INSTALL_DIR/cloudcli/entrypoint.sh"

# cloudcli/supervisord.conf
cat > "$INSTALL_DIR/cloudcli/supervisord.conf" <<'EOF'
[supervisord]
nodaemon=true
user=agent
logfile=/tmp/supervisord.log
pidfile=/tmp/supervisord.pid
logfile_maxbytes=10MB
logfile_backups=2

[program:cloudcli]
command=/usr/local/bin/cloudcli start --port 3001
directory=/home/agent/workspace
environment=HOME="/home/agent",USER="agent"
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
stopsignal=SIGTERM
stopwaitsecs=15

[program:codeserver]
command=/usr/bin/code-server --bind-addr 0.0.0.0:8080 --disable-telemetry --auth none /home/agent/workspace
directory=/home/agent/workspace
environment=HOME="/home/agent",USER="agent"
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
stopsignal=SIGTERM
stopwaitsecs=15
EOF

# ---------- Scripts de sauvegarde ----------
write_script() {
  local target="$1" perm="$2"; shift 2
  cat > "$target"
  chmod "$perm" "$target"
}

write_script "$INSTALL_DIR/scripts/snapshot.sh" 755 <<'SNAPEOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
BACKUP_DIR="$(pwd)/backups"
mkdir -p "$BACKUP_DIR"
NAME="${1:-snapshot-$(date +%Y%m%d-%H%M%S)}"
ARCHIVE="$BACKUP_DIR/${NAME}.tar.gz"
echo "📸 Snapshot : $ARCHIVE"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
VOLUMES=(
  multi-agents_cloudcli-data multi-agents_claude-data multi-agents_codex-data
  multi-agents_codeserver-data multi-agents_codeserver-config
  multi-agents_projects multi-agents_caddy-data multi-agents_caddy-config)
PREFIX="$(docker compose config --format json 2>/dev/null | grep -o '"Name":"[^"]*_cloudcli-data"' | head -n1 | sed 's/.*"Name":"//;s/_cloudcli-data.*//')"
[ -n "$PREFIX" ] && for i in "${!VOLUMES[@]}"; do VOLUMES[$i]="${PREFIX}_${VOLUMES[$i]#multi-agents_}"; done
mkdir -p "$TMP/volumes"
for V in "${VOLUMES[@]}"; do
  echo "  • export $V"
  docker run --rm -v "$V:/source:ro" -v "$TMP/volumes:/backup" alpine \
    sh -c "cd /source && tar czf /backup/${V}.tar.gz ."
done
mkdir -p "$TMP/config"
cp docker-compose.yml Caddyfile "$TMP/config/" 2>/dev/null || true
[ -f .env ] && cp .env "$TMP/config/.env"
cp -r cloudcli "$TMP/config/cloudcli" 2>/dev/null || true
{ echo "snapshot_date: $(date -Iseconds)"; echo "hostname: $(hostname)"; docker compose images; } > "$TMP/MANIFEST.txt"
tar czf "$ARCHIVE" -C "$TMP" .
SIZE=$(du -h "$ARCHIVE" | cut -f1)
echo "✅ $ARCHIVE  ($SIZE)"
SNAPEOF

write_script "$INSTALL_DIR/scripts/restore.sh" 755 <<'RESTEOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[ -z "${1:-}" ] && { echo "❌ Usage: $0 <nom-snapshot>"; ls -1 backups/*.tar.gz | xargs -n1 basename | sed 's/\.tar\.gz$//'; exit 1; }
INPUT="$1"
[ -f "$INPUT" ] && ARCHIVE="$INPUT" || \
[ -f "backups/$INPUT" ] && ARCHIVE="backups/$INPUT" || \
[ -f "backups/${INPUT}.tar.gz" ] && ARCHIVE="backups/${INPUT}.tar.gz" || \
  { echo "❌ Snapshot introuvable : $INPUT"; exit 1; }
read -p "⚠  Ceci REMPLACE l'état actuel. Taper OUI pour confirmer : " C
[ "$C" = "OUI" ] || { echo "Annulé."; exit 0; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "📦 Extraction..."
tar xzf "$ARCHIVE" -C "$TMP"
echo "🛑 Arrêt..."
docker compose down
PREFIX="$(docker compose config --format json 2>/dev/null | grep -o '"Name":"[^"]*_cloudcli-data"' | head -n1 | sed 's/.*"Name":"//;s/_cloudcli-data.*//')"
[ -z "$PREFIX" ] && PREFIX="multi-agents"
VOLS=(cloudcli-data claude-data codex-data codeserver-data codeserver-config projects caddy-data caddy-config)
for V in "${VOLS[@]}"; do docker volume rm "${PREFIX}_$V" 2>/dev/null || true; done
echo "♻️  Import..."
for V in "${VOLS[@]}"; do
  F="$TMP/volumes/${PREFIX}_$V.tar.gz"
  [ ! -f "$F" ] && F="$TMP/volumes/multi-agents_$V.tar.gz"
  [ ! -f "$F" ] && { echo "⚠  Volume $V absent, ignoré."; continue; }
  docker volume create "${PREFIX}_$V" >/dev/null
  docker run --rm -v "${PREFIX}_$V:/target" -v "$TMP/volumes:/backup:ro" alpine \
    sh -c "cd /target && tar xzf /backup/$(basename "$F")"
done
echo "▶️  Redémarrage..."
docker compose up -d --build
echo "✅ Restauration terminée."
RESTEOF

write_script "$INSTALL_DIR/scripts/factory-reset.sh" 755 <<'FACEOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
read -p "⚠ TOUT SUPPRIMER (projets, sessions, comptes) ? Taper 'SUPPRIMER TOUT' : " C
[ "$C" != "SUPPRIMER TOUT" ] && { echo "Annulé."; exit 0; }
echo "🛑 Arrêt + suppression des volumes..."
docker compose down -v
echo "✅ Reset. Relance avec : docker compose up -d --build"
FACEOF

write_script "$INSTALL_DIR/scripts/auto-snapshot.sh" 755 <<'AUTOEOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"
KEEP="${SNAPSHOT_KEEP:-14}"
LOG_FILE="${SNAPSHOT_LOG:-/var/log/cloudcli-snapshot.log}"
mkdir -p backups "$(dirname "$LOG_FILE")"
ts(){ date '+%Y-%m-%d %H:%M:%S'; }
log(){ echo "[$(ts)] $*" | tee -a "$LOG_FILE"; }
log "📸 Snapshot auto (KEEP=$KEEP)"
NAME="auto-$(date +%Y%m%d-%H%M%S)"
if ./scripts/snapshot.sh "$NAME" >>"$LOG_FILE" 2>&1; then
  log "✅ backups/${NAME}.tar.gz"
else
  log "❌ ERREUR"; exit 1
fi
mapfile -t OLD < <(ls -1t backups/auto-*.tar.gz 2>/dev/null | tail -n +$((KEEP+1)))
((${#OLD[@]}>0)) && { log "🗑 Suppression ${#OLD[@]} anciens auto"; rm -f "${OLD[@]}"; }
DEL=$(find backups -maxdepth 1 -name "snapshot-*.tar.gz" -mtime +30 -print -delete 2>/dev/null | wc -l)
((DEL>0)) && log "🗑 $DEL snapshot(s) manuel(s) >30j supprimé(s)"
SIZE=$(du -sh backups | cut -f1); COUNT=$(ls -1 backups/*.tar.gz 2>/dev/null | wc -l)
log "📂 backups/ : $COUNT archives, $SIZE — terminé"
AUTOEOF

write_script "$INSTALL_DIR/scripts/status.sh" 755 <<'STATEOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
GREEN="\033[0;32m"; RED="\033[0;31m"; YEL="\033[0;33m"; NC="\033[0m"
ok(){ echo -e "  ${GREEN}✔${NC} $*"; }
warn(){ echo -e "  ${YEL}⚠${NC} $*"; }
bad(){ echo -e "  ${RED}✘${NC} $*"; }
echo "🌐 VMREMOTEAGENT — status"
echo
if docker compose ps --services >/dev/null 2>&1; then
  R=$(docker compose ps --status running --format '{{.Name}}' | wc -l)
  T=$(docker compose ps --services | wc -l)
  [ "$R" -eq "$T" ] && ok "Stack : $R/$T conteneurs Up" || warn "Stack : $R/$T conteneurs Up"
  docker compose ps
else
  bad "Stack inaccessible (vérifie Docker)"
fi
echo
if [ -L /etc/cron.daily/cloudcli-snapshot ]; then
  ok "Cron backup : $(readlink -f /etc/cron.daily/cloudcli-snapshot)"
else
  warn "Cron backup absent"
fi
if [ -f /var/log/cloudcli-snapshot.log ]; then
  LAST=$(tail -n 20 /var/log/cloudcli-snapshot.log | grep -E "terminé|snapshot auto OK" | tail -n1)
  [ -n "$LAST" ] && ok "Dernier backup : $LAST"
fi
echo
if ls backups/*.tar.gz >/dev/null 2>&1; then
  N=$(ls -1 backups/*.tar.gz | wc -l); S=$(du -sh backups | cut -f1)
  ok "$N snapshots ($S) dans backups/"
  ls -lht backups/*.tar.gz | head -n 10 | awk '{printf "   %-6s %-20s %s\n",$5,$6" "$7" "$8,$9}'
else
  warn "Aucun snapshot pour l'instant : ./scripts/snapshot.sh test"
fi
echo
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo "🔗 URLs : https://${IP:-<IP>}/   •   https://${IP:-<IP>}/ide/"
STATEOF

ok "Fichiers écrits dans $INSTALL_DIR"

# ---------- Sauvegarde automatique (cron) ----------
step "Configuration de la sauvegarde automatique quotidienne..."
ln -sf "$INSTALL_DIR/scripts/auto-snapshot.sh" /etc/cron.daily/cloudcli-snapshot
chmod +x "$INSTALL_DIR/scripts/"*.sh
systemctl enable --now cron 2>/dev/null || true
touch /var/log/cloudcli-snapshot.log
chmod 644 /var/log/cloudcli-snapshot.log
ok "Cron quotidien installé → /etc/cron.daily/cloudcli-snapshot"
ok "Logs : /var/log/cloudcli-snapshot.log"
ok "Rétention : 14 snapshots auto, 30 jours pour les manuels"

# ---------- Build & démarrage ----------
cd "$INSTALL_DIR"
if [ "${NO_BUILD:-}" = "1" ]; then
  warn "NO_BUILD=1 : démarrage ignoré. Lance plus tard :"
  echo "     cd $INSTALL_DIR && docker compose up -d --build"
else
  step "Build des images Docker et démarrage de la stack..."
  step "(Cela peut prendre 5-15 minutes au premier lancement.)"
  echo
  # Note : on ne bloque pas si le build échoue — on affiche un message
  if docker compose up -d --build; then
    ok "Stack démarrée"
  else
    warn "Le build a échoué. Ré-essaie avec : cd $INSTALL_DIR && docker compose up -d --build"
  fi
fi

# ---------- Message final ----------
echo
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅  Installation terminée !${NC}"
echo
echo -e "🔗 ${CYAN}CloudCLI (agents) :${NC}  https://${HOSTNAME_PUBLIQUE}/"
echo -e "🔗 ${CYAN}code-server (IDE):${NC}  https://${HOSTNAME_PUBLIQUE}/ide/"
echo
echo -e "🔑 ${CYAN}Compte CloudCLI :${NC}  définis un mot de passe à la 1ère visite."
if [ -n "$BASIC_AUTH_PASS" ]; then
  echo -e "🔐 ${CYAN}Mot de passe basique (si activé dans Caddy) :${NC}  agent / $BASIC_AUTH_PASS"
fi
echo
echo -e "⚠  Certificat auto-signé → accepte l'avertissement dans le navigateur."
echo -e "   Pour un vrai certificat : pointe un domaine vers l'IP, remplace"
echo -e "   ':80, :443' dans le Caddyfile par le domaine, supprime 'tls internal',"
echo -e "   puis 'docker compose restart caddy' (Let's Encrypt auto)."
echo
echo -e "📸 Sauvegarde avant une grosse mission :${NC}"
echo -e "     cd $INSTALL_DIR && ./scripts/snapshot.sh <nom>"
echo -e "♻️  Restaurer :${NC}  ./scripts/restore.sh <nom>"
echo -e "📊 État :${NC}      ./scripts/status.sh"
echo
echo -e "${CYAN}Log d'installation :${NC} $LOG_FILE"
echo -e "${CYAN}Dossier :${NC}           $INSTALL_DIR"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
