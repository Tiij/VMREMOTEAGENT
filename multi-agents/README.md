# 🤖 CloudCLI (Claude Code + Codex) + code-server sur Ollama Cloud
# Contrôle web/mobile depuis n'importe où

Stack prête à déployer sur une VM Ubuntu/Debian :

- **CloudCLI** (`siteboon/claudecodeui`, AGPL-3) — frontend web multi-agents
  qui pilote **Claude Code** et **OpenAI Codex** nativement, avec chat,
  éditeur de fichiers, panneau Git, terminal intégré, support MCP,
  interface responsive mobile.
- **code-server** — **VS Code dans le navigateur** sur le **même workspace**
  que CloudCLI, pour éditer les fichiers comme dans un vrai IDE.
- **Caddy** — reverse-proxy HTTPS (certificat auto-signé ou Let's Encrypt
  automatique avec un domaine).
- Tous les agents LLM sont redirigés vers **Ollama Cloud** via ta clé
  API. Aucun GPU nécessaire sur la VM.

---

## 🏗️ Architecture

```
PC / téléphone
  │
  ├── https://<ip>/        → CloudCLI :3001   (UI multi-agents)
  └── https://<ip>/ide/    → code-server :8080 (VS Code web)
           │                       │
           │                       └── mêmes fichiers (/home/agent/workspace)
           │
           └──▶ spawn `claude` et `codex` dans des PTY
                     │
                     ├── ANTHROPIC_BASE_URL=https://ollama.com      (Claude Code)
                     └── OPENAI_BASE_URL=https://ollama.com/v1     (Codex)
                              │
                              ▼
                         Ollama Cloud  (qwen3-coder:cloud par défaut)
```

CloudCLI et code-server partagent le volume `projects/` → tu peux
commencer une tâche avec Claude Code dans CloudUI, puis ouvrir le même
dossier dans `/ide/` pour éditer finement à la main, et inversement.
Le terminal intégré de CloudCLI et celui de code-server voient tous
les deux les mêmes variables d'environnement pointées sur Ollama Cloud.

---

## 📋 Prérequis

- VM Ubuntu 22.04/24.04 ou Debian 12
- 2 vCPU / 4 Go RAM minimum
- Ports **80** et **443** ouverts
- Clé API Ollama Cloud → https://ollama.com/settings/keys

---

## 🚀 Installation

```bash
# Sur la VM, en SSH
cd multi-agents
sudo ./install.sh
nano .env                 # renseigner OLLAMA_API_KEY et WEBUI_URL
docker compose up -d --build
```

Logs du premier démarrage :
```bash
docker compose logs -f cloudcli
```

---

## 🧑‍💻 Utilisation

| URL | Service | Usage |
|---|---|---|
| `https://<IP>/` | **CloudCLI** | Piloter Claude Code / Codex : chat, fichiers, Git, terminal, MCP, multi-projets. |
| `https://<IP>/ide/` | **code-server** | VS Code complet (extensions, terminal intégré, debug, etc.) sur le même workspace. |

### Premier accès CloudCLI
1. Accepte l'avertissement du certificat auto-signé.
2. Crée un compte / mot de passe (compte local stocké dans le volume Docker).
3. Nouveau projet → choisis **Claude Code** ou **Codex** → envoie ta mission.

### code-server
- Ouvre `https://<IP>/ide/`.
- Aucun mot de passe par défaut (auth désactivée, Caddy et CloudCLI font
  office de protection). Tu peux en ajouter un en modifiant
  `/home/agent/.config/code-server/config.yaml` dans le conteneur.
- Le dossier racine est `/home/agent/workspace` → c'est le **même**
  que celui utilisé par CloudCLI et les agents.
- Tu peux installer toutes les extensions VS Code habituelles depuis
  le marketplace ouvert (Open-VSX).

### Changer de modèle Ollama Cloud
`qwen3-coder:cloud` est utilisé par défaut. Pour changer :
- **Claude Code** : `/model <nom-du-modèle:cloud>` dans la session Claude.
- **Codex** : sélecteur de modèle dans CloudCLI, ou `codex -m <modèle>`
  dans le terminal.
- Pour changer la valeur permanente, modifie `qwen3-coder:cloud` dans
  `cloudcli/Dockerfile` puis `docker compose build cloudcli &&
  docker compose up -d`.

### Accès téléphone
- CloudCLI est responsive et fonctionne sur tablette/phone.
- "Ajouter à l'écran d'accueil" depuis Chrome/Safari → PWA comme une app.
- code-server fonctionne aussi sur tablette (utiliser une vue bureau
  pour une meilleure ergonomie).

---

## 🔒 Sécurité

1. Définis un mot de passe CloudCLI fort dès la première visite.
2. Un vrai domaine + `basicauth` dans le Caddyfile ajoute une couche
   supplémentaire si la VM est exposée sur Internet.
3. Conteneur non-root (`agent`), `shm_size=2g` alloué pour Chromium.
4. Mises à jour :
   ```bash
   docker compose build --pull
   docker compose up -d
   ```

---

## 🔧 Commandes utiles

```bash
docker compose ps
docker compose logs -f cloudcli
docker compose exec cloudcli bash          # shell dans le conteneur
docker compose restart cloudcli
docker compose down                       # arrête (données conservées)
docker compose down -v                    # ⚠️ SUPPRIME tout
```

---

## 📂 Structure

```
multi-agents/
├── docker-compose.yml
├── Caddyfile
├── .env.example
├── install.sh
├── README.md
└── cloudcli/
    ├── Dockerfile          # Debian + Node22 + CloudCLI + Claude + Codex
    │                       # + code-server + Chromium
    ├── supervisord.conf    # lance cloudcli (:3001) et code-server (:8080)
    └── entrypoint.sh       # injecte la clé API + écrit settings.json
```

Bon code avec tes agents ! 🤖💻📱
