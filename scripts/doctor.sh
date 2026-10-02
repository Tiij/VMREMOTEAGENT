#!/usr/bin/env bash
# =============================================================
# VMREMOTEAGENT DOCTOR — Diagnostic & réparation
# Usage :
#   cd /opt/multi-agents && ./scripts/doctor.sh            # diagnostic interactif
#   cd /opt/multi-agents && ./scripts/doctor.sh --fix      # diagnostic + réparation auto
#   cd /opt/multi-agents && ./scripts/doctor.sh --fix --noninteractive
# =============================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

G="\033[0;32m"; R="\033[0;31m"; Y="\033[1;33m"; C="\033[0;36m"; NC="\033[0m"
hdr(){ echo -e "\n${C}═══ $* ═══${NC}"; }
ok(){  echo -e "  ${G}✔${NC} $*"; }
warn(){ echo -e "  ${Y}⚠${NC} $*"; }
bad(){  echo -e "  ${R}✘${NC} $*"; }

FIX=0; NONINT=0
for a in "$@"; do
  case "$a" in
    --fix)             FIX=1 ;;
    --noninteractive)  NONINT=1 ;;
    -h|--help)
      echo "Usage: $0 [--fix] [--noninteractive]"; exit 0 ;;
  esac
done

echo -e "${C}
╔══════════════════════════════════════════╗
║    🩺  VMREMOTEAGENT  —  Doctor          ║
║    Diagnostic & réparation automatique  ║
╚══════════════════════════════════════════╝${NC}"

PROBLEMS=0; CAN_FIX=0

# ---------- 1. Fichiers ----------
hdr "1. Fichiers de configuration"
REQUIRED_FILES=(
  docker-compose.yml Caddyfile .env
  dashboard/index.html
  cloudcli/Dockerfile cloudcli/entrypoint.sh cloudcli/supervisord.conf
  scripts/status.sh scripts/snapshot.sh scripts/doctor.sh
)
for f in "${REQUIRED_FILES[@]}"; do
  if [ -f "$f" ]; then ok "$f"
  else bad "manquant: $f"; PROBLEMS=$((PROBLEMS+1)); CAN_FIX=$((CAN_FIX+1)); fi
done
if [ -f .vmremoteagent.state ]; then
  V=$(grep -E '^version=' .vmremoteagent.state 2>/dev/null | cut -d= -f2 || echo "?")
  S=$(grep -E '^state='   .vmremoteagent.state 2>/dev/null | cut -d= -f2 || echo "?")
  ok "marqueur d'état présent ($S, v$V)"
else
  warn "marqueur d'état .vmremoteagent.state absent (installation incomplète ou ancienne)"
  CAN_FIX=$((CAN_FIX+1))
fi

# ---------- 2. Docker ----------
hdr "2. Docker"
if command -v docker >/dev/null 2>&1; then
  ok "docker $(docker --version 2>/dev/null | sed 's/Docker version //;s/,.*//')"
else
  bad "docker n'est pas installé"; PROBLEMS=$((PROBLEMS+1)); CAN_FIX=$((CAN_FIX+1))
fi
if docker info >/dev/null 2>&1; then
  ok "démon Docker répond"
else
  bad "démon Docker arrêté ou injoignable"; PROBLEMS=$((PROBLEMS+1)); CAN_FIX=$((CAN_FIX+1))
fi
if docker compose version >/dev/null 2>&1; then
  ok "docker compose $(docker compose version --short 2>/dev/null)"
else
  bad "plugin docker compose absent"; PROBLEMS=$((PROBLEMS+1)); CAN_FIX=$((CAN_FIX+1))
fi

# ---------- 3. Compose validity ----------
hdr "3. Configuration docker-compose"
if [ -f docker-compose.yml ]; then
  if docker compose config --quiet 2>/dev/null; then ok "compose valide"
  else bad "docker-compose.yml invalide"; PROBLEMS=$((PROBLEMS+1)); CAN_FIX=$((CAN_FIX+1)); fi
fi

# ---------- 4. Image ----------
hdr "4. Image Docker de la stack"
if docker image inspect multi-agents-cloudcli:latest >/dev/null 2>&1; then
  CREATED=$(docker image inspect multi-agents-cloudcli:latest -f '{{.Created}}' 2>/dev/null | cut -d. -f1)
  ok "multi-agents-cloudcli:latest (créée $CREATED)"
else
  warn "image multi-agents-cloudcli:latest absente (pas encore buildée ou à reconstruire)"
  CAN_FIX=$((CAN_FIX+1))
fi

# ---------- 5. Conteneurs ----------
hdr "5. Conteneurs"
for N in cloudcli caddy; do
  if docker ps --filter "name=^${N}$" --format '{{.Status}}' 2>/dev/null | grep -q Up; then
    ST=$(docker ps --filter "name=^${N}$" --format '{{.Status}}' 2>/dev/null)
    ok "$N : $ST"
  elif docker ps -a --filter "name=^${N}$" --format '{{.Names}}' 2>/dev/null | grep -q "$N"; then
    EXIT=$(docker ps -a --filter "name=^${N}$" --format '{{.Status}}' 2>/dev/null)
    bad "$N arrêté ($EXIT)"; PROBLEMS=$((PROBLEMS+1)); CAN_FIX=$((CAN_FIX+1))
  else
    warn "$N non créé (la stack n'a jamais été démarrée)"; CAN_FIX=$((CAN_FIX+1))
  fi
done

# ---------- 6. HTTP endpoints ----------
hdr "6. Connectivité (HTTPS local)"
if curl -kfsS --max-time 5 https://127.0.0.1/ -o /dev/null 2>/dev/null; then
  ok "dashboard https://127.0.0.1/ répond"
else
  bad "dashboard ne répond pas sur le port 443"; PROBLEMS=$((PROBLEMS+1))
fi
if curl -kfsS --max-time 5 https://127.0.0.1:3001/ -o /dev/null 2>/dev/null; then
  ok "CloudCLI https://127.0.0.1:3001/ répond"
else
  warn "CloudCLI sur :3001 ne répond pas encore (normal au premier démarrage, attendre 1-2 min)"
fi
if curl -kfsS --max-time 5 https://127.0.0.1/ide/ -o /dev/null 2>/dev/null; then
  ok "/ide/ (code-server) répond"
else
  warn "/ide/ ne répond pas encore (normal si cloudcli est encore en boot)"
fi

# ---------- 7. Cron & snapshots ----------
hdr "7. Sauvegardes"
if [ -L /etc/cron.daily/cloudcli-snapshot ]; then
  ok "lien cron installé ($(readlink -f /etc/cron.daily/cloudcli-snapshot))"
else
  warn "lien cron /etc/cron.daily/cloudcli-snapshot absent"; CAN_FIX=$((CAN_FIX+1))
fi
if ls backups/*.tar.gz >/dev/null 2>&1; then
  N=$(ls -1 backups/*.tar.gz 2>/dev/null | wc -l)
  S=$(du -sh backups 2>/dev/null | cut -f1)
  ok "$N snapshots ($S)"
  ls -lht backups/*.tar.gz 2>/dev/null | head -n3 | awk '{printf "     %-6s %s\n",$5,$6" "$7" "$8,$9}'
else
  warn "aucun snapshot — lancez ./scripts/snapshot.sh premier-test"
fi

# ---------- 8. .env ----------
hdr "8. Configuration .env"
if [ -f .env ]; then
  if grep -qE '^OLLAMA_API_KEY=sk-' .env; then ok "clé Ollama configurée"
  else bad "OLLAMA_API_KEY invalide dans .env"; PROBLEMS=$((PROBLEMS+1)); fi
  if grep -qE '^WEBUI_SECRET_KEY=.{16,}' .env; then ok "secret webui présent"
  else warn "WEBUI_SECRET_KEY absent ou trop court"; fi
  if grep -qE '^WEBUI_URL=https?://.+' .env; then ok "WEBUI_URL renseignée"
  else warn "WEBUI_URL manquant"; fi
else
  bad ".env absent"; PROBLEMS=$((PROBLEMS+1)); CAN_FIX=$((CAN_FIX+1))
fi

# ---------- 9. Ports host ----------
hdr "9. Ports hôtes (80/443/3001)"
for PORT in 80 443 3001; do
  if ss -ltnH "sport = :$PORT" 2>/dev/null | grep -q ":$PORT"; then
    LISTENER_PID=$(ss -ltnHp "sport = :$PORT" 2>/dev/null | grep -oP 'pid=\K[0-9]+' | head -n1 || echo "")
    LISTENER_NAME="?"
    [ -n "$LISTENER_PID" ] && LISTENER_NAME=$(ps -p "$LISTENER_PID" -o comm= 2>/dev/null || echo "?")
    case "$LISTENER_NAME" in
      docker-proxy|caddy|containerd-shim*|caddy)
        ok "port $PORT écouté par $LISTENER_NAME (Caddy/container docker : OK)" ;;
      "")
        ok "port $PORT en écoute" ;;
      *)
        bad "port $PORT occupé par $LISTENER_NAME (PID $LISTENER_PID) — conflit potentiel"
        PROBLEMS=$((PROBLEMS+1)) ;;
    esac
  else
    bad "port $PORT pas en écoute (Caddy n'est pas démarré?)"; PROBLEMS=$((PROBLEMS+1))
  fi
done

# ---------- Bilan ----------
echo
if [ "$PROBLEMS" -eq 0 ]; then
  echo -e "${G}✅ Tout semble opérationnel.${NC}"
  echo "state=healthy" > .vmremoteagent.state
  grep -qE '^version=' .vmremoteagent.state 2>/dev/null || echo "version=?" >> .vmremoteagent.state
  exit 0
fi

echo -e "${Y}${PROBLEMS} problème(s) détecté(s), ${CAN_FIX} peuvent être corrigés automatiquement.${NC}"

if [ "$FIX" -eq 0 ] && [ "$NONINT" -eq 0 ] && [ -t 0 ]; then
  echo ""
  read -p "Voulez-vous que le docteur répare automatiquement ? [O/n] " -n 1 -r R; echo
  case "$R" in n|N) echo "Annulé. Relancez avec ./scripts/doctor.sh --fix pour réparer."; exit 0;; esac
  FIX=1
fi

if [ "$FIX" -eq 1 ]; then
  hdr "🔧 Réparation"

  # Si Docker est absent, on ne peut pas aller loin
  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    bad "Docker indisponible. Relancez l'installateur :"
    echo "  curl -fsSL https://raw.githubusercontent.com/Tiij/VMREMOTEAGENT/main/setup.sh | sudo bash"
    exit 2
  fi

  # Fichiers ou image manquants → relancer setup.sh en mode repair
  NEED_REINSTALL=0
  for f in docker-compose.yml Caddyfile dashboard/index.html cloudcli/Dockerfile cloudcli/entrypoint.sh cloudcli/supervisord.conf; do
    [ ! -f "$f" ] && NEED_REINSTALL=1
  done
  if ! docker image inspect multi-agents-cloudcli:latest >/dev/null 2>&1; then
    NEED_REINSTALL=1
  fi

  if [ "$NEED_REINSTALL" -eq 1 ] && [ -x ./setup.sh ]; then
    warn "Fichiers ou image Docker manquants → relance de setup.sh en mode repair"
    FORCE_ACTION=repair NONINTERACTIVE=1 bash ./setup.sh
  elif [ "$NEED_REINSTALL" -eq 1 ] && [ ! -x ./setup.sh ]; then
    bad "setup.sh n'est pas présent dans $(pwd)."
    echo "  Relancez l'installation complète :"
    echo "  curl -fsSL https://raw.githubusercontent.com/Tiij/VMREMOTEAGENT/main/setup.sh | sudo bash"
    exit 2
  else
    # Conteneurs arrêtés ou instables → redémarrage simple
    warn "Redémarrage de la stack (up -d --remove-orphans)..."
    docker compose up -d --remove-orphans || warn "docker compose up a retourné une erreur (voir logs)"
    ok "Commande de relance envoyée. Les services démarrent en arrière-plan."
  fi

  # Recréer le lien cron s'il manque
  if [ ! -L /etc/cron.daily/cloudcli-snapshot ] && [ -x scripts/auto-snapshot.sh ]; then
    ln -sf "$(pwd)/scripts/auto-snapshot.sh" /etc/cron.daily/cloudcli-snapshot
    ok "lien cron recréé"
  fi

  # Snapshot de l'état
  if curl -kfsS --max-time 3 https://127.0.0.1/ -o /dev/null 2>/dev/null; then
    echo "state=healthy" > .vmremoteagent.state
  else
    echo "state=starting" > .vmremoteagent.state
  fi
  if ! grep -qE '^version=' .vmremoteagent.state 2>/dev/null; then
    echo "version=?" >> .vmremoteagent.state
  fi
  echo ""
  echo -e "${G}✅ Fin de la réparation.${NC}"
  echo "   Attendez 30-60 secondes le temps que CloudCLI et code-server démarrent,"
  echo "   puis relancez : ./scripts/doctor.sh"
  echo "   Pour les logs en direct : docker compose logs -f cloudcli"
fi
