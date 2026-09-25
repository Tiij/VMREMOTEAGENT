# 📘 Tutoriel complet : Installer CloudCLI + Claude Code + Codex + code-server sur ta VM
# Backend : Ollama Cloud — Accès : navigateur PC + téléphone

> Prérequis : une VM Ubuntu **22.04/24.04** ou Debian **12**, avec accès SSH.
> Aucun GPU n'est nécessaire sur la VM (les modèles tournent sur Ollama Cloud).
> Compte environ **15-20 minutes** pour tout installer.

---

## Étape 1 — Préparer la VM

### 1.1 Se connecter en SSH
Depuis ton PC :
```bash
ssh ton_utilisateur@<IP_DE_LA_VM>
```

### 1.2 Passer root
Toute la suite se fait en root pour simplifier :
```bash
sudo -i
```

### 1.3 Mettre à jour le système
```bash
apt update && apt upgrade -y
```

### 1.4 Installer les outils de base
```bash
apt install -y curl git wget nano sudo
```

---

## Étape 2 — Vérifier les ports du pare-feu

### Si tu utilises `ufw` (pare-feu Ubuntu par défaut)
```bash
ufw allow 80/tcp
ufw allow 443/tcp
ufw status
```

### Si tu es sur un cloud provider (Hetzner, OVH, AWS, etc.)
Pense aussi à ouvrir les ports **80** et **443** dans le **Security Group** /
**pare-feu externe** de ton fournisseur (les ports 7682/8443/3001/8080
ne sont PAS à ouvrir : seul Caddy est exposé, en 80/443).

---

## Étape 3 — Créer ta clé API Ollama Cloud

1. Sur ton PC, ouvre https://ollama.com/settings/keys
2. Connecte-toi / crée un compte
3. Clique sur **"Create API key"**
4. Donne-lui un nom (ex: `ma-vm-agents`)
5. **Copie la clé** qui commence par `sk-ollama-...` — tu la colleras dans
   le fichier `.env` juste après.

Note : la clé n'apparaîtra qu'une seule fois, garde-la dans un coin.

---

## Étape 4 — Récupérer les fichiers de la stack

### Option A : tu as déjà copié le dossier `multi-agents` sur la VM
Si le dossier est déjà présent (par exemple via SCP, SFTP ou le
partage de fichiers Arena), passe directement à l'étape 5.

### Option B : créer les fichiers à la main (méthode fiable)

Crée un dossier de travail :
```bash
mkdir -p /opt/multi-agents/cloudcli
cd /opt/multi-agents
```

Crée chaque fichier ci-dessous avec `nano <nom-du-fichier>`,
colle le contenu avec **Ctrl+Shift+V**, enregistre avec **Ctrl+O**
puis **Entrée**, et quitte avec **Ctrl+X**.

---

### 📄 Fichier 1 : `docker-compose.yml`
```bash
nano /opt/multi-agents/docker-compose.yml
```

Colle :
```yaml
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
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
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
```

---

### 📄 Fichier 2 : `Caddyfile`
```bash
nano /opt/multi-agents/Caddyfile
```

Colle :
```caddy
:80, :443 {
    request_body { max_size 500MB }

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

    handle /* {
        reverse_proxy cloudcli:3001 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-Proto {scheme}
            header_up Upgrade {>Upgrade}
            header_up Connection {>Connection}
            transport http { response_header_timeout 0 }
        }
    }

    header {
        X-Content-Type-Options nosniff
        X-Frame-Options SAMEORIGIN
        Referrer-Policy strict-origin-when-cross-origin
        -Server
    }

    tls internal
    flush_interval -1
}
```

---

### 📄 Fichier 3 : `.env.example`
```bash
nano /opt/multi-agents/.env.example
```

Colle :
```ini
OLLAMA_API_KEY=sk-ollama-votre-cle-ici
WEBUI_URL=https://localhost
ENABLE_SIGNUP=true
WEBUI_SECRET_KEY=
```

---

### 📄 Fichier 4 : `install.sh`
```bash
nano /opt/multi-agents/install.sh
```

Colle :
```bash
#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "⚠️  Lance en root : sudo ./install.sh" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

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

cat <<'EOF'
🚪 Vérifie que les ports 80 et 443 sont ouverts.

Puis lance :
    docker compose up -d --build

Au premier démarrage, ouvre https://<IP>/ :
  1. Certificat auto-signé → accepte l'avertissement.
  2. CloudCLI te demande un mot de passe (compte local).
  3. Tu peux créer des projets et lancer Claude Code ou Codex.
  4. https://<IP>/ide/ ouvre VS Code (code-server) sur le même workspace.
EOF
```

Rends le script exécutable :
```bash
chmod +x /opt/multi-agents/install.sh
```

---

### 📄 Fichier 5 : `cloudcli/Dockerfile`
```bash
nano /opt/multi-agents/cloudcli/Dockerfile
```

Colle :
```dockerfile
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 LC_ALL=C.UTF-8 TZ=Europe/Paris

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget git unzip zip jq sudo htop tmux neovim ripgrep fd-find \
      build-essential python3 python3-pip python3-venv pipx \
      openssh-client gnupg procps xz-utils supervisor tini \
      chromium fonts-noto-color-emoji \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g npm@latest

RUN npm install -g @anthropic-ai/claude-code @openai/codex @cloudcli-ai/cloudcli

RUN curl -fsSL https://code-server.dev/install.sh | sh \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 1000 agent -s /bin/bash \
    && echo "agent ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agent \
    && mkdir -p /home/agent/.cloudcli /home/agent/.claude /home/agent/.codex \
                 /home/agent/.local/share/code-server \
                 /home/agent/.config/code-server \
                 /home/agent/workspace /home/agent/.cache \
    && chown -R agent:agent /home/agent

RUN cat > /home/agent/.codex/config.toml <<'EOF'
model_provider = "ollama_cloud"
model = "qwen3-coder:cloud"

[model_providers.ollama_cloud]
name = "Ollama Cloud"
base_url = "https://ollama.com/v1"
env_key = "OLLAMA_API_KEY"

oss_provider = "ollama_cloud"
EOF

RUN cat > /home/agent/.config/code-server/config.yaml <<'EOF'
bind-addr: 0.0.0.0:8080
auth: none
disable-telemetry: true
disable-update-check: true
EOF
RUN chown -R agent:agent /home/agent/.config

ENV ANTHROPIC_BASE_URL=https://ollama.com \
    ANTHROPIC_AUTH_TOKEN=__OLLAMA_API_KEY__ \
    ANTHROPIC_API_KEY="" \
    ANTHROPIC_MODEL=qwen3-coder:cloud \
    ANTHROPIC_SMALL_FAST_MODEL=qwen3-coder:cloud \
    ANTHROPIC_DEFAULT_SONNET_MODEL=qwen3-coder:cloud \
    ANTHROPIC_DEFAULT_HAIKU_MODEL=qwen3-coder:cloud \
    ANTHROPIC_DEFAULT_OPUS_MODEL=qwen3-coder:cloud \
    OPENAI_BASE_URL=https://ollama.com/v1 \
    OPENAI_API_KEY=__OLLAMA_API_KEY__ \
    CHROME_BIN=/usr/bin/chromium \
    SERVER_PORT=3001 \
    HOST=0.0.0.0 \
    DATABASE_PATH=/home/agent/.cloudcli/auth.db

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

WORKDIR /home/agent/workspace
USER agent

COPY --chown=agent:agent entrypoint.sh /home/agent/entrypoint.sh
USER root
RUN chmod +x /home/agent/entrypoint.sh && chown agent:agent /home/agent/entrypoint.sh
USER agent

EXPOSE 3001 8080
ENTRYPOINT ["/usr/bin/tini", "--", "/home/agent/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
```

---

### 📄 Fichier 6 : `cloudcli/entrypoint.sh`
```bash
nano /opt/multi-agents/cloudcli/entrypoint.sh
```

Colle :
```bash
#!/bin/bash
set -e

KEY="${OLLAMA_API_KEY:-ollama}"
export ANTHROPIC_AUTH_TOKEN="$KEY"
export OPENAI_API_KEY="$KEY"

cat >> /home/agent/.bashrc <<EOF
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
EOF

mkdir -p /home/agent/.claude
cat > /home/agent/.claude/settings.json <<EOF
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://ollama.com",
    "ANTHROPIC_AUTH_TOKEN": "$KEY",
    "ANTHROPIC_API_KEY": "",
    "ANTHROPIC_MODEL": "qwen3-coder:cloud",
    "ANTHROPIC_SMALL_FAST_MODEL": "qwen3-coder:cloud",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "qwen3-coder:cloud",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "qwen3-coder:cloud",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "qwen3-coder:cloud"
  }
}
EOF

sudo chown -R agent:agent /home/agent/.cloudcli /home/agent/.claude \
                           /home/agent/.codex /home/agent/workspace \
                           /home/agent/.config /home/agent/.local 2>/dev/null || true

cd /home/agent/workspace
exec "$@"
```

Rends-le exécutable :
```bash
chmod +x /opt/multi-agents/cloudcli/entrypoint.sh
```

---

### 📄 Fichier 7 : `cloudcli/supervisord.conf`
```bash
nano /opt/multi-agents/cloudcli/supervisord.conf
```

Colle :
```ini
[supervisord]
nodaemon=true
user=agent
logfile=/tmp/supervisord.log
pidfile=/tmp/supervisord.pid
logfile_maxbytes=10MB
logfile_backups=2

[program:cloudcli]
command=/usr/local/bin/cloudcli start --port 3001
directory=/home/agent/workspace
environment=HOME="/home/agent",USER="agent"
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
stopsignal=SIGTERM
stopwaitsecs=15

[program:codeserver]
command=/usr/bin/code-server --bind-addr 0.0.0.0:8080 --disable-telemetry --auth none /home/agent/workspace
directory=/home/agent/workspace
environment=HOME="/home/agent",USER="agent"
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
stopsignal=SIGTERM
stopwaitsecs=15
```

---

### Vérification
Tu dois avoir cette arborescence :
```bash
cd /opt/multi-agents && find . -type f | sort
```

Ça doit afficher :
```
./.env.example
./Caddyfile
./cloudcli/Dockerfile
./cloudcli/entrypoint.sh
./cloudcli/supervisord.conf
./docker-compose.yml
./install.sh
```

---

## Étape 5 — Lancer l'installation

```bash
cd /opt/multi-agents
./install.sh
```

Le script :
1. Installe Docker automatiquement (si absent),
2. Crée un fichier `.env` à partir de `.env.example`,
3. Génère une clé secrète aléatoire pour WebUI.

---

## Étape 6 — Configurer ta clé API

Édite le `.env` :
```bash
nano /opt/multi-agents/.env
```

Remplace :

```ini
OLLAMA_API_KEY=sk-ollama-ta-vraie-cle-ici
WEBUI_URL=https://TON.IP.PUBLIQUE
```

Exemple (remplace par ta vraie clé et ta vraie IP) :
```ini
OLLAMA_API_KEY=sk-ollama-abc123def456...
WEBUI_URL=https://203.0.113.42
```

Enregistre (Ctrl+O → Entrée) et quitte (Ctrl+X).

---

## Étape 7 — Démarrer la stack

```bash
cd /opt/multi-agents
docker compose up -d --build
```

⚠️ Le **premier build** prend entre 5 et 15 minutes (téléchargement de
Debian, Node, Chromium, Claude Code, Codex, CloudCLI, code-server).

### Suivre les logs pendant le démarrage
```bash
docker compose logs -f cloudcli
```

Attends de voir quelque chose comme :
```
cloudcli  | CloudCLI running on http://0.0.0.0:3001
cloudcli  | web server available on http://0.0.0.0:8080
```

Appuie sur **Ctrl+C** pour quitter les logs (les conteneurs continuent
de tourner en arrière-plan).

### Vérifier que tout tourne
```bash
docker compose ps
```

Tu dois voir 2 conteneurs en état **Up** :
- `caddy`
- `cloudcli`

---

## Étape 8 — Premier accès depuis ton PC

### 8.1 Ouvrir CloudCLI
Dans ton navigateur (Chrome/Firefox/Safari/Edge), va sur :
```
https://<TON_IP_PUBLIQUE>/
```

👉 Le certificat est **auto-signé** (c'est normal, tu n'as pas de
domaine). Le navigateur affiche un avertissement de sécurité :
- Chrome : clique sur **"Avancé"** → **"Continuer vers <IP> (dangereux)"**
- Firefox : **"Avancé..."** → **"Accepter le risque et continuer"**
- Safari : **"Afficher les détails"** → **"visiter ce site web"**

### 8.2 Créer ton compte CloudCLI
À la première visite, CloudCLI te demande de définir un **compte local**
(adresse email + mot de passe). Choisis un mot de passe **fort** :
c'est la clé d'accès à tous tes agents.

### 8.3 Lancer ton premier agent Claude Code
1. Clique sur **"New Project"** ou sur le workspace par défaut.
2. Dans la liste des providers/agents, choisis **Claude Code**.
3. Envoie un message test, par exemple :
   > Crée un petit serveur Node.js "Hello World" qui écoute sur le
   > port 3000 et lance-le.
4. Tu devrais voir l'agent réfléchir, créer les fichiers, lancer des
   commandes, en temps réel.

---

## Étape 9 — Ouvrir code-server (VS Code web)

Dans un nouvel onglet :
```
https://<TON_IP_PUBLIQUE>/ide/
```

Tu tombes sur VS Code dans ton navigateur. Le dossier ouvert est
`/home/agent/workspace` → **exactement le même** que celui où travaillent
Claude Code et Codex dans CloudCLI.

Tu peux donc :
- Installer des extensions (Python, ESLint, Docker, etc.),
- Éditer des fichiers à la main pendant que l'agent travaille,
- Utiliser le terminal intégré (`Ctrl+``) : il a `claude`, `codex`,
  `git`, `node`, `python`, etc. tous préinstallés et préconfigurés
  avec ta clé Ollama Cloud.

---

## Étape 10 — Accès depuis le téléphone 📱

1. Ouvre `https://<TON_IP_PUBLIQUE>/` dans Chrome ou Safari.
2. Accepte l'avertissement de certificat (même manip que sur PC).
3. Connecte-toi avec ton compte CloudCLI.
4. Optionnel : ajoute la page à l'**écran d'accueil** :
   - Android (Chrome) : menu ⋮ → **"Ajouter à l'écran d'accueil"**
   - iOS (Safari) : bouton partager □ → **"Sur l'écran d'accueil"**
5. Ça s'ouvre ensuite comme une app à part entière (PWA).

Tu peux lancer ou suivre une mission depuis ton téléphone, voir les
fichiers créés, envoyer de nouvelles instructions, etc.

---

## 🎯 Changer de modèle Ollama Cloud

Par défaut, les agents utilisent **`qwen3-coder:cloud`** (excellent pour le code).
Pour utiliser un autre modèle :

- **Dans Claude Code**, en cours de session : tape `/model` et choisis
  un autre modèle cloud (ex: `deepseek-v3.1:671b`, `llama-4-scout:cloud`,
  `glm-5:cloud`…).
- **Dans Codex**, lance `codex -m <nom-du-modele>` dans le terminal, ou
  utilise le sélecteur dans CloudCLI.

Pour voir les modèles disponibles sur Ollama Cloud :
https://ollama.com/search (cherche ceux qui ont le tag **Cloud**).

---

## 🔧 Commandes utiles

Depuis le dossier `/opt/multi-agents` :

```bash
# Voir l'état des conteneurs
docker compose ps

# Voir les logs en direct
docker compose logs -f cloudcli
docker compose logs -f caddy

# Redémarrer la stack
docker compose restart

# Arrêter la stack (conserve toutes les données)
docker compose down

# Redémarrer (après un changement de config)
docker compose up -d --build

# Mettre à jour (télécharge les dernières images)
docker compose build --pull
docker compose up -d

# Ouvrir un shell dans le conteneur cloudcli (pour débuguer)
docker compose exec cloudcli bash

# ⚠️ SUPPRIMER TOUT (projets, comptes, config) — pour reset complet
docker compose down -v
```

---

## 🔒 Recommandations de sécurité

1. **Mot de passe CloudCLI fort** dès la première visite.
2. **Ne pas laisser ENABLE_SIGNUP ouvert** si tu ajoutes Open WebUI
   (ce n'est pas activé dans cette stack, c'est pour info).
3. Si tu as un **nom de domaine** (ex: `agents.mondomaine.tld`) :
   - Fais pointer un enregistrement A vers l'IP de la VM,
   - Dans `/opt/multi-agents/Caddyfile`, remplace `:80, :443` par ton
     domaine (ex: `agents.mondomaine.tld`),
   - Supprime la ligne `tls internal`,
   - Redémarre : `docker compose restart caddy`.
   - Caddy obtiendra alors automatiquement un **vrai certificat
     Let's Encrypt** valide (plus d'avertissement navigateur,
     même sur téléphone).
4. Pense à faire des sauvegardes régulières des volumes Docker :
   les scripts `scripts/snapshot.sh` et `scripts/auto-snapshot.sh`
   sont là pour ça (voir section suivante).

---

## 💾 Étape 11 — Sauvegardes automatiques quotidiennes

Les agents peuvent modifier/supprimer des fichiers ou casser l'env.
**`install.sh` a déjà configuré un cron quotidien pour toi** (lien
symbolique `/etc/cron.daily/cloudcli-snapshot`). La première
sauvegarde se fera automatiquement cette nuit.

### 11.1 Vérifier que tout est en place
```bash
cd /opt/multi-agents
./scripts/status.sh
```

Tu dois voir :
```
✔ Sauvegarde automatique (cron.daily) : /opt/multi-agents/scripts/auto-snapshot.sh
```

### 11.2 Tester la sauvegarde MAINTENANT
Pour faire un premier snapshot sans attendre cette nuit :
```bash
./scripts/snapshot.sh premier-snapshot
```

Vérifie qu'il est là :
```bash
ls -lh backups/
```

### 11.3 Voir les logs de sauvegarde
```bash
tail -f /var/log/cloudcli-snapshot.log
```

### 11.4 Snapshot manuel avant une grosse mission agent
Avant de lancer l'agent sur une mission à risque (gros refactoring,
migration de framework, install système, etc.) :
```bash
./scripts/snapshot.sh avant-mission-xyz
```
Ça crée `backups/avant-mission-xyz.tar.gz` (config, projets, sessions
Claude/Codex, comptes CloudCLI, certs Caddy).

### 11.5 Restaurer un snapshot si l'agent a tout cassé
```bash
# Optionnel : snapshot de l'état courant avant de restaurer
./scripts/snapshot.sh avant-restauration

# Restaure un snapshot (conteneurs arrêtés/recréés/redémarrés)
./scripts/restore.sh avant-mission-xyz
```

### 11.6 Réglages de rétention
Par défaut :
- **14 snapshots "auto-*"** conservés (soit ~2 semaines),
- snapshots manuels supprimés après **30 jours**.

Pour modifier, édite le script `/etc/cron.daily/cloudcli-snapshot`
en ajoutant `SNAPSHOT_KEEP=30` devant la commande, ou sur la ligne
crontab si tu préfères utiliser crontab directement. Heure par défaut :
l'heure d'exécution de cron.daily est fixée par `/etc/crontab`
(typiquement 6h25 du matin). Pour une heure précise (ex: 3h00),
ajoute une ligne crontab manuellement :
```bash
(crontab -l 2>/dev/null; echo "0 3 * * * /opt/multi-agents/scripts/auto-snapshot.sh >> /var/log/cloudcli-snapshot.log 2>&1") | crontab -
```

### 11.7 Reset complet (tout effacer)
```bash
./scripts/factory-reset.sh
```

### 11.8 Snapshot VM côté hébergeur (RECOMMANDÉ)
Les snapshots ci-dessus sauvegardent la stack, mais pas l'OS lui-même.
Pour une sécurité maximale, utilise aussi le mécanisme de **snapshot**
de ton fournisseur cloud (Hetzner, OVH, DigitalOcean, etc.) :
1. Arrête la stack  :  `docker compose stop`
2. Prends un snapshot depuis le panel de l'hébergeur
3. Redémarre : `docker compose start`

C'est la restauration la plus fiable. Guide plus détaillé dans
`BACKUPS.md`.

---

## 🆘 Dépannage

| Problème | Cause probable | Solution |
|---|---|---|
| `ERR_CONNECTION_REFUSED` en allant sur l'IP | Les conteneurs ne sont pas démarrés | `docker compose ps` ; `docker compose logs cloudcli` |
| Erreur 502 Bad Gateway | cloudcli est encore en train de booter | Attends 30s et rafraîchis ; checke les logs |
| Les agents répondent "Auth error" / "401" | `OLLAMA_API_KEY` mal renseignée | Vérifie `.env`, puis `docker compose up -d` et vérifie que l'entrypoint a bien injecté la clé : `docker compose exec cloudcli env \| grep ANTHROPIC` |
| `claude` dit qu'il n'a pas de clé API | Variables non chargées | Les variables sont dans `~/.bashrc` : lance un nouveau shell (ou `source ~/.bashrc`) |
| Le build échoue avec une erreur de mémoire | VM trop petite | Vérifie que tu as au moins 2 Go RAM (`free -h`) ; ajoute de la RAM ou utilise une instance plus grande |
| Le cert est rouge/orange dans le navigateur | Normal en IP (auto-signé) | Accepte l'avertissement une fois, ou utilise un vrai domaine |
| Les WebSockets se ferment (code-server) | Header Upgrade manquant | Vérifie que le Caddyfile contient bien les lignes `header_up Upgrade` et `header_up Connection` |

---

## 🎉 C'est prêt !

Tu as maintenant :
- ✅ **Claude Code** et **Codex** qui tournent sur ta VM,
- ✅ Les deux alimentés par **Ollama Cloud** (pas de GPU needed),
- ✅ **CloudCLI** comme frontend web/mobile (multi-projets, chat,
  éditeur de fichiers, Git, terminal, MCP),
- ✅ **code-server** (VS Code web) sur le même workspace,
- ✅ Le tout en **HTTPS**, accessible de n'importe où sur PC et téléphone.

Bonnes missions avec tes agents ! 🤖💻📱
