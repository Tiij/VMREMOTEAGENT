#!/usr/bin/env bash
# =============================================================
# VMREMOTEAGENT — Système de mise à jour
# Usage :
#   ./scripts/update.sh                # vérifie si une MAJ est dispo, demande confirmation
#   ./scripts/update.sh --check        # vérifie seulement (dry-run), rien n'est modifié
#   ./scripts/update.sh --yes          # installe la MAJ sans demander
#   ./scripts/update.sh --channel beta # change de channel (stable|beta|dev)
#   ./scripts/update.sh --force        # relance l'installateur même si à jour
# =============================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

G="\033[0;32m"; R="\033[0;31m"; Y="\033[1;33m"; C="\033[0;36m"; NC="\033[0m"
hdr(){ echo -e "\n${C}═══ $* ═══${NC}"; }
ok(){  echo -e "  ${G}✔${NC} $*"; }
warn(){ echo -e "  ${Y}⚠${NC} $*"; }
bad(){  echo -e "  ${R}✘${NC} $*"; }
step(){ echo -e "${G}▶${NC} $*"; }
die(){ echo -e "${R}✘${NC} $*" >&2; exit 1; }

# ---------- Arguments ----------
CHECK_ONLY=0; AUTO_YES=0; FORCE=0
UPDATE_CHANNEL="${UPDATE_CHANNEL:-stable}"
while [ $# -gt 0 ]; do
  case "$1" in
    --check)      CHECK_ONLY=1 ;;
    --yes|-y)     AUTO_YES=1 ;;
    --force|-f)   FORCE=1 ;;
    --channel)    shift; UPDATE_CHANNEL="${1:-stable}" ;;
    --channel=*)  UPDATE_CHANNEL="${1#*=}" ;;
    -h|--help)
      echo "Usage: $0 [--check] [--yes] [--force] [--channel <stable|beta|dev>]"; exit 0 ;;
    *)
      die "Argument inconnu: $1 (--help pour l'aide)" ;;
  esac
  shift
done

if [ "$(id -u)" -ne 0 ]; then
  # On n'a pas besoin d'être root juste pour --check, mais pour lancer
  # setup.sh qui écrit des fichiers oui.
  if [ "$CHECK_ONLY" -eq 0 ]; then
    echo -e "${R}✘ Ce script doit être lancé en ROOT pour appliquer une mise à jour.${NC}"
    echo ""
    echo "  Vérification seule :  sudo ./scripts/update.sh --check"
    echo "  Mise à jour :         sudo ./scripts/update.sh"
    exit 1
  fi
fi

INSTALL_DIR="$(pwd)"
STATE_FILE=".vmremoteagent.state"
CURRENT_VERSION="?"
[ -f "$STATE_FILE" ] && CURRENT_VERSION=$(grep -E '^version=' "$STATE_FILE" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]' || echo "?")

# ---------- Construire l'URL selon le channel ----------
case "$UPDATE_CHANNEL" in
  stable) REMOTE_BRANCH="main" ;;
  beta)   REMOTE_BRANCH="beta" ;;
  dev)    REMOTE_BRANCH="dev" ;;
  *)      die "Channel inconnu: $UPDATE_CHANNEL (valeurs: stable, beta, dev)" ;;
esac

SETUP_URL="https://raw.githubusercontent.com/Tiij/VMREMOTEAGENT/${REMOTE_BRANCH}/setup.sh"
VERSION_URL="https://raw.githubusercontent.com/Tiij/VMREMOTEAGENT/${REMOTE_BRANCH}/VERSION"
CHANGELOG_URL="https://raw.githubusercontent.com/Tiij/VMREMOTEAGENT/${REMOTE_BRANCH}/CHANGELOG.md"

echo -e "${C}
╔══════════════════════════════════════════════╗
║    🚀  VMREMOTEAGENT  —  Mise à jour         ║
║    Channel : $UPDATE_CHANNEL$(printf '%*s' $((27-${#UPDATE_CHANNEL})) '')║
╚══════════════════════════════════════════════╝${NC}"
echo -e "  ${C}Dossier :${NC}  $INSTALL_DIR"
echo -e "  ${C}Version installée :${NC} $CURRENT_VERSION"
echo ""

# ---------- Récupérer la version distante ----------
step "Vérification de la dernière version disponible (channel: $UPDATE_CHANNEL)..."
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Option 1: récupérer depuis VERSION (fichier dédié, plus rapide)
REMOTE_VERSION=""
if command -v curl >/dev/null 2>&1; then
  if REMOTE_VERSION=$(curl -fsSL --max-time 10 "$VERSION_URL" 2>/dev/null); then
    REMOTE_VERSION=$(echo "$REMOTE_VERSION" | tr -d '[:space:]')
  fi
fi

# Fallback : si VERSION n'existe pas (v1.0.0), parser INSTALLER_VERSION du setup.sh distant
if [ -z "$REMOTE_VERSION" ]; then
  if SETUP_TMP=$(curl -fsSL --max-time 15 "$SETUP_URL" 2>/dev/null); then
    REMOTE_VERSION=$(echo "$SETUP_TMP" | grep -E '^INSTALLER_VERSION=' | head -n1 | cut -d= -f2 | tr -d '"' | tr -d '[:space:]')
    echo "$SETUP_TMP" > "$TMP_DIR/setup.sh"
  else
    die "Impossible de contacter GitHub ($VERSION_URL). Vérifiez votre connexion Internet sur la VM (curl -I https://github.com)."
  fi
fi

if [ -z "$REMOTE_VERSION" ]; then
  die "Impossible de déterminer la version distante depuis $SETUP_URL"
fi

ok "Dernière version disponible : $REMOTE_VERSION"

# ---------- Comparaison de versions ----------
version_ge() {
  # Renvoie 0 si $1 >= $2 (comparaison SemVer basique)
  [ "$1" = "$2" ] && return 0
  local IFS=.
  local i ver1=($1) ver2=($2)
  for ((i=${#ver1[@]}; i<3; i++)); do ver1[i]=0; done
  for ((i=${#ver2[@]}; i<3; i++)); do ver2[i]=0; done
  for ((i=0; i<3; i++)); do
    if [ "${ver1[i]:-0}" -gt "${ver2[i]:-0}" ]; then return 0; fi
    if [ "${ver1[i]:-0}" -lt "${ver2[i]:-0}" ]; then return 1; fi
  done
  return 0
}

NEED_UPDATE=0
if [ "$CURRENT_VERSION" = "?" ]; then
  warn "Impossible de déterminer la version locale. Une installation ou mise à jour sera proposée."
  NEED_UPDATE=1
elif [ "$FORCE" -eq 1 ]; then
  warn "Mode --force : relance de l'installation demandée."
  NEED_UPDATE=1
elif version_ge "$CURRENT_VERSION" "$REMOTE_VERSION"; then
  ok "Vous êtes déjà à jour (local: $CURRENT_VERSION, distant: $REMOTE_VERSION)."
  [ "$CHECK_ONLY" -eq 1 ] && exit 0
  if [ "$AUTO_YES" -eq 0 ] && [ -t 0 ]; then
    echo ""
    read -p "Voulez-vous quand même relancer l'installation (réparation) ? [o/N] " -n 1 -r R; echo
    case "$R" in o|O|y|Y) NEED_UPDATE=1 ;; *) echo "Aucune action. Bye."; exit 0 ;; esac
  fi
else
  echo ""
  echo -e "${Y}⬆  Une mise à jour est disponible :${NC}"
  echo -e "     ${C}${CURRENT_VERSION}${NC}  →  ${G}${REMOTE_VERSION}${NC}"
  NEED_UPDATE=1
fi

# ---------- Afficher le changelog si mise à jour ----------
if [ "$NEED_UPDATE" -eq 1 ]; then
  step "Récupération des notes de version..."
  if CHANGELOG=$(curl -fsSL --max-time 10 "$CHANGELOG_URL" 2>/dev/null); then
    # Extraire la section correspondant à REMOTE_VERSION
    SECTION=$(echo "$CHANGELOG" | awk -v ver="## \\[$REMOTE_VERSION\\]" '
      $0 ~ ver {p=1; print; next}
      p && /^## \[/ {exit}
      p {print}')
    if [ -n "$SECTION" ]; then
      echo ""
      echo "$SECTION" | head -80
      echo ""
    else
      warn "Section ${REMOTE_VERSION} non trouvée dans le CHANGELOG (version très récente ?)"
    fi
  else
    warn "Impossible de récupérer le CHANGELOG — continuons."
  fi
fi

# ---------- Mode check seulement ----------
if [ "$CHECK_ONLY" -eq 1 ]; then
  echo ""
  if [ "$NEED_UPDATE" -eq 1 ]; then
    echo -e "${Y}Une mise à jour est disponible.${NC}  (v$REMOTE_VERSION)"
    echo "  Pour installer : sudo ./scripts/update.sh"
    exit 0
  else
    echo -e "${G}Déjà à jour.${NC}"
    exit 0
  fi
fi

# ---------- Confirmation ----------
if [ "$NEED_UPDATE" -eq 1 ]; then
  if [ "$AUTO_YES" -eq 0 ] && [ -t 0 ]; then
    echo ""
    echo -e "${Y}Cette opération va :${NC}"
    echo "  1. Créer un snapshot de précaution (volumes + config)"
    echo "  2. Télécharger le nouvel installateur (v$REMOTE_VERSION, channel $UPDATE_CHANNEL)"
    echo "  3. Lancer l'installateur en mode 'update' (il préserve vos secrets,"
    echo "     régénère les fichiers de config, build la nouvelle image,"
    echo "     préserve les volumes de données)"
    echo "  4. Vérifier que la stack démarre correctement (healthcheck)"
    echo "  5. Si le démarrage échoue, tenter un rollback automatique"
    echo ""
    read -p "Continuer ? [O/n] " -n 1 -r R; echo
    case "$R" in n|N) echo "Annulé."; exit 0 ;; esac
  fi
fi

# ---------- Téléchargement du setup.sh le plus récent ----------
if [ ! -f "$TMP_DIR/setup.sh" ]; then
  step "Téléchargement de l'installateur v$REMOTE_VERSION..."
  if ! curl -fsSL --max-time 15 "$SETUP_URL" -o "$TMP_DIR/setup.sh"; then
    die "Échec du téléchargement depuis $SETUP_URL"
  fi
fi
chmod +x "$TMP_DIR/setup.sh"
bash -n "$TMP_DIR/setup.sh" || die "L'installateur distant a une erreur de syntaxe — annulation par sécurité."
ok "Installateur v$REMOTE_VERSION téléchargé et syntaxiquement valide."

# ---------- Snapshot de précaution ----------
if [ -x ./scripts/snapshot.sh ]; then
  SNAP_NAME="pre-update-${CURRENT_VERSION}-to-${REMOTE_VERSION}-$(date +%Y%m%d-%H%M%S)"
  step "Snapshot de précaution : $SNAP_NAME"
  if ./scripts/snapshot.sh "$SNAP_NAME" >/dev/null 2>&1; then
    ok "Snapshot créé dans backups/"
    SNAP_CREATED=1
  else
    warn "Échec du snapshot — continuons mais attention."
    SNAP_CREATED=0
  fi
else
  warn "scripts/snapshot.sh introuvable, pas de snapshot de précaution."
  SNAP_CREATED=0
fi

# ---------- Mise à jour du setup.sh local pour les prochaines fois ----------
cp "$TMP_DIR/setup.sh" ./setup.sh
chmod +x ./setup.sh
ok "setup.sh local mis à jour (v$REMOTE_VERSION)"

# ---------- Lancer l'installateur en mode update ----------
step "Application de la mise à jour (peut prendre quelques minutes au premier build)..."
echo ""

# On garde le INSTALL_DIR et on transmet toutes les infos à setup.sh
# Il détectera automatiquement l'état et fera les changements nécessaires.
# Note: on ne force pas FORCE_ACTION=update pour laisser le diagnostic décider.
export FORCE_ACTION=update
export NONINTERACTIVE=1
export INSTALL_DIR
# Conserver OLLAMA_API_KEY depuis .env si elle y est
if [ -f .env ] && grep -qE '^OLLAMA_API_KEY=sk-' .env; then
  export OLLAMA_API_KEY=$(grep -E '^OLLAMA_API_KEY=' .env | cut -d= -f2-)
fi
# Conserver HOSTNAME_PUBLIQUE
if [ -f "$STATE_FILE" ] && grep -qE '^host=' "$STATE_FILE"; then
  export HOSTNAME_PUBLIQUE=$(grep -E '^host=' "$STATE_FILE" | cut -d= -f2-)
fi

UPDATE_LOG="$INSTALL_DIR/backups/update-${REMOTE_VERSION}-$(date +%Y%m%d-%H%M%S).log"
mkdir -p backups

SET_RC=0
if bash ./setup.sh 2>&1 | tee "$UPDATE_LOG"; then
  ok "Mise à jour terminée avec succès."
else
  SET_RC=$?
  bad "Le script d'installation a retourné une erreur (code $SET_RC)."
fi

# ---------- Vérification post-update ----------
hdr "Vérification post-mise à jour"
FINAL_STATE="?"
[ -f "$STATE_FILE" ] && FINAL_STATE=$(grep -E '^state=' "$STATE_FILE" | cut -d= -f2 || echo "?")
NEW_VERSION="?"
[ -f "$STATE_FILE" ] && NEW_VERSION=$(grep -E '^version=' "$STATE_FILE" | cut -d= -f2 || echo "?")

echo -e "  État final : ${C}$FINAL_STATE${NC}"
echo -e "  Version installée : ${C}$NEW_VERSION${NC}"
echo -e "  Log complet : ${C}$UPDATE_LOG${NC}"

# Test HTTP rapide
HEALTH=0
for i in $(seq 1 30); do
  if curl -kfsS --max-time 3 https://127.0.0.1/ -o /dev/null 2>/dev/null; then
    HEALTH=1; break
  fi
  sleep 1
done

if [ "$HEALTH" -eq 1 ] && [ "$SET_RC" -eq 0 ]; then
  ok "Healthcheck OK : le dashboard répond en HTTPS."
  echo "state=healthy" > "$STATE_FILE"
  echo "version=$NEW_VERSION" >> "$STATE_FILE"
  echo "last_action=update" >> "$STATE_FILE"
  echo ""
  echo -e "${G}═══════════════════════════════════════════════════${NC}"
  echo -e "${G}✅ Mise à jour installée : v$CURRENT_VERSION → v$NEW_VERSION${NC}"
  echo ""
  echo -e "  Dashboard :         https://$(grep -E '^host=' "$STATE_FILE" | cut -d= -f2)/"
  echo -e "  Doctor (si besoin):  ./scripts/doctor.sh --fix"
  echo -e "  Log :               $UPDATE_LOG"
  echo -e "${G}═══════════════════════════════════════════════════${NC}"
  exit 0
else
  bad "Le service ne répond pas encore ou l'installation a échoué."

  # ---------- Rollback automatique ----------
  if [ "$SNAP_CREATED" -eq 1 ] && [ -x ./scripts/restore.sh ]; then
    echo ""
    warn "Tentative de ROLLBACK automatique vers l'état d'avant la MAJ..."
    if ./scripts/restore.sh "$SNAP_NAME"; then
      ok "Rollback effectué. Vous êtes revenu en v$CURRENT_VERSION."
      echo "Le log d'erreur est dans $UPDATE_LOG."
      echo "Vous pouvez réessayer plus tard ou lancer manuellement ./scripts/update.sh"
      exit 2
    else
      bad "Le rollback a échoué. Utilisez manuellement :"
      echo "  ./scripts/restore.sh $SNAP_NAME"
      exit 3
    fi
  else
    echo ""
    echo "  Aucun snapshot de précaution n'a été créé. Pour diagnostiquer :"
    echo "    ./scripts/doctor.sh"
    echo "    docker compose logs -f cloudcli"
    echo "    cat $UPDATE_LOG"
    exit 2
  fi
fi
