#!/usr/bin/env bash
# ------------------------------------------------------------
# status.sh  —  Affiche l'état de la stack et des sauvegardes.
# Usage : ./scripts/status.sh
# ------------------------------------------------------------
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

GREEN="\033[0;32m"; RED="\033[0;31m"; YEL="\033[0;33m"; RST="\033[0m"

ok()   { echo -e "  ${GREEN}✔${RST} $*"; }
warn() { echo -e "  ${YEL}⚠${RST} $*"; }
bad()  { echo -e "  ${RED}✘${RST} $*"; }

echo "🌐 CloudCLI / multi-agents — status"
echo

# --- Docker stack ---
if docker compose ps --services >/dev/null 2>&1; then
  RUNNING=$(docker compose ps --status running --format '{{.Name}}' | wc -l)
  TOTAL=$(docker compose ps --services | wc -l)
  if [ "$RUNNING" -eq "$TOTAL" ]; then
    ok "Docker stack : $RUNNING/$TOTAL conteneurs en cours d'exécution"
  else
    warn "Docker stack : $RUNNING/$TOTAL conteneurs en cours d'exécution"
  fi
  docker compose ps
else
  bad "Docker stack : inaccessible (vérifie Docker / docker compose)"
fi
echo

# --- Sauvegarde auto (cron) ---
if [ -L /etc/cron.daily/cloudcli-snapshot ]; then
  TARGET=$(readlink -f /etc/cron.daily/cloudcli-snapshot)
  ok "Sauvegarde automatique (cron.daily) : $TARGET"
else
  warn "Pas de lien /etc/cron.daily/cloudcli-snapshot (lance sudo install.sh pour le recréer)"
fi

if [ -f /var/log/cloudcli-snapshot.log ]; then
  LAST=$(tail -n 20 /var/log/cloudcli-snapshot.log | grep "Terminé\|snapshot auto OK" | tail -n1)
  if [ -n "$LAST" ]; then
    ok "Dernier snapshot auto : $LAST"
  fi
else
  warn "Fichier de log /var/log/cloudcli-snapshot.log absent (le cron n'a pas encore tourné)"
fi
echo

# --- Snapshots existants ---
if ls backups/*.tar.gz >/dev/null 2>&1; then
  N=$(ls -1 backups/*.tar.gz | wc -l)
  SIZE=$(du -sh backups | cut -f1)
  ok "Snapshots présents : $N archives dans backups/ ($SIZE)"
  echo
  ls -lht backups/*.tar.gz | head -n 10 | awk '{printf "   %-6s %-20s %s\n", $5, $6" "$7" "$8, $9}'
else
  warn "Aucun snapshot dans backups/ pour le moment."
  echo "   Pour en créer un tout de suite : ./scripts/snapshot.sh test"
fi
echo

# --- Rappel des URLs ---
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo "🔗 URLs (depuis un navigateur) :"
echo "   CloudCLI    : https://${IP:-<IP-de-la-VM>}/"
echo "   code-server : https://${IP:-<IP-de-la-VM>}/ide/"
