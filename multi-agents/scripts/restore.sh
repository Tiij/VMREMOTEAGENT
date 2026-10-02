#!/usr/bin/env bash
# ------------------------------------------------------------
# restore.sh  —  Restaure un snapshot créé par snapshot.sh.
# Arrête les conteneurs, efface les volumes courants, réimporte
# les données de l'archive puis redémarre.
#
# Usage :  ./scripts/restore.sh <nom-du-snapshot>
#   (on peut passer le nom sans .tar.gz, sans le chemin backups/)
# ------------------------------------------------------------
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
SCRIPT_DIR="$(pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backups"

if [ -z "${1:-}" ]; then
  echo "❌ Usage : $0 <nom-du-snapshot>"
  echo "Snapshots disponibles :"
  ls -1 "${BACKUP_DIR}"/*.tar.gz 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/\.tar\.gz$//'
  exit 1
fi

# Accepte "mon-snap", "mon-snap.tar.gz", ou "./backups/mon-snap.tar.gz"
INPUT="$1"
if [ -f "$INPUT" ]; then
  ARCHIVE="$INPUT"
elif [ -f "${BACKUP_DIR}/${INPUT}" ]; then
  ARCHIVE="${BACKUP_DIR}/${INPUT}"
elif [ -f "${BACKUP_DIR}/${INPUT}.tar.gz" ]; then
  ARCHIVE="${BACKUP_DIR}/${INPUT}.tar.gz"
else
  echo "❌ Snapshot introuvable : $INPUT"
  exit 1
fi

echo "⚠️  ATTENTION : la restauration REMPLACE toutes les données"
echo "   actuelles (projets, sessions, config) par celles du snapshot."
echo
read -p "Continuer ? [tapez OUI en majuscules] : " CONFIRM
if [ "$CONFIRM" != "OUI" ]; then
  echo "Annulé."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "📦 Extraction de l'archive..."
tar xzf "${ARCHIVE}" -C "$TMP"

echo "🛑 Arrêt de la stack..."
docker compose down

# Détection du préfixe des volumes
PREFIX="$(docker compose config --format json | grep -o '"Name":"[^"]*_cloudcli-data"' | head -n1 | sed 's/.*"Name":"//;s/_cloudcli-data.*//')"
if [ -z "$PREFIX" ]; then
  echo "⚠️  Aucun projet docker compose détecté, on suppose 'multi-agents'"
  PREFIX="multi-agents"
fi

echo "🗑️  Suppression des volumes existants..."
VOLUMES=(
  "${PREFIX}_cloudcli-data"
  "${PREFIX}_claude-data"
  "${PREFIX}_codex-data"
  "${PREFIX}_codeserver-data"
  "${PREFIX}_codeserver-config"
  "${PREFIX}_projects"
  "${PREFIX}_caddy-data"
  "${PREFIX}_caddy-config"
)
for V in "${VOLUMES[@]}"; do
  docker volume rm "$V" 2>/dev/null || true
done

echo "♻️  Recréation des volumes vides + import..."
mkdir -p "$TMP/volumes"
for V in "${VOLUMES[@]}"; do
  ARCHIVE_VOL="$TMP/volumes/${V}.tar.gz"
  if [ ! -f "$ARCHIVE_VOL" ]; then
    echo "  ⚠️  Volume $V absent du snapshot, ignoré."
    continue
  fi
  echo "  • import volume $V ..."
  docker volume create "$V" >/dev/null
  docker run --rm \
    -v "$V:/target" \
    -v "$TMP/volumes:/backup:ro" \
    alpine \
    sh -c "cd /target && tar xzf /backup/${V}.tar.gz"
done

echo "▶️  Redémarrage..."
docker compose up -d --build

echo
echo "✅ Restauration terminée."
echo "   Vérifie avec : docker compose ps && docker compose logs -f cloudcli"
