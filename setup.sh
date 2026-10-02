#!/usr/bin/env bash
# =================================================================
# VMREMOTEAGENT — Installateur UNE COMMANDE
# CloudCLI (Claude Code + Codex) + code-server + Dashboard Apple-style
# + Caddy HTTPS + backups automatiques. Backend : Ollama Cloud.
#
# Usage :
#   curl -fsSL https://raw.githubusercontent.com/Tiij/VMREMOTEAGENT/main/setup.sh | sudo bash
#
# Variables d'environnement :
#   INSTALL_DIR       défaut: /opt/multi-agents
#   OLLAMA_API_KEY    si non défini = demande interactive
#   HOSTNAME_PUBLIQUE défaut: détection auto (ipify → ifconfig → hostname -I)
#   NO_BUILD=1        pour écrire les fichiers sans lancer docker
#   FORCE_ACTION      auto|install|repair|update|rebuild|reinstall
#   NONINTERACTIVE=1  pas de menu, pas de demande (CI/automation)
#   NOTUI=1           désactive l'interface whiptail (fallback texte)
# =================================================================
set -euo pipefail

# ==================== Version de cette release ====================
INSTALLER_VERSION="1.4.0"
STATE_FILE=".vmremoteagent.state"
META_FILE="MANIFEST.txt"
HEALTH_TIMEOUT=45

INSTALL_DIR="${INSTALL_DIR:-/opt/multi-agents}"
LOG_FILE="$INSTALL_DIR/install.log"
LOCK_FILE="/var/run/vmremoteagent-install.lock"
PROGRESS_FILE="/tmp/vmremoteagent-progress.$$"
FORCE_ACTION="${FORCE_ACTION:-auto}"
NONINTERACTIVE="${NONINTERACTIVE:-0}"
NOTUI="${NOTUI:-0}"

# ==================== Couleurs ANSI ====================
RED='\033[0;31m'; GREEN='\033[0;32m'; YEL='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

banner(){ echo -e "${CYAN}
╔══════════════════════════════════════════════════════════════╗
║   VMREMOTEAGENT  —  Agents IA + Dashboard + IDE sécurisé     ║
║   CloudCLI · Claude Code · Codex · code-server · Caddy       ║
╚══════════════════════════════════════════════════════════════╝${NC}"; }
step(){ echo -e "${GREEN}▶${NC} $*"; }
warn(){ echo -e "${YEL}⚠${NC}  $*"; }
bad(){ echo -e "${RED}✘${NC}  $*"; }
die(){ echo -e "${RED}✘${NC}  $*">&2; cleanup_lock; exit 1; }
ok(){ echo -e "${GREEN}✔${NC} $*"; }

# ==================== Nettoyage du lock à la sortie ====================
cleanup_lock() {
  rm -f "$LOCK_FILE" "$PROGRESS_FILE" 2>/dev/null || true
  # Restaurer le terminal si whiptail l'a cassé
  [ -t 1 ] && stty sane 2>/dev/null || true
}
trap 'cleanup_lock' EXIT INT TERM HUP


banner

# =====================================================================
# 🔒 VERROU : empêche deux installations en parallèle sur la même machine
# =====================================================================
# On vérifie root AVANT de toucher au verrou (qui est dans /var/run, root-only)

# ---------- Vérification root ----------
if [ "$(id -u)" -ne 0 ]; then
  echo ""
  echo -e "${RED}✘${NC}  Ce script doit être lancé en ROOT."
  echo ""
  echo -e "   ${YEL}Si vous avez fait:${NC}"
  echo -e "     $ ${0##*/}"
  echo ""
  echo -e "   ${GREEN}Relancez avec:${NC}"
  echo -e "     $ sudo ${0##*/}"
  echo ""
  echo -e "   ${YEL}Si vous utilisez la commande curl | bash:${NC}"
  echo ""
  echo -e "     ❌ curl -fsSL URL | bash"
  echo ""
  echo -e "   ${GREEN}Ajoutez sudo devant bash:${NC}"
  echo ""
  echo -e "     ✅ curl -fsSL URL | ${GREEN}sudo${NC} bash"
  echo ""
  echo -e "   Astuce: placez vos variables APRÈS sudo:"
  echo -e "     curl -fsSL URL | sudo OLLAMA_API_KEY=sk-... HOSTNAME_PUBLIQUE=1.2.3.4 bash"
  echo ""
  exit 1
fi

# On crée le dossier d'installation pour avoir le droit d'écrire dans LOG_FILE
mkdir -p "$INSTALL_DIR" 2>/dev/null || die "Impossible de créer $INSTALL_DIR."

if [ -f "$LOCK_FILE" ]; then
  OTHER_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "?")
  if [ -n "$OTHER_PID" ] && kill -0 "$OTHER_PID" 2>/dev/null; then
    echo -e "${RED}✘${NC} Une autre instance de setup.sh est déjà en cours (PID $OTHER_PID)."
    echo "   Si vous êtes certain qu'aucune installation n'est en cours,"
    echo "   supprimez le verrou avec :  sudo rm -f $LOCK_FILE"
    exit 1
  else
    # Verrou orphelin (processus mort) → on le supprime
    warn "Verrou orphelin détecté (PID $OTHER_PID n'existe plus) — nettoyage."
    rm -f "$LOCK_FILE"
  fi
fi
echo $$ > "$LOCK_FILE"
ok "Verrou d'installation créé (PID $$)"

cd "$INSTALL_DIR"; :> "$LOG_FILE"

# =====================================================================
# 🎨 TUI : détection de whiptail + installation si absent
# =====================================================================
USE_TUI=0
if [ "$NOTUI" != "1" ] && [ "$NONINTERACTIVE" != "1" ] && [ -t 0 ] && [ -t 1 ]; then
  if command -v whiptail >/dev/null 2>&1; then
    USE_TUI=1
  else
    # Essayer d'installer whiptail avec ce qu'on a sous la main
    if command -v apt-get >/dev/null 2>&1; then
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -y >/dev/null 2>&1 || true
      apt-get install -y --no-install-recommends whiptail >/dev/null 2>&1 && USE_TUI=1 || true
    elif command -v dnf >/dev/null 2>&1; then
      dnf install -y newt >/dev/null 2>&1 && USE_TUI=1 || true
    elif command -v yum >/dev/null 2>&1; then
      yum install -y newt >/dev/null 2>&1 && USE_TUI=1 || true
    elif command -v pacman >/dev/null 2>&1; then
      pacman -Sy --noconfirm --needed libnewt >/dev/null 2>&1 && USE_TUI=1 || true
    elif command -v zypper >/dev/null 2>&1; then
      zypper --non-interactive install whiptail >/dev/null 2>&1 && USE_TUI=1 || true
    elif command -v apk >/dev/null 2>&1; then
      apk add --no-cache newt >/dev/null 2>&1 && USE_TUI=1 || true
    fi
  fi
fi
if [ "$USE_TUI" -eq 1 ]; then
  ok "Interface whiptail disponible (TUI graphique)"
else
  ok "Interface texte classique"
fi

# =====================================================================
# 🔧 Fonctions TUI helpers (wrapper adaptatif whiptail / texte brut)
# =====================================================================
TUI_BACKTITLE="VMREMOTEAGENT v$INSTALLER_VERSION — Installation"

# msgbox <titre> <message>
msgbox(){
  local title="$1" msg="$2"
  if [ "$USE_TUI" -eq 1 ]; then
    whiptail --title "$title" --msgbox "$msg" 15 70 3>&1 1>&2 2>&3
  else
    echo ""
    echo -e "${CYAN}─── $title ───${NC}"
    echo -e "$msg" | sed 's/\\n/\n/g' | fold -s -w 72 | sed 's/^/  /'
    echo ""
  fi
}

# yesno <titre> <question> [defaut 0=yes / 1=no] → return 0 si Oui
yesno(){
  local title="$1" msg="$2" default="${3:-0}"
  if [ "$NONINTERACTIVE" -eq 1 ]; then
    return 0
  fi
  if [ "$USE_TUI" -eq 1 ]; then
    whiptail --title "$title" --yesno "$msg" 15 70 --defaultno 3>&1 1>&2 2>&3
    return $?
  else
    echo ""
    echo -e "${BOLD}$title${NC}"
    echo -e "$msg" | sed 's/\\n/\n/g' | fold -s -w 72
    local deflabel="[O/n]"
    [ "$default" = "1" ] && deflabel="[o/N]"
    echo -n "  $deflabel "
    local R
    IFS= read -r R
    case "$R" in n|N|no|non) return 1 ;; *) return 0 ;; esac
  fi
}

# inputbox <titre> <message> <default> → stdout le résultat
inputbox(){
  local title="$1" msg="$2" default="${3:-}"
  local res
  if [ "$NONINTERACTIVE" -eq 1 ]; then
    echo "$default"
    return
  fi
  if [ "$USE_TUI" -eq 1 ]; then
    res=$(whiptail --title "$title" --inputbox "$msg" 12 70 "$default" 3>&1 1>&2 2>&3)
  else
    echo ""
    echo -e "${BOLD}$title${NC}"
    echo -e "$msg" | fold -s -w 72 | sed 's/^/  /'
    echo -n "  [défaut: $default] : "
    IFS= read -r res
    [ -z "$res" ] && res="$default"
  fi
  echo "$res"
}

# passwordbox <titre> <message> → stdout le mot de passe / clé
passwordbox(){
  local title="$1" msg="$2"
  local res
  if [ "$NONINTERACTIVE" -eq 1 ]; then
    echo "${OLLAMA_API_KEY:-}"; return
  fi
  if [ "$USE_TUI" -eq 1 ]; then
    res=$(whiptail --title "$title" --passwordbox "$msg" 12 70 3>&1 1>&2 2>&3)
  else
    echo ""
    echo -e "${BOLD}$title${NC}"
    echo -e "$msg" | fold -s -w 72 | sed 's/^/  /'
    echo -n "  > "
    stty -echo 2>/dev/null || true
    IFS= read -r res
    stty echo 2>/dev/null || true
    echo ""
  fi
  echo "$res"
}

# menu <titre> <prompt> <item1> <desc1> [item2 desc2 ...] → stdout item choisi
menu(){
  local title="$1" prompt="$2"; shift 2
  if [ "$NONINTERACTIVE" -eq 1 ]; then
    echo "$1"; return
  fi
  local res
  if [ "$USE_TUI" -eq 1 ]; then
    res=$(whiptail --title "$title" --menu "$prompt" 20 70 12 "$@" 3>&1 1>&2 2>&3)
  else
    echo ""
    echo -e "${BOLD}$title${NC}"
    echo -e "$prompt" | fold -s -w 72 | sed 's/^/  /'
    local i=1 items=()
    while [ $# -gt 0 ]; do
      echo -e "  ${BOLD}[$i]${NC} $1 — $2"
      items+=("$1"); shift 2; i=$((i+1))
    done
    echo -n "  Choix (1-${#items[@]}, défaut=1) : "
    local R; IFS= read -r R
    if [ -z "$R" ] || [ "$R" -lt 1 ] 2>/dev/null || [ "$R" -gt "${#items[@]}" ] 2>/dev/null; then
      R=1
    fi
    res="${items[$((R-1))]}"
  fi
  echo "$res"
}

# Progression : on utilise une gauge whiptail si possible
GAUGE_PID=""
GAUGE_TTY=""
progress_start(){
  if [ "$NONINTERACTIVE" -eq 1 ] || [ "$USE_TUI" -ne 1 ] || [ ! -t 1 ]; then return; fi
  # Ouvrir une gauge en arrière-plan sur /dev/tty réutilisé
  exec 3<>/tmp/tui-gauge.fifo.$$ 2>/dev/null || return 0
  rm -f /tmp/tui-gauge.fifo.$$
  mkfifo /tmp/tui-gauge.fifo.$$ 2>/dev/null || return 0
  exec 3<>/tmp/tui-gauge.fifo.$$
  whiptail --title "$TUI_BACKTITLE" --gauge "Initialisation..." 8 70 0 <&3 &
  GAUGE_PID=$!
  disown $GAUGE_PID 2>/dev/null || true
}
progress(){
  local pct="$1" msg="$2"
  if [ -n "$GAUGE_PID" ] && kill -0 "$GAUGE_PID" 2>/dev/null; then
    echo "$pct" >&3
    echo "XXX" >&3
    echo "$msg" >&3
    echo "XXX" >&3
  else
    echo -e "${GREEN}[${pct}%]${NC} $msg"
  fi
}
progress_done(){
  if [ -n "$GAUGE_PID" ]; then
    echo "100" >&3 2>/dev/null
    echo "XXX" >&3; echo "Terminé." >&3; echo "XXX" >&3
    sleep 0.3
    kill $GAUGE_PID 2>/dev/null || true
    wait $GAUGE_PID 2>/dev/null || true
    exec 3>&-
    rm -f /tmp/tui-gauge.fifo.$$
    GAUGE_PID=""
  fi
}

# =====================================================================
# 🧙 ASSISTANT D'ONBOARDING (wizard interactif)
# =====================================================================
step "Assistant d'intégration..."

# Détection système (rapide, avant les questions)
ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
case "$ARCH" in amd64|x86_64) ;; arm64|aarch64) ;; armv7l) ;; *)
  die "Architecture non supportée: $ARCH"
esac
[ -r /etc/os-release ] && . /etc/os-release || die "/etc/os-release absent"
DISTRO_LABEL="${PRETTY_NAME:-$ID $VERSION_ID}"

# --- Écran de bienvenue (TUI seulement) ---
if [ "$USE_TUI" -eq 1 ] && [ -z "${OLLAMA_API_KEY:-}" ]; then
  whiptail --title "VMREMOTEAGENT — Bienvenue" --msgbox \
"Bienvenue dans l'assistant d'installation de VMREMOTEAGENT.

Ce wizard va :
  1. Vérifier que votre système est compatible
  2. Installer les dépendances et Docker si nécessaire
  3. Vous demander votre clé API Ollama Cloud
  4. Configurer le nom d'hôte / IP publique
  5. Configurer et lancer la stack
  6. Créer les sauvegardes automatiques
  7. Vérifier que tout fonctionne (healthcheck)
  8. En cas d'échec : rollback automatique et diagnostic

Durée estimée : 5 à 15 minutes (principalement le premier build Docker).
Appuyez sur ENTRÉE pour commencer." 20 70
fi

# --- Choix de l'action si une installation existe déjà ---
DETECTED_ACTION="install"
DETECTED_LABEL=""
if [ -f "$INSTALL_DIR/$STATE_FILE" ]; then
  EXISTING_VER=$(grep -E '^version=' "$INSTALL_DIR/$STATE_FILE" 2>/dev/null | cut -d= -f2 || echo "?")
  EXISTING_STATE=$(grep -E '^state=' "$INSTALL_DIR/$STATE_FILE" 2>/dev/null | cut -d= -f2 || echo "?")
  ACTION_CHOICE=$(menu "Installation existante détectée" \
"Version $EXISTING_VER trouvée (état: $EXISTING_STATE).
Que souhaitez-vous faire ?" \
    "repair"    "Réparer / relancer (conserve données et secrets)" \
    "update"    "Mettre à jour vers v$INSTALLER_VERSION" \
    "rebuild"   "Rebuild complet de l'image (conserve les données)" \
    "reinstall" "Réinstaller depuis zéro (les données sont sauvegardées)" \
    "status"    "Voir l'état actuel et quitter")
  case "$ACTION_CHOICE" in
    status)
      if [ -x "$INSTALL_DIR/scripts/status.sh" ]; then
        if [ "$USE_TUI" -eq 1 ]; then
          bash "$INSTALL_DIR/scripts/status.sh" > /tmp/vma-status.txt 2>&1
          whiptail --title "État actuel" --textbox /tmp/vma-status.txt 22 76
          rm -f /tmp/vma-status.txt
        else
          bash "$INSTALL_DIR/scripts/status.sh"
        fi
      fi
      echo "Aucune modification. Au revoir."
      cleanup_lock; exit 0 ;;
    *) DETECTED_ACTION="$ACTION_CHOICE" ;;
  esac
fi
FORCE_ACTION="$DETECTED_ACTION"

# --- Clé API Ollama ---
if [ -z "${OLLAMA_API_KEY:-}" ]; then
  # Proposer de coller directement ou ouvrir un rappel
  if yesno "Clé API Ollama Cloud" "Avez-vous déjà une clé API Ollama Cloud ?\n\nSi ce n'est pas le cas, allez sur :\n  https://ollama.com/settings/keys\n\nVous pouvez en créer une en 30 secondes (gratuit)." 0; then
    :
  else
    msgbox "Création de la clé" "1. Ouvrez https://ollama.com/settings/keys\n2. Créez un compte / connectez-vous\n3. Cliquez 'Create API key', nommez-la (ex: vm-agents)\n4. Copiez la clé (sk-ollam-...) et collez-la à la prochaine invite.\n\nAppuyez sur ENTRÉE quand vous êtes prêt."
  fi
  while [ -z "${OLLAMA_API_KEY:-}" ]; do
    OLLAMA_API_KEY=$(passwordbox "Clé API Ollama Cloud" "Collez votre clé API (sk-ollama-...):")
    if [ -z "$OLLAMA_API_KEY" ]; then
      msgbox "Clé vide" "La clé ne peut pas être vide. Réessayez."
    fi
  done
fi
ok "Clé Ollama Cloud configurée"

# --- Host / domaine ---
DEFAULT_HOST=""
if [ -n "${HOSTNAME_PUBLIQUE:-}" ]; then
  DEFAULT_HOST="$HOSTNAME_PUBLIQUE"
elif [ -f "$INSTALL_DIR/.env" ] && grep -qE '^WEBUI_URL=https?://' "$INSTALL_DIR/.env"; then
  DEFAULT_HOST=$(grep -E '^WEBUI_URL=' "$INSTALL_DIR/.env" | cut -d= -f2 | sed 's|^https\?://||;s|/$||')
fi
if [ -z "$DEFAULT_HOST" ]; then
  step "Détection de l'IP publique..."
  DEFAULT_HOST=$(curl -4 -fsSL --max-time 5 https://api.ipify.org 2>/dev/null \
               || curl -4 -fsSL --max-time 5 https://ifconfig.me 2>/dev/null \
               || hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
  ok "IP détectée : $DEFAULT_HOST"
fi
HOSTNAME_PUBLIQUE=$(inputbox "Adresse publique" "Entrez l'IP publique ou le nom de domaine que vous utiliserez pour accéder à la plateforme.\n\n(Utilisée pour générer les liens et certificats.)" "$DEFAULT_HOST")
[ -z "$HOSTNAME_PUBLIQUE" ] && HOSTNAME_PUBLIQUE="$DEFAULT_HOST"
ok "Hôte : $HOSTNAME_PUBLIQUE"

# --- Dossier d'installation ---
INSTALL_DIR=$(inputbox "Dossier d'installation" "Où voulez-vous installer la stack ?\n\n(Valeur par défaut : /opt/multi-agents)" "$INSTALL_DIR")
LOG_FILE="$INSTALL_DIR/install.log"
ok "Dossier d'installation : $INSTALL_DIR"

# --- Récapitulatif avant installation ---
if yesno "Récapitulatif" \
"Résumé de l'installation :\n\n  Distro :    $DISTRO_LABEL\n  Arch :      $ARCH\n  Dossier :   $INSTALL_DIR\n  Hôte :      $HOSTNAME_PUBLIQUE\n  Action :    $DETECTED_ACTION\n  Interface : $([ "$USE_TUI" -eq 1 ] && echo 'TUI whiptail' || echo 'texte')\n\nC'est prêt ? On y va !" 0; then
  :
else
  msgbox "Annulation" "Installation annulée par l'utilisateur.\nVous pouvez relancer le script à tout moment."
  cleanup_lock; exit 0
fi

mkdir -p "$INSTALL_DIR"; cd "$INSTALL_DIR"; :> "$LOG_FILE"

progress_start
progress 5 "Démarrage..."

# ---------- 1. VÉRIFICATION DU SYSTÈME ----------
progress 10 "Vérification du système..."; step "Vérification du système..."
VERIFY_ISSUES=0

# Architecture
case "$ARCH" in
  amd64|x86_64) ARCH_LABEL="amd64/x86_64"; ARCH_DOCKER="amd64" ;;
  arm64|aarch64) ARCH_LABEL="arm64/aarch64"; ARCH_DOCKER="arm64" ;;
  armv7l)       ARCH_LABEL="armv7 (32-bit)"; ARCH_DOCKER="armhf" ;;
  *)            ARCH_LABEL="$ARCH (non testée)" ;;
esac
ok "Architecture : $ARCH_LABEL"

# CPU
CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "?")
ok "CPU : $CPU_CORES coeurs"
if [ "$CPU_CORES" != "?" ] && [ "$CPU_CORES" -lt 2 ] 2>/dev/null; then
  warn "Moins de 2 coeurs détectés — l'expérience peut être lente."
fi

# Disque (avant RAM, parce que swap a besoin du disque)
DISK_KB=$(df -Pk "$INSTALL_DIR" 2>/dev/null | awk 'NR==2{print $4}')
if [ -n "$DISK_KB" ]; then
  DISK_GB=$(awk "BEGIN{printf \"%.1f\", $DISK_KB/1024/1024}")
  ok "Espace disque disponible sur ${INSTALL_DIR} : ${DISK_GB} Go"
  if [ "$DISK_KB" -lt 5242880 ]; then  # <5 Go
    bad "Espace disque insuffisant (moins de 5 Go). Minimum 10 Go recommandé."
    VERIFY_ISSUES=$((VERIFY_ISSUES+1))
  elif [ "$DISK_KB" -lt 10485760 ]; then
    warn "Espace disque juste (${DISK_GB} Go). 10 Go+ recommandé."
  fi
fi

# RAM
RAM_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024)}' || echo 0)
if [ "$RAM_KB" -gt 0 ]; then
  RAM_MB=$((RAM_KB / 1024))
  RAM_GB=$(awk "BEGIN{printf \"%.1f\", $RAM_MB/1024}")
  ok "RAM : ${RAM_GB} Go"
  if [ "$RAM_MB" -lt 1800 ]; then
    bad "RAM insuffisante (moins de 2 Go). Minimum 2 Go (4 Go idéal)."
    VERIFY_ISSUES=$((VERIFY_ISSUES+1))
  elif [ "$RAM_MB" -lt 3500 ]; then
    warn "RAM juste (${RAM_GB} Go)."
    # Ajouter un swap de 2 Go si pas de swap actif et place disponible
    if [ "$(swapon --show 2>/dev/null | wc -l)" -le 1 ] && [ ! -f /swapfile ]; then
      if [ -n "$DISK_KB" ] && [ "$DISK_KB" -gt 15728640 ]; then  # >15 Go libre (2G swap + 10G build)
        step "Création automatique d'un fichier swap de 2 Go..."
        if fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none; then
          chmod 600 /swapfile
          if mkswap /swapfile >/dev/null 2>&1 && swapon /swapfile; then
            echo '/swapfile none swap sw 0 0' >> /etc/fstab
            ok "Swap de 2 Go activé (évite les OOM au build)."
          else
            warn "Échec de mkswap/swapon — continuons sans swap."
            rm -f /swapfile
          fi
        else
          warn "Impossible de créer /swapfile (continuons)."
        fi
      fi
    fi
  fi
fi

# Distribution & package manager
PM=""
DISTRO_LIKE="unknown"
VERSION_CODENAME=""
if [ -r /etc/os-release ]; then
  . /etc/os-release
  [ -n "${VERSION_CODENAME:-}" ] || VERSION_CODENAME="${UBUNTU_CODENAME:-${VERSION_ID%%.*}}"
  case "$ID" in
    debian|ubuntu|linuxmint|pop|raspbian|elementary|kali|zorin|mx)
      PM="apt"; DISTRO_LIKE="debian" ;;
    fedora|rhel|centos|rocky|almalinux|ol|amzn|virtuozzo)
      PM="dnf"; DISTRO_LIKE="rhel"
      command -v dnf >/dev/null 2>&1 || PM="yum" ;;
    arch|manjaro|endeavouros|garuda|artix)
      PM="pacman"; DISTRO_LIKE="arch" ;;
    alpine)
      PM="apk"; DISTRO_LIKE="alpine" ;;
    opensuse*|sles|suse)
      PM="zypper"; DISTRO_LIKE="suse" ;;
    gentoo)
      PM="emerge"; DISTRO_LIKE="gentoo" ;;
    *)
      # essayons ID_LIKE
      case "${ID_LIKE:-}" in
        *debian*) PM="apt"; DISTRO_LIKE="debian" ;;
        *rhel*|*fedora*) PM="dnf"; DISTRO_LIKE="rhel"; command -v dnf >/dev/null 2>&1 || PM="yum" ;;
        *suse*) PM="zypper"; DISTRO_LIKE="suse" ;;
        *arch*) PM="pacman"; DISTRO_LIKE="arch" ;;
      esac
      ;;
  esac
fi
if [ "$(uname -s)" = "Darwin" ]; then
  DISTRO_LIKE="macos"; PM="brew"
fi
ok "Distribution : ${PRETTY_NAME:-$ID $VERSION_ID} (package manager : ${PM:-détection automatique})"

# systemd ?
if command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1; then
  ok "systemd : présent"
else
  warn "systemd non détecté — cron et Docker devront peut-être être démarrés manuellement."
fi

# Connectivité Internet
step "Connectivité Internet..."
ONLINE=0
for URL in https://github.com https://ollama.com https://registry-1.docker.io https://deb.nodesource.com https://raw.githubusercontent.com; do
  DOM="${URL#https://}"; DOM="${DOM%%/*}"
  if curl -fsSL --max-time 5 -o /dev/null "$URL" 2>/dev/null; then
    ok "Connexion à $DOM : OK"
    ONLINE=1
  else
    warn "Connexion à $DOM : ÉCHEC (pourrait poser problème pendant le build)"
  fi
done
if [ "$ONLINE" -eq 0 ]; then
  bad "Aucune connexion Internet sortante détectée. L'installation nécessite un accès au web."
  VERIFY_ISSUES=$((VERIFY_ISSUES+1))
fi

# Ports disponibles
step "Vérification des ports (80/443/3001)..."
for PORT in 80 443 3001; do
  if ss -ltnH "sport = :$PORT" 2>/dev/null | grep -q ":$PORT" \
     || netstat -ltn 2>/dev/null | grep -q ":$PORT "; then
    LISTENER_PID=$(ss -ltnHp "sport = :$PORT" 2>/dev/null | grep -oP 'pid=\K[0-9]+' | head -n1 || echo "")
    LISTENER_NAME="?"
    [ -n "$LISTENER_PID" ] && LISTENER_NAME=$(ps -p "$LISTENER_PID" -o comm= 2>/dev/null || echo "?")
    case "$LISTENER_NAME" in
      docker-proxy|caddy|containerd-shim*|caddy|nginx|apache2|httpd)
        warn "port $PORT occupé par $LISTENER_NAME (pourrait être un reste d'install précédente — on écrasera au (re)start)" ;;
      *)
        warn "port $PORT occupé par $LISTENER_NAME (PID $LISTENER_PID) — possible conflit à résoudre"
        VERIFY_ISSUES=$((VERIFY_ISSUES+1)) ;;
    esac
  else
    ok "port $PORT : libre"
  fi
done

# Si issues critiques, demander confirmation avant de continuer
if [ "$VERIFY_ISSUES" -gt 0 ]; then
  echo ""
  warn "$VERIFY_ISSUES problème(s) critique(s) détecté(s)."
  if [ "${NONINTERACTIVE:-0}" != "1" ] && [ -t 0 ]; then
    read -p "Voulez-vous continuer malgré tout ? [o/N] " -n 1 -r R; echo
    case "$R" in o|O|y|Y) warn "Continuation forcée..." ;; *) die "Annulé. Corrigez les problèmes et relancez." ;; esac
  fi
fi

# ---------- 2. INSTALLATION AUTOMATIQUE DES DÉPENDANCES ----------
step "Installation des dépendances système..."

install_deps_apt() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y --no-install-recommends \
    ca-certificates curl git wget sudo nano gnupg lsb-release \
    vim-common cron coreutils procps jq apt-transport-https iptables
  # software-properties-common n'est pas disponible sur toutes les
  # variantes (Debian testing/trixie, certains conteneurs) ; optionnel
  apt-get install -y --no-install-recommends software-properties-common 2>/dev/null || true
}

install_deps_dnf() {
  dnf install -y --setopt=install_weak_deps=False \
    ca-certificates curl git wget sudo nano gnupg2 lsb-release \
    vim-minimal cronie coreutils procps-ng jq iptables \
    dnf-plugins-core tar findutils
  command -v crond >/dev/null 2>&1 || true
  systemctl enable --now crond 2>/dev/null || true
}

install_deps_yum() {
  yum install -y ca-certificates curl git wget sudo nano gnupg2 \
    vim-minimal cronie coreutils procps-ng jq iptables tar findutils
  systemctl enable --now crond 2>/dev/null || true
}

install_deps_pacman() {
  pacman -Sy --noconfirm --needed \
    ca-certificates curl git wget sudo nano gnupg vim cronie \
    coreutils procps-ng jq iptables tar findutils lsb-release
  systemctl enable --now cronie 2>/dev/null || true
}

install_deps_apk() {
  apk add --no-cache ca-certificates curl git wget sudo nano gnupg \
    vim cronie coreutils procps jq iptables tar findutils
  rc-update add crond default 2>/dev/null || true
  rc-service crond start 2>/dev/null || true
}

install_deps_zypper() {
  zypper --non-interactive --gpg-auto-import-keys refresh
  zypper --non-interactive install -y ca-certificates curl git wget sudo \
    nano gpg2 vim cron coreutils procps jq iptables tar findutils lsb-release
  systemctl enable --now cron 2>/dev/null || true
}

DEPS_NEEDED=0
need_cmd() { command -v "$1" >/dev/null 2>&1 || return 0; return 1; }
for dep in curl git sudo; do
  need_cmd "$dep" && DEPS_NEEDED=1 && break
done

if [ "$DEPS_NEEDED" -eq 1 ] || [ "${SKIP_DEPS:-0}" != "1" ]; then
  case "$DISTRO_LIKE" in
    debian|apt)     install_deps_apt ;;
    rhel)           [ "$PM" = "yum" ] && install_deps_yum || install_deps_dnf ;;
    arch)           install_deps_pacman ;;
    alpine|apk)     install_deps_apk ;;
    suse|zypper)    install_deps_zypper ;;
    macos|brew)
      if command -v brew >/dev/null 2>&1; then
        warn "macOS détecté — utilisez Docker Desktop pour Mac. Les dépendances système (Docker) sont installées via Docker Desktop, pas via brew."
      else
        warn "macOS détecté. Installez Docker Desktop depuis https://www.docker.com/products/docker-desktop/ avant de continuer."
      fi ;;
    gentoo)
      emerge --noreplace app-misc/ca-certificates net-misc/curl dev-vcs/git app-admin/sudo app-editors/nano app-crypt/gnupg sys-process/cronie sys-apps/coreutils sys-process/procps app-misc/jq ;;
    *)
      warn "Gestionnaire de paquets non reconnu ($PM/$DISTRO_LIKE). Tentative avec apt (Debian/Ubuntu)..."
      if command -v apt-get >/dev/null 2>&1; then install_deps_apt; else
        die "Impossible d'installer les dépendances automatiquement sur cette distribution. Installez manuellement : curl git sudo gnupg cron docker.io docker-compose-plugin, puis relancez."
      fi ;;
  esac
  ok "Dépendances système installées (ou déjà présentes)"
progress 25 "Dépendances système installées"
else
  ok "Toutes les dépendances système sont déjà présentes"
fi

progress 35 "Installation de Docker (1-2 minutes)..."

# ---------- Docker ----------
install_docker_apt() {
  step "Installation de Docker (repo officiel docker.com)..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${ID}/gpg" 2>/dev/null | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes || \
  curl -fsSL https://download.docker.com/linux/debian/gpg | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=${ARCH_DOCKER} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io \
                     docker-buildx-plugin docker-compose-plugin
}

install_docker_dnf() {
  step "Installation de Docker (repo officiel docker.com)..."
  dnf -y remove docker docker-client docker-client-latest docker-common \
    docker-latest docker-latest-logrotate docker-logrotate docker-engine \
    podman runc 2>/dev/null || true
  # Docker fournit des repos pour fedora, centos, rhel ; rocky/almalinux/ol utilisent centos
  DOCKER_DISTRO="$ID"
  case "$ID" in rocky|almalinux|ol|virtuozzo) DOCKER_DISTRO="centos" ;; esac
  if curl -fsSL --max-time 5 "https://download.docker.com/linux/${DOCKER_DISTRO}/docker-ce.repo" -o /etc/yum.repos.d/docker-ce.repo 2>/dev/null; then
    :
  else
    curl -fsSL https://download.docker.com/linux/centos/docker-ce.repo -o /etc/yum.repos.d/docker-ce.repo
  fi
  dnf makecache 2>/dev/null || true
  dnf install -y --setopt=install_weak_deps=False \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker_pacman() {
  step "Installation de Docker via pacman..."
  pacman -Sy --noconfirm --needed docker docker-compose
}

install_docker_apk() {
  step "Installation de Docker via apk..."
  apk add --no-cache docker docker-cli-compose
  rc-update add docker default 2>/dev/null || true
}

install_docker_zypper() {
  step "Installation de Docker via zypper..."
  zypper --non-interactive install docker docker-compose docker-compose-switch
}

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  ok "Docker déjà présent : $(docker --version 2>/dev/null) ; compose : $(docker compose version --short 2>/dev/null)"
else
  case "$DISTRO_LIKE" in
    debian)   install_docker_apt ;;
    rhel)     install_docker_dnf ;;
    arch)     install_docker_pacman ;;
    alpine)   install_docker_apk ;;
    suse)     install_docker_zypper ;;
    macos)
      if command -v docker >/dev/null 2>&1; then
        ok "Docker (Docker Desktop) détecté"
      else
        die "Docker n'est pas disponible. Sur macOS, installez Docker Desktop puis relancez le script."
      fi ;;
    *)
      if command -v apt-get >/dev/null 2>&1; then install_docker_apt
      else die "Impossible d'installer Docker automatiquement sur cette distribution ($DISTRO_LIKE). Installez Docker + docker compose-plugin manuellement puis relancez."; fi
      ;;
  esac
fi

# Activer et démarrer Docker
if command -v systemctl >/dev/null 2>&1; then
  systemctl enable --now docker 2>/dev/null || warn "Impossible d'activer docker via systemctl (peut-être déjà démarré)"
elif command -v service >/dev/null 2>&1; then
  service docker start 2>/dev/null || rc-service docker start 2>/dev/null || true
fi

# Ajouter l'utilisateur au groupe docker si non-root (seulement si on est sudo)
if [ "${SUDO_USER:-}" != "" ]; then
  usermod -aG docker "$SUDO_USER" 2>/dev/null || true
fi

if ! docker info >/dev/null 2>&1; then
  die "Docker est installé mais ne répond pas. Vérifiez avec 'systemctl status docker' ou 'service docker status'."
fi
ok "Docker opérationnel"
progress 50 "Docker installé et opérationnel"

# ==============================================================
# 🔍 DIAGNOSTIC INTELLIGENT : détecte install / repair / update / reinstall
# ==============================================================
progress 55 "Analyse de l'installation existante..."
step "Diagnostic de l'installation existante..."

STATE_RAW="none"; INSTALLED_VERSION=""; INSTALL_DATE=""; ISSUES=0; WARNINGS=0; DETAILS=()
has(){ [ -e "$1" ]; }
count_container_up(){ docker ps --filter "name=$1" --format '{{.Names}}' 2>/dev/null | wc -l; }

# 1. Dossier install ?
if [ -d "$INSTALL_DIR" ]; then
  # 2. Fichier d'état ?
  if [ -f "$INSTALL_DIR/$STATE_FILE" ]; then
    STATE_RAW=$(grep -E '^state='    "$INSTALL_DIR/$STATE_FILE" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]' || echo "unknown")
    INSTALLED_VERSION=$(grep -E '^version=' "$INSTALL_DIR/$STATE_FILE" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]' || echo "?")
    INSTALL_DATE=$(grep -E '^install_date=' "$INSTALL_DIR/$STATE_FILE" 2>/dev/null | cut -d= -f2- || echo "")
  fi
  # Si le dossier existe mais sans STATE_FILE → install cassée/incomplète
  [ "$STATE_RAW" = "none" ] && STATE_RAW="incomplete"

  # 3. Vérifier les fichiers critiques
  for f in docker-compose.yml Caddyfile .env dashboard/index.html cloudcli/Dockerfile cloudcli/entrypoint.sh cloudcli/supervisord.conf scripts/status.sh; do
    if [ ! -f "$INSTALL_DIR/$f" ]; then
      DETAILS+=("fichier manquant: $f"); ISSUES=$((ISSUES+1))
    fi
  done

  # 4. Docker compose valide ?
  if has "$INSTALL_DIR/docker-compose.yml"; then
    if (cd "$INSTALL_DIR" && docker compose config --quiet) >/dev/null 2>&1; then
      : # ok
    else
      DETAILS+=("docker-compose.yml invalide"); ISSUES=$((ISSUES+1))
    fi
  fi

  # 5. Images Docker construites ?
  if docker image inspect multi-agents-cloudcli:latest >/dev/null 2>&1; then
    :
  else
    DETAILS+=("image multi-agents-cloudcli:latest absente"); ISSUES=$((ISSUES+1))
  fi

  # 6. Conteneurs Up ?
  if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
    UP_CLOUD=$(count_container_up '^cloudcli$')
    UP_CADDY=$(count_container_up '^caddy$')
    if [ "$UP_CLOUD" -eq 0 ] || [ "$UP_CADDY" -eq 0 ]; then
      DETAILS+=("conteneurs arrêtés (cloudcli=$UP_CLOUD, caddy=$UP_CADDY)"); WARNINGS=$((WARNINGS+1))
    fi
  fi

  # 7. Cron ?
  if [ -L /etc/cron.daily/cloudcli-snapshot ]; then
    :
  else
    DETAILS+=("lien cron absent"); WARNINGS=$((WARNINGS+1))
  fi

  # 8. Clé API dans .env ?
  if [ -f "$INSTALL_DIR/.env" ]; then
    if grep -qE '^OLLAMA_API_KEY=(sk-ollama|ollama).+' "$INSTALL_DIR/.env"; then
      :
    elif grep -qE '^OLLAMA_API_KEY=sk-ollama-votre-cle' "$INSTALL_DIR/.env"; then
      DETAILS+=("OLLAMA_API_KEY toujours sur la valeur exemple"); WARNINGS=$((WARNINGS+1))
    elif ! grep -qE '^OLLAMA_API_KEY=.+' "$INSTALL_DIR/.env"; then
      DETAILS+=("OLLAMA_API_KEY absente du .env"); ISSUES=$((ISSUES+1))
    fi
  fi

  # 9. Ports 80/443/3001 libres ? (si pas de conteneurs déjà en écoute)
  for PORT in 80 443 3001; do
    if ss -ltnH "sport = :$PORT" 2>/dev/null | grep -q ":$PORT"; then
      # Vérifier si c'est Caddy qui écoute — si oui c'est normal
      LISTENER_PID=$(ss -ltnHp "sport = :$PORT" 2>/dev/null | grep -oP 'pid=\K[0-9]+' | head -n1 || echo "")
      if [ -n "$LISTENER_PID" ]; then
        LISTENER_NAME=$(ps -p "$LISTENER_PID" -o comm= 2>/dev/null || echo "")
        case "$LISTENER_NAME" in
          docker-proxy|caddy|containerd-shim) : ;;
          *) DETAILS+=("port $PORT occupé par $LISTENER_NAME (PID $LISTENER_PID)"); WARNINGS=$((WARNINGS+1)) ;;
        esac
      fi
    fi
  done
fi

# 10. Décision de l'action
case "$STATE_RAW" in
  none)
    ACTION="install"
    ACTION_LABEL="🆕 NOUVELLE INSTALLATION"
    ACTION_DETAIL="Aucune installation détectée dans $INSTALL_DIR."
    ;;
  incomplete)
    ACTION="repair"
    ACTION_LABEL="🔧 RÉPARATION"
    ACTION_DETAIL="Le dossier $INSTALL_DIR existe mais n'a pas de marqueur d'état (installation interrompue ou ancienne version)."
    ;;
  ok|healthy)
    if [ "$ISSUES" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
      if [ "$INSTALLED_VERSION" = "$INSTALLER_VERSION" ]; then
        ACTION="repair"
        ACTION_LABEL="✅ INSTALLATION OK — Vérification / réparation"
        ACTION_DETAIL="Version $INSTALLED_VERSION déjà installée et saine. Relance = vérification + redémarrage si besoin."
      else
        ACTION="update"
        ACTION_LABEL="⬆️  MISE À JOUR"
        ACTION_DETAIL="Version installée : $INSTALLED_VERSION → version de l'installateur : $INSTALLER_VERSION."
      fi
    elif [ "$ISSUES" -gt 0 ]; then
      ACTION="repair"
      ACTION_LABEL="🔧 RÉPARATION"
      ACTION_DETAIL="Installation détectée (v$INSTALLED_VERSION) mais $ISSUES problème(s) critique(s) détecté(s)."
    else
      ACTION="repair"
      ACTION_LABEL="🔧 VÉRIFICATION & CORRECTION"
      ACTION_DETAIL="Installation détectée (v$INSTALLED_VERSION) avec $WARNINGS avertissement(s)."
    fi
    ;;
  failed|error|interrupted)
    ACTION="repair"
    ACTION_LABEL="🔧 RÉPARATION (échec détecté)"
    ACTION_DETAIL="La dernière installation avait échoué (état: $STATE_RAW)."
    ;;
  *)
    ACTION="repair"
    ACTION_LABEL="🔧 RÉPARATION (état inconnu)"
    ACTION_DETAIL="État précédent: '$STATE_RAW', v$INSTALLED_VERSION."
    ;;
esac

# Force action ?
if [ "$FORCE_ACTION" != "auto" ]; then
  ACTION="$FORCE_ACTION"
  ACTION_LABEL="FORCÉ: $FORCE_ACTION"
  ACTION_DETAIL="Action forcée par la variable FORCE_ACTION=$FORCE_ACTION."
fi

# Afficher le diagnostic
echo ""
echo -e "${CYAN}┌─────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}              $ACTION_LABEL"
echo -e "${CYAN}└─────────────────────────────────────────────────────┘${NC}"
echo -e "  ${CYAN}Dossier cible :${NC} $INSTALL_DIR"
echo -e "  ${CYAN}Action :${NC}       $ACTION_DETAIL"
if [ -n "$INSTALLED_VERSION" ] && [ "$INSTALLED_VERSION" != "?" ]; then
  echo -e "  ${CYAN}Version installée :${NC} $INSTALLED_VERSION  ${CYAN}(installateur :${NC} $INSTALLER_VERSION${CYAN})${NC}"
fi
if [ -n "$INSTALL_DATE" ]; then
  echo -e "  ${CYAN}Installée le :${NC}    $INSTALL_DATE"
fi
if [ "$ISSUES" -gt 0 ] || [ "$WARNINGS" -gt 0 ]; then
  echo ""
  declare -A SEEN=()
  for d in "${DETAILS[@]}"; do
    [ -n "${SEEN[$d]:-}" ] && continue
    SEEN[$d]=1
    case "$d" in
      *manquant*|*invalide*|*absente*|*absente\ du\ .env*)
        echo -e "  ${RED}✘${NC} $d" ;;
      *)
        echo -e "  ${YEL}⚠${NC} $d" ;;
    esac
  done
fi
echo ""

# Si l'installation est déjà OK et à jour en mode auto, proposer le menu
if { [ "$ACTION" = "repair" ] && [ "$ISSUES" -eq 0 ] && [ "$WARNINGS" -eq 0 ] && [ "$INSTALLED_VERSION" = "$INSTALLER_VERSION" ]; } || [ "$ACTION" = "update" ]; then
  if [ "$NONINTERACTIVE" != "1" ] && [ -t 0 ]; then
    echo -e "${YEL}Que voulez-vous faire ?${NC}"
    echo "  [1] Vérifier et redémarrer la stack (réparation légère)     — par défaut"
    echo "  [2] Mettre à jour / réécrire les fichiers de configuration"
    echo "  [3] Build complet de l'image et redémarrage (upgrade)"
    echo "  [4] Réinstallation complète (puis restaure les volumes)"
    echo "  [5] Afficher l'état (status.sh) et quitter"
    echo "  [6] Quitter sans rien faire"
    echo -n "  Choix [1-6, défaut=1] : "
    read -r CHOICE
    case "${CHOICE:-1}" in
      2) ACTION="repair-files" ;;
      3) ACTION="rebuild" ;;
      4) ACTION="reinstall" ;;
      5) bash "$INSTALL_DIR/scripts/status.sh"; exit 0 ;;
      6) echo "Annulé."; exit 0 ;;
      *) ACTION="light-restart" ;;
    esac
    echo ""
  fi
fi

# Pour reinstall, avertissement
if [ "$ACTION" = "reinstall" ]; then
  echo -e "${RED}⚠ Vous avez choisi RÉINSTALLATION COMPLÈTE.${NC}"
  echo "  Les conteneurs seront arrêtés, les images seront supprimées,"
  echo "  mais les volumes Docker (projets, sessions, config CloudCLI)"
  echo "  seront conservés. Un snapshot de pré-réinstallation sera pris"
  echo "  automatiquement dans $INSTALL_DIR/backups/."
  if [ "$NONINTERACTIVE" != "1" ] && [ -t 0 ]; then
    echo -n "  Confirmer par 'OUI' : "
    read -r C
    [ "$C" != "OUI" ] && { echo "Annulé."; exit 0; }
  fi
fi

# Snapshot de précaution si l'installation existe déjà
if [ "$STATE_RAW" != "none" ] && [ -f "$INSTALL_DIR/docker-compose.yml" ] && [ -f "$INSTALL_DIR/scripts/snapshot.sh" ]; then
  step "Snapshot de précaution avant modification..."
  (cd "$INSTALL_DIR" && bash scripts/snapshot.sh "pre-${ACTION}-$(date +%Y%m%d-%H%M%S)" >/dev/null 2>&1 && ok "Snapshot de sauvegarde créé dans backups/") || warn "Impossible de créer un snapshot (continuons)."
fi

progress 65 "Écriture des configurations..."

# ---------- Écriture des fichiers ----------
# En mode repair/light-restart on saute la réécriture des fichiers de config
SKIP_WRITE=0
case "$ACTION" in light-restart) SKIP_WRITE=1 ;; esac

if [ "$SKIP_WRITE" -eq 0 ]; then
step "Écriture de la configuration dans $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"/{cloudcli,scripts,backups,dashboard}

# Conserver l'ancien secret si .env existe déjà (évite d'invalider les comptes CloudCLI)
EXISTING_SECRET=""; EXISTING_OLLAMA=""; EXISTING_WEBUI=""
if [ -f "$INSTALL_DIR/.env" ]; then
  EXISTING_SECRET=$(grep -E '^WEBUI_SECRET_KEY=' "$INSTALL_DIR/.env" | cut -d= -f2-)
  EXISTING_OLLAMA=$(grep -E '^OLLAMA_API_KEY=' "$INSTALL_DIR/.env" | cut -d= -f2-)
  EXISTING_WEBUI=$(grep -E '^WEBUI_URL=' "$INSTALL_DIR/.env" | cut -d= -f2-)
fi
SECRET="${EXISTING_SECRET:-$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 64)}"
# Ne pas écraser la clé Ollama existante si elle est valide et qu'on n'a pas passé la nouvelle
if [ -n "$EXISTING_OLLAMA" ] && [[ "$EXISTING_OLLAMA" == sk-* ]] && [ "${OLLAMA_API_KEY:-}" = "$EXISTING_OLLAMA" ]; then
  : # la variable passée prévaut
elif [ -n "$EXISTING_OLLAMA" ] && [[ "$EXISTING_OLLAMA" == sk-* ]] && [ -z "${OLLAMA_API_KEY_ENV:-}" ]; then
  OLLAMA_API_KEY="$EXISTING_OLLAMA"
  ok "Clé Ollama existante conservée"
fi
# Conserver WEBUI_URL si l'utilisateur n'a pas passé de nouveau HOSTNAME_PUBLIQUE
if [ -n "$EXISTING_WEBUI" ] && [ "${HOSTNAME_PUBLIQUE:-}" = "localhost" ] && [ "$ACTION" != "install" ]; then
  HOSTNAME_PUBLIQUE="${EXISTING_WEBUI#https://}"
  HOSTNAME_PUBLIQUE="${HOSTNAME_PUBLIQUE%/}"
fi

cat > "$INSTALL_DIR/.env" <<EOF
# Généré par setup.sh le $(date -Iseconds)
OLLAMA_API_KEY=${OLLAMA_API_KEY}
WEBUI_URL=https://${HOSTNAME_PUBLIQUE}
ENABLE_SIGNUP=true
WEBUI_SECRET_KEY=${SECRET}
EOF
chmod 600 "$INSTALL_DIR/.env"

# ----- docker-compose.yml -----
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
      - "3001:3001"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./dashboard:/srv/dashboard:ro
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

# ----- Caddyfile -----
cat > "$INSTALL_DIR/Caddyfile" <<'EOF'
http://:80, http://:8080 { redir https://{host}{uri} permanent }
http://:3000 { redir https://{host}:3001{uri} permanent }

https://:443 {
    request_body { max_size 500MB }
    handle /* { root * /srv/dashboard; file_server }
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
    header { X-Content-Type-Options nosniff; X-Frame-Options SAMEORIGIN; Referrer-Policy strict-origin-when-cross-origin; -Server }
    tls internal; flush_interval -1
}

https://:3001 {
    request_body { max_size 500MB }
    reverse_proxy cloudcli:3001 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-Proto {scheme}
        header_up Upgrade {>Upgrade}
        header_up Connection {>Connection}
        transport http { response_header_timeout 0 }
    }
    header { X-Content-Type-Options nosniff; X-Frame-Options SAMEORIGIN; Referrer-Policy strict-origin-when-cross-origin; -Server }
    tls internal; flush_interval -1
}
EOF

# ----- Dashboard index.html (Apple-style) -----
cat > "$INSTALL_DIR/dashboard/index.html" <<'HTMLEOF'
<!DOCTYPE html>
<html lang="fr"><head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"/>
<title>VMREMOTEAGENT</title>
<link rel="icon" href="data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'><defs><linearGradient id='g' x1='0' y1='0' x2='1' y2='1'><stop offset='0' stop-color='%2300f5d4'/><stop offset='1' stop-color='%2300bbf9'/></linearGradient></defs><rect rx='14' ry='14' width='64' height='64' fill='url(%23g)'/><text x='32' y='42' font-size='34' font-family='-apple-system' text-anchor='middle' fill='white' font-weight='700'>🤖</text></svg>">
<style>
:root{--card-bg:rgba(255,255,255,.22);--card-bg-hover:rgba(255,255,255,.32);--card-border:rgba(255,255,255,.35);--text:#fff;--text-dim:rgba(255,255,255,.75);--radius:22px;--shadow:0 20px 60px rgba(0,0,0,.35)}
*{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent}
html,body{height:100%}
body{font-family:-apple-system,BlinkMacSystemFont,"SF Pro Display","Helvetica Neue",Arial,sans-serif;color:var(--text);min-height:100vh;overflow-x:hidden;background:radial-gradient(1200px 800px at 20% 10%,#ff9a8b 0%,transparent 60%),radial-gradient(1200px 800px at 80% 20%,#ff6ec4 0%,transparent 60%),radial-gradient(1400px 1000px at 50% 100%,#7873f5 0%,transparent 60%),linear-gradient(180deg,#0f2027 0%,#203a43 50%,#2c5364 100%);background-attachment:fixed;-webkit-font-smoothing:antialiased}
body::before{content:"";position:fixed;inset:0;background:radial-gradient(ellipse at top,rgba(255,255,255,.12),transparent 50%);pointer-events:none;z-index:0}
.wrap{position:relative;z-index:1;max-width:1100px;margin:0 auto;padding:56px 28px 80px}
.topbar{display:flex;align-items:center;justify-content:space-between;margin-bottom:44px}
.brand{display:flex;align-items:center;gap:14px}.brand .logo{width:44px;height:44px;border-radius:12px;background:linear-gradient(135deg,#00f5d4,#00bbf9);display:grid;place-items:center;font-size:24px;box-shadow:0 8px 20px rgba(0,187,249,.35)}
.brand h1{font-size:22px;font-weight:700;letter-spacing:-.02em}.brand small{display:block;color:var(--text-dim);font-weight:500;font-size:12px;margin-top:2px}
.clock{font-feature-settings:"tnum";font-size:15px;font-weight:600;color:var(--text-dim);background:var(--card-bg);border:1px solid var(--card-border);padding:8px 14px;border-radius:999px;backdrop-filter:blur(20px) saturate(160%);-webkit-backdrop-filter:blur(20px) saturate(160%)}
.hero{text-align:center;margin-bottom:44px}.hero h2{font-size:clamp(34px,5vw,52px);font-weight:700;letter-spacing:-.03em;line-height:1.05;text-shadow:0 2px 20px rgba(0,0,0,.2)}.hero p{margin-top:12px;color:var(--text-dim);font-size:17px;max-width:620px;margin-left:auto;margin-right:auto}
.grid{display:grid;gap:22px;grid-template-columns:repeat(auto-fill,minmax(260px,1fr))}
.card{display:flex;flex-direction:column;padding:24px;border-radius:var(--radius);background:var(--card-bg);border:1px solid var(--card-border);backdrop-filter:blur(24px) saturate(180%);-webkit-backdrop-filter:blur(24px) saturate(180%);box-shadow:var(--shadow);text-decoration:none;color:inherit;transition:transform .18s cubic-bezier(.2,.8,.2,1),background .18s,box-shadow .18s;position:relative;overflow:hidden;min-height:170px}
.card:hover{background:var(--card-bg-hover);transform:translateY(-4px);box-shadow:0 28px 70px rgba(0,0,0,.45)}
.card .icon{width:58px;height:58px;border-radius:16px;display:grid;place-items:center;font-size:30px;margin-bottom:16px;box-shadow:inset 0 0 0 1px rgba(255,255,255,.2),0 6px 16px rgba(0,0,0,.2)}
.card h3{font-size:19px;font-weight:600;letter-spacing:-.01em}.card p{margin-top:6px;color:var(--text-dim);font-size:14px;line-height:1.45}
.card .meta{margin-top:auto;padding-top:18px;display:flex;align-items:center;gap:8px;font-size:13px;color:var(--text-dim);font-weight:500}
.dot{width:8px;height:8px;border-radius:50%;background:#30d158;box-shadow:0 0 12px #30d158}.dot.orange{background:#ff9f0a;box-shadow:0 0 12px #ff9f0a}.arrow{margin-left:auto;font-size:18px;opacity:.7;transition:transform .18s}.card:hover .arrow{transform:translateX(4px);opacity:1}
.i-blue{background:linear-gradient(135deg,#0a84ff,#5ac8fa)}.i-purple{background:linear-gradient(135deg,#bf5af2,#5e5ce6)}.i-green{background:linear-gradient(135deg,#30d158,#34c759)}.i-orange{background:linear-gradient(135deg,#ff9f0a,#ff375f)}.i-teal{background:linear-gradient(135deg,#00c7be,#64d2ff)}.i-gray{background:linear-gradient(135deg,#636366,#8e8e93)}.i-indigo{background:linear-gradient(135deg,#5856d6,#af52de)}
footer{margin-top:56px;text-align:center;color:var(--text-dim);font-size:13px}
@media (max-width:520px){.wrap{padding:32px 18px 60px}.hero h2{font-size:32px}.topbar{margin-bottom:28px}.brand h1{font-size:18px}}
</style></head><body>
<div class="wrap"><div class="topbar"><div class="brand"><div class="logo">🤖</div><div><h1 id="host">VMREMOTEAGENT</h1><small>Multi-agents · Claude Code · Codex · code-server</small></div></div><div class="clock" id="clock">--:--</div></div>
<section class="hero"><h2>Bienvenue.</h2><p>Votre plateforme d'agents IA est en ligne. Choisissez un service pour commencer.</p></section>
<main class="grid">
<a class="card" href="https://AGENT_HOST" rel="noopener"><div class="icon i-blue">🧠</div><h3>Agents CloudCLI</h3><p>Pilotez Claude Code et Codex depuis le web/mobile : chat, projets, fichiers, Git, terminal, MCP.</p><div class="meta"><span class="dot"></span> En ligne<span class="arrow">→</span></div></a>
<a class="card" href="/ide/" rel="noopener"><div class="icon i-purple">💻</div><h3>Éditeur IDE</h3><p>VS Code dans le navigateur, sur le même workspace que vos agents. Extensions, terminal, debug.</p><div class="meta"><span class="dot"></span> code-server<span class="arrow">→</span></div></a>
<a class="card" href="https://ollama.com/settings/keys" target="_blank" rel="noopener"><div class="icon i-teal">🔑</div><h3>Clé Ollama Cloud</h3><p>Gérez votre clé API, surveillez la conso et découvrez de nouveaux modèles sur ollama.com.</p><div class="meta"><span class="dot orange"></span> Site externe<span class="arrow">↗</span></div></a>
<a class="card" href="#" onclick="alert('📸 Snapshot manuel :\n\n  cd /opt/multi-agents && ./scripts/snapshot.sh <nom>\n\nRestauration : ./scripts/restore.sh <nom>');return false;"><div class="icon i-green">💾</div><h3>Sauvegarder</h3><p>Créez un snapshot instantané de toute la stack avant une mission risquée.</p><div class="meta"><span class="dot orange"></span> Terminal<span class="arrow">→</span></div></a>
<a class="card" href="#" onclick="alert('🩺 Diagnostic et réparation automatique :\n\n  cd /opt/multi-agents && ./scripts/doctor.sh\n\nPour réparer automatiquement :\n\n  ./scripts/doctor.sh --fix\n\n(Aperçu rapide : ./scripts/status.sh).');return false;"><div class="icon i-indigo">📊</div><h3>État / Réparer</h3><p>Diagnostique automatiquement la stack et répare les fichiers, conteneurs ou config cassés.</p><div class="meta"><span class="dot"></span> Doctor · auto-réparation<span class="arrow">→</span></div></a>
<a class="card" href="https://github.com/Tiij/VMREMOTEAGENT" target="_blank" rel="noopener"><div class="icon i-gray">📘</div><h3>Documentation</h3><p>README, guide d'installation, commandes utiles et dépannage sur GitHub.</p><div class="meta"><span class="dot orange"></span> GitHub<span class="arrow">↗</span></div></a>
<a class="card" href="#" onclick="alert('🚀 Mettre à jour VMREMOTEAGENT :\n\n  cd /opt/multi-agents && sudo ./scripts/update.sh\n\nVérifier seulement (sans modifier) :\n\n  sudo ./scripts/update.sh --check\n\nLe script sauvegarde automatiquement avant la MAJ et fait un rollback si la nouvelle version ne démarre pas.');return false;"><div class="icon i-orange">🚀</div><h3>Mettre à jour</h3><p>Vérifie si une nouvelle version est disponible (channel stable), sauvegarde, met à jour, avec rollback automatique si problème.</p><div class="meta"><span class="dot orange" id="upd-dot"></span> 1 commande<span class="arrow">→</span></div></a>
</main>
<footer><span id="foot">VMREMOTEAGENT</span> · CloudCLI + code-server + Caddy · backend Ollama Cloud</footer></div>
<script>
const host=window.location.hostname,proto=window.location.protocol,agentUrl=`${proto}//${host}:3001/`;
document.querySelectorAll('a[href="https://AGENT_HOST"]').forEach(a=>a.href=agentUrl);
document.getElementById('host').textContent=host;document.getElementById('foot').textContent=host;
function tick(){const d=new Date();document.getElementById('clock').textContent=`${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}:${String(d.getSeconds()).padStart(2,'0')}`;}tick();setInterval(tick,1000);
</script></body></html>
HTMLEOF

# ----- cloudcli/Dockerfile -----
cat > "$INSTALL_DIR/cloudcli/Dockerfile" <<'EOF'
FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8 TZ=Europe/Paris
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl wget git unzip zip jq sudo htop tmux neovim ripgrep fd-find build-essential python3 python3-pip python3-venv pipx openssh-client gnupg procps xz-utils supervisor tini chromium fonts-noto-color-emoji && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && apt-get install -y nodejs && rm -rf /var/lib/apt/lists/* && npm install -g npm@latest
RUN npm install -g @anthropic-ai/claude-code @openai/codex @cloudcli-ai/cloudcli
RUN curl -fsSL https://code-server.dev/install.sh | sh && rm -rf /var/lib/apt/lists/*
RUN useradd -m -u 1000 agent -s /bin/bash && echo "agent ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agent && mkdir -p /home/agent/.cloudcli /home/agent/.claude /home/agent/.codex /home/agent/.local/share/code-server /home/agent/.config/code-server /home/agent/workspace /home/agent/.cache && chown -R agent:agent /home/agent
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
ENV ANTHROPIC_BASE_URL=https://ollama.com ANTHROPIC_AUTH_TOKEN=__OLLAMA_API_KEY__ ANTHROPIC_API_KEY="" ANTHROPIC_MODEL=qwen3-coder:cloud ANTHROPIC_SMALL_FAST_MODEL=qwen3-coder:cloud ANTHROPIC_DEFAULT_SONNET_MODEL=qwen3-coder:cloud ANTHROPIC_DEFAULT_HAIKU_MODEL=qwen3-coder:cloud ANTHROPIC_DEFAULT_OPUS_MODEL=qwen3-coder:cloud OPENAI_BASE_URL=https://ollama.com/v1 OPENAI_API_KEY=__OLLAMA_API_KEY__ CHROME_BIN=/usr/bin/chromium SERVER_PORT=3001 HOST=0.0.0.0 DATABASE_PATH=/home/agent/.cloudcli/auth.db
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
WORKDIR /home/agent/workspace
USER agent
COPY --chown=agent:agent entrypoint.sh /home/agent/entrypoint.sh
USER root;RUN chmod +x /home/agent/entrypoint.sh && chown agent:agent /home/agent/entrypoint.sh;USER agent
EXPOSE 3001 8080
ENTRYPOINT ["/usr/bin/tini","--","/home/agent/entrypoint.sh"]
CMD ["/usr/bin/supervisord","-c","/etc/supervisor/conf.d/supervisord.conf"]
EOF

# ----- cloudcli/entrypoint.sh -----
cat > "$INSTALL_DIR/cloudcli/entrypoint.sh" <<'EOF'
#!/bin/bash
set -e
KEY="${OLLAMA_API_KEY:-ollama}";export ANTHROPIC_AUTH_TOKEN="$KEY";export OPENAI_API_KEY="$KEY"
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
{"env":{"ANTHROPIC_BASE_URL":"https://ollama.com","ANTHROPIC_AUTH_TOKEN":"$KEY","ANTHROPIC_API_KEY":"","ANTHROPIC_MODEL":"qwen3-coder:cloud","ANTHROPIC_SMALL_FAST_MODEL":"qwen3-coder:cloud","ANTHROPIC_DEFAULT_SONNET_MODEL":"qwen3-coder:cloud","ANTHROPIC_DEFAULT_HAIKU_MODEL":"qwen3-coder:cloud","ANTHROPIC_DEFAULT_OPUS_MODEL":"qwen3-coder:cloud"}}
JSONEOF
sudo chown -R agent:agent /home/agent/.cloudcli /home/agent/.claude /home/agent/.codex /home/agent/workspace /home/agent/.config /home/agent/.local 2>/dev/null || true
cd /home/agent/workspace;exec "$@"
EOF
chmod +x "$INSTALL_DIR/cloudcli/entrypoint.sh"

# ----- cloudcli/supervisord.conf -----
cat > "$INSTALL_DIR/cloudcli/supervisord.conf" <<'EOF'
[supervisord]
nodaemon=true;user=agent;logfile=/tmp/supervisord.log;pidfile=/tmp/supervisord.pid;logfile_maxbytes=10MB;logfile_backups=2
[program:cloudcli]
command=/usr/local/bin/cloudcli start --port 3001
directory=/home/agent/workspace;environment=HOME="/home/agent",USER="agent";autostart=true;autorestart=true;stdout_logfile=/dev/stdout;stdout_logfile_maxbytes=0;stderr_logfile=/dev/stderr;stderr_logfile_maxbytes=0;stopsignal=SIGTERM;stopwaitsecs=15
[program:codeserver]
command=/usr/bin/code-server --bind-addr 0.0.0.0:8080 --disable-telemetry --auth none --proxy-prefix /ide /home/agent/workspace
directory=/home/agent/workspace;environment=HOME="/home/agent",USER="agent";autostart=true;autorestart=true;stdout_logfile=/dev/stdout;stdout_logfile_maxbytes=0;stderr_logfile=/dev/stderr;stderr_logfile_maxbytes=0;stopsignal=SIGTERM;stopwaitsecs=15
EOF

# ----- scripts/ -----
write_script(){ local tgt="$1" perm="$2"; shift 2; cat > "$tgt"; chmod "$perm" "$tgt"; }
mkdir -p "$INSTALL_DIR/scripts"

# ----- VERSION (pour le script update.sh) -----
cat > "$INSTALL_DIR/VERSION" <<VEOF
${INSTALLER_VERSION}
VEOF

# ----- scripts/update.sh -----
write_script "$INSTALL_DIR/scripts/update.sh" 755 <<'UPDEOF'
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

UPDEOF

write_script "$INSTALL_DIR/scripts/snapshot.sh" 755 <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
BD="$(pwd)/backups";mkdir -p "$BD";NAME="${1:-snapshot-$(date +%Y%m%d-%H%M%S)}";A="$BD/${NAME}.tar.gz"
echo "📸 Snapshot: $A";TMP="$(mktemp -d)";trap 'rm -rf "$TMP"' EXIT
VOLS=(cloudcli-data claude-data codex-data codeserver-data codeserver-config projects caddy-data caddy-config)
PREF="$(docker compose config --format json 2>/dev/null|grep -o '"Name":"[^"]*_cloudcli-data"'|head -n1|sed 's/.*"Name":"//;s/_cloudcli-data.*//')"
[ -n "$PREF" ] && for i in "${!VOLS[@]}";do VOLS[$i]="${PREF}_${VOLS[$i]}";done
mkdir -p "$TMP/volumes"
for V in "${VOLS[@]}";do echo "  • export $V";docker run --rm -v "$V:/source:ro" -v "$TMP/volumes:/backup" alpine sh -c "cd /source&&tar czf /backup/${V}.tar.gz .";done
mkdir -p "$TMP/config";cp docker-compose.yml Caddyfile "$TMP/config/" 2>/dev/null||true;[ -f .env ]&&cp .env "$TMP/config/.env";cp -r cloudcli "$TMP/config/cloudcli" 2>/dev/null||true
{ echo "snapshot_date: $(date -Iseconds)";echo "hostname: $(hostname)";docker compose images;} > "$TMP/MANIFEST.txt"
tar czf "$A" -C "$TMP" .;echo "✅ $A ($(du -h "$A"|cut -f1))"
EOS

write_script "$INSTALL_DIR/scripts/restore.sh" 755 <<'EOS'
#!/usr/bin/env bash
set -euo pipefail;cd "$(dirname "${BASH_SOURCE[0]}")/.."
[ -z "${1:-}" ]&&{ echo "Usage: $0 <nom>";ls -1 backups/*.tar.gz 2>/dev/null|xargs -n1 basename|sed 's/\.tar\.gz$//';exit 1;}
I="$1";[ -f "$I" ]&&A="$I"||[ -f "backups/$I" ]&&A="backups/$I"||[ -f "backups/${I}.tar.gz" ]&&A="backups/${I}.tar.gz"||{ echo "Introuvable: $I";exit 1;}
read -p "⚠ REMPLACE l'état actuel. Taper OUI : " C;[ "$C" != "OUI" ]&&{ echo "Annulé.";exit 0;}
TMP="$(mktemp -d)";trap 'rm -rf "$TMP"' EXIT;echo "📦 Extraction...";tar xzf "$A" -C "$TMP";echo "🛑 Arrêt...";docker compose down
PREF="$(docker compose config --format json 2>/dev/null|grep -o '"Name":"[^"]*_cloudcli-data"'|head -n1|sed 's/.*"Name":"//;s/_cloudcli-data.*//')";[ -z "$PREF" ]&&PREF="multi-agents"
for V in cloudcli-data claude-data codex-data codeserver-data codeserver-config projects caddy-data caddy-config;do docker volume rm "${PREF}_$V" 2>/dev/null||true;done
echo "♻ Import...";for V in cloudcli-data claude-data codex-data codeserver-data codeserver-config projects caddy-data caddy-config;do
  F="$TMP/volumes/${PREF}_$V.tar.gz";[ ! -f "$F" ]&&F="$TMP/volumes/multi-agents_$V.tar.gz";[ ! -f "$F" ]&&{ echo "⚠ $V absent";continue;}
  docker volume create "${PREF}_$V">/dev/null;docker run --rm -v "${PREF}_$V:/target" -v "$TMP/volumes:/backup:ro" alpine sh -c "cd /target&&tar xzf /backup/$(basename "$F")"
done
echo "▶ Redémarrage...";docker compose up -d --build;echo "✅ Restauré."
EOS

write_script "$INSTALL_DIR/scripts/factory-reset.sh" 755 <<'EOS'
#!/usr/bin/env bash;set -euo pipefail;cd "$(dirname "${BASH_SOURCE[0]}")/.."
read -p "⚠ TOUT SUPPRIMER ? Taper 'SUPPRIMER TOUT' : " C;[ "$C" != "SUPPRIMER TOUT" ]&&{ echo "Annulé.";exit 0;}
docker compose down -v;echo "✅ Reset. Relance: docker compose up -d --build"
EOS

write_script "$INSTALL_DIR/scripts/auto-snapshot.sh" 755 <<'EOS'
#!/usr/bin/env bash;set -euo pipefail;SD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."&&pwd)";cd "$SD";KEEP="${SNAPSHOT_KEEP:-14}";LF="${SNAPSHOT_LOG:-/var/log/cloudcli-snapshot.log}";mkdir -p backups "$(dirname "$LF")"
ts(){ date '+%Y-%m-%d %H:%M:%S';};log(){ echo "[$(ts)] $*"|tee -a "$LF";}
log "📸 Snapshot auto (KEEP=$KEEP)";NAME="auto-$(date +%Y%m%d-%H%M%S)"
if ./scripts/snapshot.sh "$NAME">>"$LF" 2>&1;then log "✅ backups/${NAME}.tar.gz";else log "❌ ERREUR";exit 1;fi
mapfile -t OLD < <(ls -1t backups/auto-*.tar.gz 2>/dev/null|tail -n +$((KEEP+1)));((${#OLD[@]}>0))&&{ log "🗑 Suppression ${#OLD[@]} anciens auto";rm -f "${OLD[@]}";}
DEL=$(find backups -maxdepth 1 -name "snapshot-*.tar.gz" -mtime +30 -print -delete 2>/dev/null|wc -l);((DEL>0))&&log "🗑 $DEL snapshot(s) manuel(s) >30j"
SIZE=$(du -sh backups|cut -f1);CNT=$(ls -1 backups/*.tar.gz 2>/dev/null|wc -l);log "📂 $CNT archives, $SIZE — terminé"
EOS

write_script "$INSTALL_DIR/scripts/status.sh" 755 <<'EOS'
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

EOS

write_script "$INSTALL_DIR/scripts/doctor.sh" 755 <<'EOS'
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

EOS

ok "Fichiers de config écrits"
fi # SKIP_WRITE

progress 75 "Configuration des sauvegardes automatiques..."

# ---------- Cron backup ----------
step "Configuration du cron de sauvegarde quotidien..."
ln -sf "$INSTALL_DIR/scripts/auto-snapshot.sh" /etc/cron.daily/cloudcli-snapshot
chmod +x "$INSTALL_DIR/scripts/"*.sh
CRON_SVC="cron"
command -v crond >/dev/null 2>&1 && CRON_SVC="crond"
systemctl enable --now "$CRON_SVC" 2>/dev/null || true
mkdir -p /var/log && touch /var/log/cloudcli-snapshot.log && chmod 644 /var/log/cloudcli-snapshot.log
ok "Cron quotidien installé → /etc/cron.daily/cloudcli-snapshot"

progress 82 "Build Docker & démarrage (5-15 min au premier run)..."

# ---------- Build & start (selon l'action décidée par le diagnostic) ----------
BUILD_ACTION="--build"
UP_ACTION="up -d"
case "$ACTION" in
  light-restart)
    BUILD_ACTION=""
    step "Redémarrage léger (sans rebuild)..."
    ;;
  repair-files)
    step "Réécriture des fichiers + redémarrage..."
    ;;
  rebuild|reinstall)
    step "Build complet de l'image et redémarrage..."
    if [ "$ACTION" = "rebuild" ]; then
      (cd "$INSTALL_DIR" && docker compose down 2>/dev/null || true)
      docker image rm -f multi-agents-cloudcli:latest >/dev/null 2>&1 || true
    fi
    ;;
  install|repair|update|*)
    step "Build des images Docker et démarrage (5-15 min au premier run)..."
    ;;
esac

if [ "${NO_BUILD:-}" = "1" ]; then
  warn "NO_BUILD=1, démarrage ignoré. Lancez : cd $INSTALL_DIR && docker compose up -d --build"
  FINAL_STATE="setup-ok-nobuild"
else
  cd "$INSTALL_DIR"
  if docker compose $UP_ACTION $BUILD_ACTION 2>&1 | tee -a "$LOG_FILE"; then
    ok "Stack démarrée"
    FINAL_STATE="starting"
  else
    # Marquer l'échec
    { echo "state=failed"
      echo "version=$INSTALLER_VERSION"
      echo "fail_date=$(date -Iseconds)"
      echo "action=$ACTION"
    } > "$INSTALL_DIR/$STATE_FILE"
    FINAL_STATE="failed"
    progress_done
    echo ""
    bad "Build/démarrage échoué. Log: $LOG_FILE"
    warn "État sauvegardé dans $INSTALL_DIR/$STATE_FILE. Le rollback et le diagnostic vont être proposés."
    # Ne pas exit — continuer vers l'écran d'échec final
  fi

  if [ "$FINAL_STATE" != "failed" ]; then
  progress 95 "Vérification du service (healthcheck)..."

# ---------- Healthcheck post-install ----------
  step "Vérification du service (healthcheck, ${HEALTH_TIMEOUT}s max)..."
  HEALTH_OK=0
  for i in $(seq 1 $HEALTH_TIMEOUT); do
    UP1=$(count_container_up '^cloudcli$')
    UP2=$(count_container_up '^caddy$')
    if [ "$UP1" -eq 1 ] && [ "$UP2" -eq 1 ]; then
      if curl -kfsS --max-time 3 https://127.0.0.1/ -o /dev/null 2>/dev/null; then
        HEALTH_OK=1; break
      fi
    fi
    sleep 1
  done

  if [ "$HEALTH_OK" -eq 1 ]; then
    ok "Healthcheck OK : conteneurs Up + dashboard répond en HTTPS"
    FINAL_STATE="healthy"
  else
    warn "Healthcheck: conteneurs Up mais le dashboard ne répond pas encore (attendez 30-60s supplémentaires, premier lancement de code-server/CloudCLI)."
    FINAL_STATE="starting"
  fi
  fi  # close failed guard
fi  # close NO_BUILD else

progress 98 "Finalisation..."

# ---------- Écrire le fichier d'état ----------
cat > "$INSTALL_DIR/$STATE_FILE" <<EOF
# VMREMOTEAGENT state file — ne pas supprimer
state=$FINAL_STATE
version=$INSTALLER_VERSION
install_date=$([ -n "${INSTALL_DATE:-}" ] && echo "$INSTALL_DATE" || date -Iseconds)
last_action=$ACTION
last_run=$(date -Iseconds)
install_dir=$INSTALL_DIR
host=$HOSTNAME_PUBLIQUE
EOF
ok "État sauvegardé ($FINAL_STATE)"

progress_done

# ---------- Écran final : succès ou échec ----------
SUCCESS_MSG="Dashboard :          https://${HOSTNAME_PUBLIQUE}/
Agents CloudCLI :    https://${HOSTNAME_PUBLIQUE}:3001/
code-server (IDE) :  https://${HOSTNAME_PUBLIQUE}/ide/

Première visite :
  1. Ouvrez https://${HOSTNAME_PUBLIQUE}/
  2. Acceptez l'avertissement de certificat auto-signé.
  3. Cliquez sur 'Agents CloudCLI' et définissez votre mot de passe.
  4. Pour un vrai certificat HTTPS (cadenas vert), ajoutez un domaine
     pointant vers cette IP, éditez le Caddyfile (remplacez :443 par
     votre domaine et supprimez 'tls internal'), puis
     'docker compose restart caddy' — Let's Encrypt fera le reste.

Commandes utiles (dans $INSTALL_DIR) :
  ./scripts/doctor.sh --fix     diagnostique ET répare en cas de problème
  ./scripts/update.sh           met à jour automatiquement
  ./scripts/snapshot.sh <nom>   sauvegarde avant une mission risquée
  ./scripts/restore.sh <nom>    restaure un snapshot
  ./scripts/status.sh           état rapide de la stack

Dossier d'installation : $INSTALL_DIR
Log complet :            $LOG_FILE
Version :                v$INSTALLER_VERSION ($FINAL_STATE)
"

if [ "$FINAL_STATE" = "healthy" ] || [ "$FINAL_STATE" = "setup-ok-nobuild" ] || [ "$FINAL_STATE" = "starting" ]; then
  echo ""
  echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}✅  Installation terminée avec succès !${NC}"
  echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "$SUCCESS_MSG"
  echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"

  if [ "$USE_TUI" -eq 1 ]; then
    whiptail --title "✅ Installation réussie" --msgbox "$SUCCESS_MSG" 25 78
  fi
  cleanup_lock
  exit 0
else
  ERR_MSG="L'installation a rencontré un problème (état final: $FINAL_STATE).

Ce que vous pouvez faire :

  1. Consultez les logs pour identifier l'erreur :
       tail -n 100 $LOG_FILE
       cd $INSTALL_DIR && docker compose logs cloudcli | tail -n 50

  2. Lancez l'outil de diagnostic & réparation :
       cd $INSTALL_DIR && ./scripts/doctor.sh --fix

  3. Relancez simplement l'installation (idempotent) :
       curl -fsSL https://raw.githubusercontent.com/Tiij/VMREMOTEAGENT/main/setup.sh | sudo bash
     L'installateur détectera automatiquement l'installation partielle
     et reprendra en mode réparation.

  4. Si vous avez fait un snapshot pendant l'installation, vous pouvez
     restaurer l'état précédent avec :
       cd $INSTALL_DIR && ls -t backups/pre-*.tar.gz | head -1
       ./scripts/restore.sh <nom-du-snapshot>

Verrou d'installation libéré. Aucune donnée n'a été perdue.
"
  echo ""
  echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
  echo -e "${RED}✘  L'installation n'a pas abouti (état: $FINAL_STATE)${NC}"
  echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "$ERR_MSG"
  echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"

  if [ "$USE_TUI" -eq 1 ]; then
    whiptail --title "✘ Échec de l'installation" --msgbox "$ERR_MSG" 25 78
  fi
  cleanup_lock
  exit 1
fi
