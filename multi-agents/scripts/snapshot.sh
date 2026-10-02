#!/usr/bin/env bash
# ------------------------------------------------------------
# snapshot.sh  —  Crée un snapshot (archive .tar.gz) de TOUTE
# la stack CloudCLI (config, sessions Claude/Codex, projets,
# certificats Caddy, base SQLite CloudCLI).
#
# Usage :  ./scripts/snapshot.sh [nom_du_snapshot]
# Sans argument : nom automatique "snapshot-YYYYMMDD-HHMMSS.tar.gz"
# ------------------------------------------------------------
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
SCRIPT_DIR="$(pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backups"
mkdir -p "${BACKUP_DIR}"

NAME="${1:-snapshot-$(date +%Y%m%d-%H%M%S)}"
ARCHIVE="${BACKUP_DIR}/${NAME}.tar.gz"

echo "📸 Création du snapshot : ${ARCHIVE}"
echo

# 1) S'assurer que les conteneurs sont cohérents (flush des DB SQLite)
docker compose exec -T cloudcli bash -c 'pgrep -f cloudcli >/dev/null' 2>/dev/null || true

# 2) Exporter chaque volume Docker dans un tar temporaire,
#    puis sauvegarder aussi les bind mounts éventuels.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Liste des volumes à sauvegarder (doit correspondre à docker-compose.yml)
VOLUMES=(
  multi-agents_cloudcli-data
  multi-agents_claude-data
  multi-agents_codex-data
  multi-agents_codeserver-data
  multi-agents_codeserver-config
  multi-agents_projects
  multi-agents_caddy-data
  multi-agents_caddy-config
)

# Si le stack a été lancé depuis un autre nom de dossier, détecte
# dynamiquement le préfixe des volumes via docker compose.
PREFIX="$(docker compose config --format json | grep -o '"Name":"[^"]*_cloudcli-data"' | head -n1 | sed 's/.*"Name":"//;s/_cloudcli-data.*//')"
if [ -n "$PREFIX" ]; then
  for i in "${!VOLUMES[@]}"; do
    VOLUMES[$i]="${PREFIX}_${VOLUMES[$i]#multi-agents_}"
  done
fi

mkdir -p "$TMP/volumes"
for V in "${VOLUMES[@]}"; do
  echo "  • export volume $V ..."
  docker run --rm \
    -v "$V:/source:ro" \
    -v "$TMP/volumes:/backup" \
    alpine \
    sh -c "cd /source && tar czf /backup/${V}.tar.gz ."
done

# 3) Sauvegarder aussi les fichiers de config du host (Caddyfile, .env, etc.)
mkdir -p "$TMP/config"
cp docker-compose.yml Caddyfile .env "$TMP/config/" 2>/dev/null || true
[ -f .env ] && cp .env "$TMP/config/.env" || true
cp -r cloudcli "$TMP/config/cloudcli" 2>/dev/null || true

# Métadonnée : date + versions des images
{
  echo "snapshot_date: $(date -Iseconds)"
  echo "hostname: $(hostname)"
  echo "--- docker compose images ---"
  docker compose images
} > "$TMP/MANIFEST.txt"

# 4) Assembler l'archive finale
tar czf "${ARCHIVE}" -C "$TMP" .

# 5) Résumé
SIZE=$(du -h "${ARCHIVE}" | cut -f1)
echo
echo "✅ Snapshot créé : ${ARCHIVE}  (${SIZE})"
echo
echo "   Pour restaurer : ./scripts/restore.sh ${NAME}"
echo
echo "📂 Snapshots existants :"
ls -lh "${BACKUP_DIR}"/*.tar.gz 2>/dev/null | tail -n 10
