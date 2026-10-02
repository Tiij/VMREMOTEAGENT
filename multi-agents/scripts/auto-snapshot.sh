#!/usr/bin/env bash
# ------------------------------------------------------------
# auto-snapshot.sh  —  Wrapper pour cron/systemd-timer : prend
# un snapshot automatiquement et ne garde que les N derniers.
#
# Par défaut : 14 snapshots auto conservés, 30 jours pour les manuels.
# Modifiable via la variable d'env SNAPSHOT_KEEP.
#
# Installation (fait aussi par install.sh) :
#   ln -sf /opt/multi-agents/scripts/auto-snapshot.sh /etc/cron.daily/cloudcli-snapshot
#
# Ou en ligne crontab explicite (3h00 du matin) :
#   0 3 * * * /opt/multi-agents/scripts/auto-snapshot.sh >> /var/log/cloudcli-snapshot.log 2>&1
# ------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

KEEP="${SNAPSHOT_KEEP:-14}"
LOG_DIR="${SNAPSHOT_LOG_DIR:-/var/log}"
LOG_FILE="${LOG_DIR}/cloudcli-snapshot.log"
mkdir -p "$(dirname "$LOG_FILE")" "$SCRIPT_DIR/backups"

ts() { date '+%Y-%m-%d %H:%M:%S'; }

log() { echo "[$(ts)] $*" | tee -a "$LOG_FILE"; }

log "📸 Démarrage snapshot automatique (KEEP=$KEEP)"

# Création du snapshot
NAME="auto-$(date +%Y%m%d-%H%M%S)"
if ./scripts/snapshot.sh "$NAME" >> "$LOG_FILE" 2>&1; then
  log "✅ Snapshot créé : backups/${NAME}.tar.gz"
else
  log "❌ ERREUR pendant la création du snapshot (voir log ci-dessus)"
  exit 1
fi

# Rotation des auto-* : ne garder que les N plus récentes
mapfile -t OLD_AUTO < <(ls -1t "$SCRIPT_DIR/backups"/auto-*.tar.gz 2>/dev/null | tail -n +$((KEEP+1)))
if (( ${#OLD_AUTO[@]} > 0 )); then
  log "🗑️  Rotation : suppression de ${#OLD_AUTO[@]} ancien(s) snapshot(s) auto"
  rm -f "${OLD_AUTO[@]}"
fi

# Nettoyer les snapshots manuels > 30 jours
DELETED_MANUAL=$(find "$SCRIPT_DIR/backups" -maxdepth 1 -name "snapshot-*.tar.gz" -mtime +30 -print -delete 2>/dev/null | wc -l)
if (( DELETED_MANUAL > 0 )); then
  log "🗑️  Nettoyage : $DELETED_MANUAL snapshot(s) manuel(s) de +30j supprimé(s)"
fi

# Résumé
SIZE=$(du -sh "$SCRIPT_DIR/backups" | cut -f1)
COUNT=$(ls -1 "$SCRIPT_DIR/backups"/*.tar.gz 2>/dev/null | wc -l)
log "📂 backups/ : $COUNT archives, taille totale $SIZE"
log "🏁 Terminé"
echo                                                     # séparateur dans le log
