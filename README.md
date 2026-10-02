<div align="center">

# 🤖 VMREMOTEAGENT

**Une plateforme d'agents IA auto-hébergée — Claude Code + Codex, dans le navigateur, depuis n'importe où.**

[CloudCLI](https://github.com/siteboon/claudecodeui) · [Claude Code](https://docs.anthropic.com/en/docs/claude-code) · [Codex CLI](https://github.com/openai/codex) · [code-server](https://github.com/coder/code-server) · [Caddy](https://caddyserver.com) · [Ollama Cloud](https://ollama.com)

[![License: Propriétaire](https://img.shields.io/badge/License-Propri%C3%A9taire-red.svg)]()
[![Debian](https://img.shields.io/badge/Debian-12%2F13-red)](https://debian.org)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%2F24.04-orange)](https://ubuntu.com)
[![Docker](https://img.shields.io/badge/Docker-Compose-blue)](https://docs.docker.com/compose)
[![No GPU](https://img.shields.io/badge/GPU-none-success)](https://ollama.com)
[![Mobile](https://img.shields.io/badge/Mobile-ready-brightgreen)]()

</div>

---

## ✨ En bref

Déployez en **une commande** une plateforme complète d'agents IA sur une VM (ou votre PC), accessible depuis n'importe quel navigateur desktop ou mobile. Aucun GPU nécessaire — tout le calcul est délégué à **Ollama Cloud**.

```bash
curl -fsSL https://raw.githubusercontent.com/Tiij/VMREMOTEAGENT/main/setup.sh \
  | sudo OLLAMA_API_KEY=sk-ollama-... HOSTNAME_PUBLIQUE=<ip> bash
```

5 à 15 minutes plus tard, vous obtenez :

| URL | Service | Ce que c'est |
|---|---|---|
| `https://<ip>/` | **Dashboard** | Page d'accueil style Apple, liens directs vers tous les services |
| `https://<ip>:3001/` | **CloudCLI** | Interface web/mobile pour piloter Claude Code et Codex (chat, fichiers, git, terminal, MCP, multi-projets) |
| `https://<ip>/ide/` | **code-server** | VS Code en ligne, sur le même workspace que les agents |

Les agents **Claude Code** et **Codex CLI** (officiels) sont préinstallés, préconfigurés pour parler à Ollama Cloud, et partage le même dossier de travail que code-server. Vous pouvez commencer une mission avec Claude, éditer un fichier à la main dans VS Code, puis reprendre avec Codex — tout est synchronisé.

---

## 🎯 Cas d'usage

- 💻 **Développement à distance** — Depuis un Chromebook, un iPad, un PC d'emprunt ou un téléphone, retrouvez votre environnement de dev complet : éditeur VS Code, terminal, agents IA, vos projets Git.
- 🏖️ **Coder en déplacement** — Toutes les fonctionnalités (chat, fichiers, git, terminal) fonctionnent sur mobile. Vous pouvez lancer une build ou un refactoring depuis votre téléphone pendant que vous êtes en déplacement.
- 🤝 **Collaboration multi-agents** — Claude Code et Codex travaillent sur le même dossier. Lancez Claude pour l'architecture et Codex pour l'implémentation, ou laissez-les dialoguer.
- 🔬 **Bac à sable sécurisé** — Les agents tournent dans un conteneur Docker isolé (pas d'accès au système hôte, pas de socket Docker). Le workspace est un volume Docker dédié.
- 💾 **Snapshot avant tout** — Une commande sauvegarde tous vos projets, sessions et config ; une autre les restaure. Un cron quotidien tourne automatiquement.
- 📦 **Reproductible** — Une machine propre + une commande = toute la plateforme. Déployez chez Hetzner, OVH, DigitalOcean, AWS, Scaleway, Vultr, sur un Raspberry Pi 5, ou même en local sur macOS/WSL.
- 🎓 **Démos & formation** — Partagez un lien avec un stagiaire pour qu'il ait un accès VS Code + IA immédiat, sans rien installer sur son PC.
- 🏠 **Home-lab** — Remplacez Ollama Cloud par une instance Ollama locale (si vous avez un GPU) et tout fonctionne de la même façon, totalement offline.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  🖥️  PC / 📱 Tablette / 📱 Téléphone                                │
│     (Chrome · Firefox · Safari · Edge)                              │
└────────────┬──────────────────────────────────────────┬─────────────┘
             │ HTTPS (Caddy, cert auto-signé ou LE)     │
             ▼                                          ▼
    ┌──────────────────┐  ┌──────────────────────────────────────────┐
    │  /  → Dashboard  │  │ :3001 → CloudCLI (React/Express :3001)   │
    │  /ide/ → code-   │  │  └── UI agents: chat, fichiers, git,    │
    │    server :8080  │  │      terminal, MCP, comptes locaux      │
    │  (reverse proxy) │  └──────────────────────────────────────────┘
    └──────────────────┘                  │
             │                            │ spawn dans des PTY
             │ partage /home/agent/workspace (volume Docker)
             ▼                            ▼
    ┌─────────────────────────────────────────────────────────┐
    │  Conteneur "cloudcli" (Debian Bookworm, non-root)       │
    │  ├─ claude (Anthropic CLI)                              │
    │  ├─ codex (OpenAI CLI)                                  │
    │  ├─ code-server (VS Code web)                           │
    │  ├─ cloudcli serve (frontend/API)                       │
    │  └─ Chromium, Node 22, git, python, pip, neovim, ripgrep│
    └──────────────────────┬──────────────────────────────────┘
                           │ ANTHROPIC_BASE_URL=https://ollama.com
                           │ OPENAI_BASE_URL=https://ollama.com/v1
                           │ OLLAMA_API_KEY (la vôtre)
                           ▼
                    ┌──────────────┐
                    │ Ollama Cloud │  Aucun GPU sur la VM
                    └──────────────┘
```

### Ce qui est inclus

| Composant | Version | Rôle |
|---|---|---|
| **CloudCLI** (`@cloudcli-ai/cloudcli`) | latest | Frontend web/mobile multi-agents |
| **Claude Code CLI** (`@anthropic-ai/claude-code`) | latest | Agent Anthropic officiel |
| **Codex CLI** (`@openai/codex`) | latest | Agent OpenAI officiel |
| **code-server** | latest | VS Code dans le navigateur |
| **Caddy 2 (alpine)** | latest | Reverse proxy HTTPS + certificats |
| **Debian Bookworm** (image conteneur) | slim | Base du conteneur agents |
| **Node.js** | 22 LTS | Runtime des CLIs |
| **Chromium** | latest | Pour le MCP browser-use |
| **Modèle par défaut** | `qwen3-coder:cloud` | Via Ollama Cloud (changeable) |

---

## 🚀 Démarrage rapide (30 secondes)

### 1. Prérequis

- Une machine Linux avec **Docker** (le script d'installation l'installe automatiquement si absent) — ou macOS/Windows avec Docker Desktop.
- **2 vCPU / 4 Go RAM minimum** (8 Go recommandés si vous utilisez plusieurs agents en parallèle).
- Ports **80, 443 et 3001** ouverts si c'est une VM exposée sur Internet.
- Une **clé API Ollama Cloud** → https://ollama.com/settings/keys

### 2. Installation une commande (depuis une VM root)

```bash
curl -fsSL https://raw.githubusercontent.com/Tiij/VMREMOTEAGENT/main/setup.sh \
  | sudo OLLAMA_API_KEY=sk-ollama-votre-cle HOSTNAME_PUBLIQUE=<IP_PUBLIQUE> bash
```

La variable `HOSTNAME_PUBLIQUE` est utilisée pour afficher les URLs finales. Vous pouvez omettre `OLLAMA_API_KEY` et `HOSTNAME_PUBLIQUE` : le script vous les demandera interactivement.

> 💡 **L'installateur est intelligent et idempotent** : si vous le relancez, il détecte automatiquement l'état de l'installation (neuve, cassée, à mettre à jour, déjà saine), affiche un diagnostic en 9 points, propose un menu d'actions adapté, prend un snapshot de précaution avant toute modification, préserve votre clé API et votre secret CloudCLI, puis fait un healthcheck HTTPS en fin de course. Si quelque chose casse à n'importe quel moment, un simple `./scripts/doctor.sh --fix` diagnostique et répare automatiquement.

Vous pouvez aussi cloner le repo d'abord (si vous voulez inspecter avant) :

```bash
git clone https://github.com/Tiij/VMREMOTEAGENT.git
cd VMREMOTEAGENT
sudo ./setup.sh
```

### 3. Premier accès

1. Ouvrez `https://<IP>/` dans votre navigateur.
2. Acceptez l'avertissement de certificat auto-signé.
3. La page d'accueil "Apple-style" s'affiche. Cliquez sur **Agents CloudCLI** pour ouvrir l'UI des agents.
4. Définissez un mot de passe (compte local, stocké dans le volume Docker).
5. Créez un projet, choisissez **Claude Code** ou **Codex**, et envoyez votre première mission.
6. Cliquez sur **Éditeur IDE** dans le dashboard pour ouvrir VS Code web sur le même dossier.

> 💡 Un tutoriel complet multi-OS est disponible dans [`TUTORIEL-INSTALLATION.md`](./TUTORIEL-INSTALLATION.md), et un guide Debian pas-à-pas dans [`GUIDE-DEBIAN-VIERGE.md`](./GUIDE-DEBIAN-VIERGE.md).

---

## 🖥️ OS & environnements supportés

| OS / Distro | Version testée | Notes |
|---|---|---|
| ✅ **Debian** | 12 Bookworm, 13 Trixie | Support principal, installateur une commande |
| ✅ **Ubuntu** | 22.04 LTS, 24.04 LTS | Support principal |
| ✅ **Raspberry Pi OS** | 12 Bookworm (arm64) | Sur Pi 5 (≥4 Go), fonctionne — démarrage plus long |
| ✅ **Fedora / RHEL / Rocky / AlmaLinux** | 40 / 9 | Voir section dédiée du tutoriel (dnf) |
| ✅ **Arch Linux / Manjaro** | rolling | Voir section dédiée (pacman) |
| ⚙️ **macOS** (local/test) | Sonoma+, puce Intel ou Apple Silicon | Via Docker Desktop, `HOSTNAME_PUBLIQUE=localhost` |
| ⚙️ **Windows WSL2** | WSL2 + Ubuntu/Debian | Via Docker Desktop ou Docker dans WSL2 |
| ⚙️ **NixOS** | 24.05 | Docker + `systemd.enable = true` |

Le tutoriel [`TUTORIEL-INSTALLATION.md`](./TUTORIEL-INSTALLATION.md) détaille la procédure pour chaque OS, y compris les cloud providers (Hetzner, OVH, DigitalOcean, AWS, GCP, Azure, Vultr, Scaleway, Oracle Cloud).

### Config minimale / recommandée

| Usage | vCPU | RAM | Disque | Note |
|---|---|---|---|---|
| Découverte / petits scripts | 1 | 2 Go | 10 Go | Build initial juste, mais peut swapper |
| Usage solo (1 projet) | 2 | 4 Go | 20 Go | **Minimum recommandé** |
| Travail quotidien / multi-projets | 2–4 | 8 Go | 50 Go | Plusieurs agents en parallèle |
| Équipe (partage VM) | 4+ | 8–16 Go | 100 Go+ | Un workspace partagé ou plusieurs |

Aucun GPU n'est nécessaire : les inférences passent par Ollama Cloud. Si vous voulez utiliser un Ollama local (avec GPU), modifiez simplement les variables d'environnement `ANTHROPIC_BASE_URL` et `OPENAI_BASE_URL` dans `cloudcli/Dockerfile` pour pointer vers votre instance Ollama.

---

## 🔒 Sécurité

Chaque couche a été pensée pour qu'un agent qui dérape ne puisse pas casser la VM hôte :

| Couche | Protection |
|---|---|
| **Isolation Docker** | Tous les processus (`claude`, `codex`, `code-server`, CloudCLI, Chromium) s'exécutent dans un seul conteneur, en tant qu'utilisateur non-root `agent` (uid 1000). |
| **Socket Docker non monté** | Les agents ne peuvent pas lancer/arrêter d'autres conteneurs ni s'échapper via Docker. |
| **Pas de privilège** | Pas de `--privileged`, pas de capacités kernel étendues. |
| **Accès réseau sortant** | Les agents peuvent joindre Internet (git, npm, Ollama Cloud), mais Caddy n'expose que 80, 443 et 3001. |
| **Auth CloudCLI** | Un compte local (email + mot de passe) est obligatoire pour utiliser l'UI des agents. |
| **TLS** | Tout le trafic passe en HTTPS (cert auto-signé par défaut, Let's Encrypt avec un vrai domaine). |
| **En-têtes sécurisés** | Caddy ajoute `X-Content-Type-Options`, `X-Frame-Options SAMEORIGIN`, `Referrer-Policy`. |

### Recommandations de durcissement

1. **Mot de passe CloudCLI fort** dès la première visite.
2. **Vrai nom de domaine** (`agents.votretld.tld`) → Caddy obtient automatiquement un certificat Let's Encrypt valide (plus d'avertissement).
3. **Basic auth Caddy** (optionnel) si vous voulez une protection avant même d'arriver à CloudCLI.
4. **Pare-feu** : n'ouvrez que 80, 443 et 3001. Les autres ports (3001 interne, 8080) ne sont pas exposés hors du réseau Docker.
5. **Sauvegardes** : cron quotidien + snapshots VM côté hébergeur.

---

## 💾 Sauvegardes & restauration

Les scripts dans `scripts/` gèrent les sauvegardes automatiques et manuelles. Voir [`BACKUPS.md`](./BACKUPS.md) pour la documentation complète.

```bash
./scripts/snapshot.sh avant-refactoring     # sauvegarde manuelle
./scripts/restore.sh avant-refactoring      # restaure
./scripts/doctor.sh                         # diagnostic + réparation automatique
./scripts/doctor.sh --fix                     # diagnostic ET réparation
./scripts/status.sh                         # état rapide de la stack + backups
./scripts/factory-reset.sh                  # reset complet
```

Par défaut : sauvegarde automatique quotidienne à ~6h25 (cron.daily), 14 snapshots conservés, logs dans `/var/log/cloudcli-snapshot.log`.

---

## 📂 Structure du projet

```
VMREMOTEAGENT/
├── setup.sh                       # Installateur une commande (curl | bash)
├── install.sh                     # Script local complémentaire (Docker + .env + cron)
├── docker-compose.yml             # Définition des services (cloudcli + caddy)
├── Caddyfile                      # Reverse proxy HTTPS (dashboard :443, ide :/ide/, cloudcli :3001)
├── .env.example                   # Template de configuration
├── README.md                      # ← vous êtes ici
├── TUTORIEL-INSTALLATION.md       # Guide multi-OS complet
├── GUIDE-DEBIAN-VIERGE.md         # Quick-start Debian/Ubuntu
├── BACKUPS.md                     # Documentation sauvegardes/restauration
│
├── dashboard/
│   └── index.html                 # Dashboard Apple-style (page d'accueil)
│
├── cloudcli/
│   ├── Dockerfile                 # Build du conteneur (Debian + Node + CLIs + code-server)
│   ├── entrypoint.sh              # Injecte la clé API au démarrage
│   └── supervisord.conf           # Lance cloudcli et code-server
│
└── scripts/
    ├── snapshot.sh                # Sauvegarde manuelle
    ├── restore.sh                 # Restauration
    ├── auto-snapshot.sh           # Cron quotidien
    ├── factory-reset.sh           # Reset complet
    ├── doctor.sh                  # Diagnostic & auto-réparation
    └── status.sh                  # Diagnostic rapide
```

---

## 🛠️ Commandes utiles

Toutes les commandes ci-dessous sont à lancer depuis le dossier d'installation (`/opt/multi-agents` par défaut) :

```bash
# État et logs
./scripts/doctor.sh                           # diagnostic + réparation
./scripts/doctor.sh --fix                     # diagnostic + réparation auto
./scripts/status.sh                           # tableau de bord + backups
docker compose ps                       # conteneurs Up/Stopped
docker compose logs -f cloudcli         # logs agents en direct
docker compose logs -f caddy            # logs reverse proxy

# Cycle de vie
docker compose restart                  # redémarre tout
docker compose stop                     # arrête (données conservées)
docker compose up -d                    # redémarre après un stop
docker compose down                     # arrête et supprime les conteneurs (données conservées dans les volumes)
docker compose down -v                  # ⚠️ SUPPRIME TOUTES LES DONNÉES

# Mise à jour
docker compose build --pull && docker compose up -d

# Shell dans le conteneur agents
docker compose exec cloudcli bash       # en root du conteneur
docker compose exec -u agent cloudcli bash    # en user agent

# Changer de clé API Ollama
nano .env                               # modifier OLLAMA_API_KEY
docker compose up -d                    # redémarrer pour prendre en compte
```

### Changer de modèle LLM

Par défaut : `qwen3-coder:cloud` (excellent pour le code). Vous pouvez utiliser n'importe quel modèle disponible sur [ollama.com/search](https://ollama.com/search) (filtre *Cloud*) :

- **Claude Code** (dans une session) : tapez `/model <nom-du-modele:cloud>`.
- **Codex** : `codex -m <nom-du-modele>` dans le terminal, ou via le sélecteur CloudCLI.
- **Défaut permanent** : modifiez `qwen3-coder:cloud` dans `cloudcli/Dockerfile` puis `docker compose build cloudcli && docker compose up -d`.

Modèles cloud populaires : `deepseek-v3.1:671b`, `llama-4-scout:cloud`, `glm-5:cloud`, `qwen3-coder:cloud`, `mistral-large:cloud`.

### Utiliser un vrai nom de domaine + Let's Encrypt

1. Créez un enregistrement DNS A qui pointe vers l'IP de votre VM.
2. Remplacez dans `Caddyfile` les lignes `https://:443 {` par `agents.votretld.tld {` et `https://:3001 {` par `agents.votretld.tld:3001 {`.
3. Supprimez les deux lignes `tls internal`.
4. Redémarrez : `docker compose restart caddy`.
5. Au bout de 10-30 secondes, le cadenas vert s'affiche.

---

## 🆘 Dépannage

| Symptôme | Cause | Solution |
|---|---|---|
| `ERR_CONNECTION_REFUSED` | Les conteneurs ne tournent pas | `docker compose ps`, puis `docker compose logs cloudcli` |
| **502 Bad Gateway** | CloudCLI est en train de booter | Attendez 30-60s, rafraîchissez |
| **Certificat rouge/orange** | Normal en IP brute (auto-signé) | Acceptez l'avertissement, ou utilisez un domaine |
| Agents en **"Auth error" / 401** | `OLLAMA_API_KEY` invalide | Vérifiez `.env`, puis `docker compose up -d` |
| `claude` dit qu'il n'a pas de clé | Variables non chargées dans le shell | Ouvrez un nouveau shell ou `source ~/.bashrc` dans le conteneur |
| Build **échoue en mémoire** (OOM) | RAM insuffisante | Minimum 4 Go ; vérifiez avec `free -h`, ajoutez du swap ou une instance plus grande |
| **Je ne peux pas me connecter** | Ports fermés | Vérifiez votre security-group/pare-feu : 80, 443, 3001 |
| WebSockets **coupés** (code-server) | Header Upgrade manquant | Vérifiez le `Caddyfile` (lignes `header_up Upgrade/Connection` déjà présentes) |
| Mot de passe CloudCLI oublié | — | `docker volume rm $(basename $(pwd))_cloudcli-data && docker compose up -d` (reset du compte) |
| J'ai cassé quelque chose | — | `./scripts/restore.sh <nom-d-un-snap>` |

---

## 📜 Licence

© Tiij — **Tous droits réservés / All rights reserved.**

Ce projet est **propriétaire**. Le code source est mis à disposition
pour votre **usage personnel et interne uniquement** : vous pouvez
l'installer, le modifier pour vos propres besoins, et le déployer sur
vos machines.

Vous **ne pouvez pas** redistribuer, revendre, publier des forks
publics, ou intégrer ce projet (en tout ou partie) dans un produit
commercial sans autorisation écrite préalable.

Les composants tiers intégrés dans l'image Docker restent soumis à
leurs propres licences :
[CloudCLI (AGPL-3.0)](https://github.com/siteboon/claudecodeui),
[Claude Code (propriétaire)](https://anthropic.com),
[Codex CLI (Apache-2.0)](https://github.com/openai/codex),
[code-server (MIT)](https://github.com/coder/code-server),
[Caddy (Apache-2.0)](https://github.com/caddyserver/caddy).

Voir le fichier [`LICENSE`](./LICENSE) pour le texte complet.

---

<div align="center">

**Bonnes missions avec vos agents !** 🤖💻📱

[Créer une clé Ollama Cloud](https://ollama.com/settings/keys) · [Signaler un bug](https://github.com/Tiij/VMREMOTEAGENT/issues) · [CloudCLI sur GitHub](https://github.com/siteboon/claudecodeui)

</div>
