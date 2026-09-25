#!/usr/bin/env bash
# =================================================================
# Installation automatique CloudCLI + Caddy sur Ubuntu/Debian
# Installe Docker si besoin, crée le .env, build l'image,
# configure la sauvegarde quotidienne automatique.
# =================================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "⚠️  Lance en root :  sudo ./install.sh" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- 1) Docker ---
if ! command -v docker >/dev/null 2>&1; then
  echo "🐳 Installation de Docker..."
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  OS_ID=$(. /etc/os-release && echo "$ID")
  OS_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
  curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" 2>/dev/null | \
     gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes || \
  curl -fsSL https://download.docker.com/linux/debian/gpg | \
     gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS_ID} ${OS_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
else
  echo "✅ Docker : $(docker --version)"
fi

# --- 2) Fichier .env ---
if [[ ! -f .env ]]; then
  cp .env.example .env
  SECRET=$(head -c 32 /dev/urandom | xxd -p -c 64)
  sed -i "s|^WEBUI_SECRET_KEY=.*|WEBUI_SECRET_KEY=${SECRET}|" .env
  echo
  echo "✏️  Édite .env pour y mettre :"
  echo "     OLLAMA_API_KEY=sk-ollama-...  (https://ollama.com/settings/keys)"
  echo "     WEBUI_URL=https://<IP_PUBLIQUE_DE_LA_VM>"
  echo
else
  echo "✅ .env existe déjà."
fi

# --- 3) Dossiers & droits des scripts de backup ---
mkdir -p backups
chmod +x scripts/*.sh 2>/dev/null || true

# --- 4) Sauvegarde automatique quotidienne (cron ou systemd-timer) ---
echo "📼 Configuration des sauvegardes automatiques quotidiennes..."

# Installer cron si absent
if ! command -v cron >/dev/null 2>&1 && ! command -v crond >/dev/null 2>&1; then
  echo "  ↳ installation de cron..."
  apt-get update -y && apt-get install -y --no-install-recommends cron
fi

# Lien symbolique dans cron.daily (lancé chaque jour par run-parts,
# généralement entre 6h et 8h du matin selon la distro)
ln -sf "$SCRIPT_DIR/scripts/auto-snapshot.sh" /etc/cron.daily/cloudcli-snapshot

# Garantir que le script est exécutable
chmod +x "$SCRIPT_DIR/scripts/auto-snapshot.sh"

# Démarrer + activer le service cron si on le vient d'installer
if command -v cron >/dev/null 2>&1; then
  systemctl enable --now cron 2>/dev/null || true
fi

# Créer le fichier de log avec droits ouverts pour que cron puisse écrire
touch /var/log/cloudcli-snapshot.log
chmod 644 /var/log/cloudcli-snapshot.log

echo "  ✅ Sauvegarde quotidienne installée :"
echo "     • Script : /etc/cron.daily/cloudcli-snapshot → $SCRIPT_DIR/scripts/auto-snapshot.sh"
echo "     • Archives : $SCRIPT_DIR/backups/"
echo "     • Log : /var/log/cloudcli-snapshot.log"
echo "     • Conservation : 14 snapshots auto (30j pour les manuels)"
echo "     • Variable SNAPSHOT_KEEP pour changer la rétention si besoin"
echo

cat <<EOF
🚪 Ouvre les ports 80 et 443 dans ton firewall / security-group.

Puis :
    docker compose up -d --build

Au premier lancement, ouvre https://<IP>/ :
  1. Le certificat est auto-signé (accepte l'avertissement).
  2. CloudCLI te demande de définir un mot de passe (compte local).
  3. Tu peux créer plusieurs projets, lancer Claude Code OU Codex
     dans chacun, et basculer entre eux depuis le navigateur
     PC comme téléphone.
  4. https://<IP>/ide/ ouvre VS Code (code-server) sur le même workspace.

📼 Pour tester la sauvegarde immédiatement :
    ./scripts/snapshot.sh test-premier-snapshot
    ls -lh backups/
EOF
