#!/usr/bin/env bash
# ------------------------------------------------------------
# factory-reset.sh  —  Remet la stack à ZÉRO (supprime tous les
# volumes : projets, sessions, comptes CloudCLI, config).
# Les images Docker ne sont pas supprimées.
#
# Usage :  ./scripts/factory-reset.sh
# ------------------------------------------------------------
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "⚠️  ATTENTION : CE SCRIPT SUPPRIME DÉFINITIVEMENT :"
echo "   • TOUS les projets dans le workspace"
echo "   • TOUTES les sessions Claude Code / Codex"
echo "   • Le compte/mot de passe CloudCLI"
echo "   • Les données Caddy (certificats)"
echo
echo "   (Les images Docker sont conservées.)"
echo
read -p "Taper 'SUPPRIMER TOUT' pour confirmer : " CONFIRM
if [ "$CONFIRM" != "SUPPRIMER TOUT" ]; then
  echo "Annulé."
  exit 0
fi

echo "🛑 Arrêt + suppression des conteneurs et volumes..."
docker compose down -v

echo "🔧 Nettoyage des dossiers bind-mount éventuels..."
rm -rf ./data 2>/dev/null || true

echo
echo "✅ Reset effectué. Tu peux relancer avec : docker compose up -d --build"
