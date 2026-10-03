#!/usr/bin/env bash
# =====================================================================
#  INSTALLATEUR SÛR — VMREMOTEAGENT
#  Télécharge setup.sh en ENTIER avant de l'exécuter, évitant les
#  plantages "syntax error: unexpected end of file" causés par curl
#  qui tronque le script en milieu de téléchargement quand on pipe
#  directement (curl | bash).
#
#  Usage :
#    curl -fsSL https://raw.githubusercontent.com/Tiij/VMREMOTEAGENT/main/install.sh -o /tmp/vmra-install.sh
#    sudo OLLAMA_API_KEY=sk-... HOSTNAME_PUBLIQUE=1.2.3.4 bash /tmp/vmra-install.sh
#
#  Ou encore plus simple (one-liner SÛR) :
#    curl -fsSL https://raw.githubusercontent.com/Tiij/VMREMOTEAGENT/main/install.sh | sudo bash -s -- OLLAMA_API_KEY=sk-... HOSTNAME_PUBLIQUE=1.2.3.4
# =====================================================================
set -euo pipefail

REPO_URL="${REPO_URL:-https://raw.githubusercontent.com/Tiij/VMREMOTEAGENT/main}"
SETUP_URL="${SETUP_URL:-$REPO_URL/setup.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "» Téléchargement de setup.sh depuis $SETUP_URL ..."
if ! curl -fL --retry 3 --retry-delay 2 --max-time 60 -o "$TMP/setup.sh" "$SETUP_URL"; then
  echo "✘ Échec du téléchargement (vérifiez votre connexion internet et l'URL)." >&2
  exit 1
fi

echo "» Vérification du script..."
# 1. Syntaxe bash
if ! bash -n "$TMP/setup.sh"; then
  echo "✘ Le script téléchargé contient une erreur de syntaxe (fichier probablement tronqué)." >&2
  echo "  Le fichier a été conservé dans : $TMP/setup.sh" >&2
  echo "  Réessayez, ou téléchargez-le manuellement." >&2
  trap - EXIT
  exit 1
fi

# 2. Marqueur de fin (EOF integrity marker)
if ! grep -q '^_VMRA_EOF_MARKER=1$' "$TMP/setup.sh"; then
  echo "✘ Marqueur de fin de script absent — le téléchargement a été tronqué." >&2
  echo "  Fichier conservé dans : $TMP/setup.sh" >&2
  trap - EXIT
  exit 1
fi

echo "» Lancement de l'installation..."
# Passer tous les arguments de ce script à setup.sh comme variables d'environnement
# (supporte VAR=val VAR2=val2 ... ou aucune variable pour le wizard interactif)
for arg in "$@"; do
  case "$arg" in
    *=*) export "$arg" ;;
    *) echo "⚠ Argument ignoré (pas KEY=VALUE) : $arg" >&2 ;;
  esac
done

# Exécuter le script complet depuis le fichier temporaire
bash "$TMP/setup.sh"
