# 📘 Tutoriel complet : installer VMREMOTEAGENT

## Sur n'importe quel OS, n'importe quel hébergeur, en local ou dans le cloud

> **Durée estimée : 15-30 minutes** (dont 5-15 min de build Docker).
> Aucun GPU requis — toutes les inférences passent par **Ollama Cloud**.
> Aucun prérequis technique si vous copiez-collez les commandes.

---

## 📑 Table des matières

1. [Cas d'usage : est-ce fait pour vous ?](#-1-cas-dusage)
2. [Choisir où héberger](#-2-choisir-où-héberger)
3. [Obtenir une clé Ollama Cloud](#-3-créer-votre-clé-ollama-cloud)
4. [Installation par OS](#-4-installation-par-os)
   - 4.1 [Debian 12 / 13 (Bare metal, VM, Raspberry Pi)](#41--debian-12--13)
   - 4.2 [Ubuntu 22.04 / 24.04](#42--ubuntu-2204--2404)
   - 4.3 [Fedora / RHEL 9 / Rocky 9 / AlmaLinux 9](#43--fedora--rhel--rocky--almalinux)
   - 4.4 [Arch Linux / Manjaro](#44--arch-linux--manjaro)
   - 4.5 [macOS (local avec Docker Desktop)](#45--macos)
   - 4.6 [Windows WSL2](#46--windows-wsl2)
   - 4.7 [NixOS](#47--nixos)
   - 4.8 [Sur un cloud provider spécifique](#48--cloud-providers)
5. [Premier accès](#-5-premier-accès)
6. [Accès mobile](#-6-accès-depuis-le-téléphone)
7. [Usage quotidien](#-7-usage-quotidien)
8. [Dépannage](#-8-dépannage)

---

## 🎯 1. Cas d'usage

VMREMOTEAGENT est fait pour vous si vous voulez…

| Cas | Pourquoi VMREMOTEAGENT |
|---|---|
| 💻 **Coder depuis n'importe où** | VS Code web + terminal + agents, dans le navigateur, sans rien installer sur le PC de prêt, le Chromebook ou l'iPad. |
| 📱 **Coder sur téléphone** | CloudCLI a une interface responsive qui fonctionne sur téléphone/tablette — vous pouvez lancer des missions en déplacement. |
| 🤝 **Multi-agents** | Claude Code **et** Codex CLI préinstallés, préconfigurés, sur le même workspace. |
| 🔬 **Bac à sable** | Les agents tournent en conteneur Docker non-root. Ils ne peuvent pas casser l'hôte. |
| 💾 **"Time machine" du dev** | Snapshots automatiques + restauration une commande avant/après chaque mission risquée. |
| 🎓 **Démos & formations** | Partagez un lien avec un stagiaire pour qu'il ait un accès dev+IA immédiat. |
| 🏠 **Home-lab** | Remplacez Ollama Cloud par un Ollama local (GPU) pour tout faire offline. |

Vous **n'avez pas besoin** de VMREMOTEAGENT si vous voulez simplement utiliser Claude Code en local sur votre Mac/PC — installez-le directement, c'est plus simple.

---

## 🌐 2. Choisir où héberger

### Cloud (VM louée) — le plus courant

| Fournisseur | Offre minimum | Prix indicatif (2025) | Notes |
|---|---|---|---|
| [Hetzner](https://www.hetzner.com/cloud/) | CX22 (2 vCPU / 4 Go) | ~4 €/mois | 🇩🇪, excellent rapport qualité/prix |
| [OVH](https://www.ovhcloud.com/fr/vps/) | VPS Starter (1 vCPU / 2 Go) | ~3,5 €/mois | 🇫🇷 |
| [DigitalOcean](https://www.digitalocean.com/pricing/droplets) | Basic 2 Go / 1 vCPU AMD | ~6 $/mois | Global |
| [Vultr](https://www.vultr.com/pricing/) | Regular Cloud 2 Go | ~5 $/mois | Beaucoup de régions |
| [Scaleway](https://www.scaleway.com/fr/vps/) | DEV1-S (2 vCPU / 2 Go) | ~5 €/mois | 🇫🇷 |
| [AWS EC2](https://aws.amazon.com/fr/ec2/pricing/) | t3.small (2 vCPU / 2 Go) | ~15 $/mois | Plus cher mais universel |
| [GCP Compute Engine](https://cloud.google.com/compute) | e2-small (2 vCPU / 2 Go) | ~12 $/mois | Idem |
| [Azure](https://azure.microsoft.com/fr-fr/pricing/details/virtual-machines/linux/) | B1s (1 vCPU / 1 Go) | ~8 $/mois | B1s trop juste → B2ms (8 Go) |
| [Oracle Cloud](https://www.oracle.com/fr/cloud/free/) | Ampere A1 (4 vCPU / 24 Go) | **Gratuit** (Free Tier) | Free tier généreux mais l'inscription est parfois capricieuse |

**Pour commencer :** Hetzner CX22 ou DigitalOcean Basic 4 Go sont des valeurs sûres. Choisissez **Debian 12** ou **Ubuntu 24.04** comme image d'OS.

### Sur site / home-lab

- Un mini-PC avec Debian/Ubuntu (Intel NUC, Beelink, etc.), 8 Go+ RAM.
- Un Raspberry Pi 5 (4 Go/8 Go) sous Raspberry Pi OS (64-bit, Bookworm) — plus lent mais fonctionnel.
- Un serveur qui tourne déjà sous Proxmox, TrueNAS ou un autre hyperviseur.

### En local (pour tester)

- macOS avec Docker Desktop.
- Windows 10/11 avec WSL2 + Docker Desktop.
- Une machine Linux quelconque.

> ⚠️ En local, le certificat HTTPS auto-signé génèrera un avertissement — c'est normal. Utilisez `HOSTNAME_PUBLIQUE=localhost`.

---

## 🔑 3. Créer votre clé Ollama Cloud

Les modèles LLM tournent sur Ollama Cloud ; vous avez besoin d'une clé API :

1. Ouvrez https://ollama.com/settings/keys
2. Connectez-vous / créez un compte.
3. Cliquez **"Create API key"**, donnez-lui un nom (ex: `vm-agents`).
4. **Copiez la clé** qui commence par `sk-ollama-...` — elle ne sera affichée qu'une fois.

> 💡 Ollama Cloud offre un crédit gratuit pour commencer. Au-delà, c'est du paiement à l'usage (quelques cents par modèle selon la taille).

---

## 🚀 4. Installation par OS

Dans tous les cas, connectez-vous d'abord à votre machine en SSH (pour les VMs) ou ouvrez un terminal (en local).

---

### 4.1 🐧 Debian 12 / 13

Cible principale. Testé sur Debian 12 Bookworm (amd64 et arm64).

```bash
# Passez root
sudo -i

# Mettez le système à jour
apt update && apt upgrade -y
apt install -y ca-certificates curl sudo

# Une commande pour tout installer
curl -fsSL https://raw.githubusercontent.com/Tiij/VMREMOTEAGENT/main/setup.sh \
  | OLLAMA_API_KEY=sk-ollama-VOTRE-CLE HOSTNAME_PUBLIQUE=VOTRE.IP bash
```

Si vous ne voulez pas mettre la clé dans la commande, ne mettez pas les variables : le script vous demandera interactivement la clé et détectera l'IP publique automatiquement (ou vous proposera une IP) :

```bash
curl -fsSL https://raw.githubusercontent.com/Tiij/VMREMOTEAGENT/main/setup.sh | sudo bash
```

Le script :
1. Installe Docker + Docker Compose si absents,
2. Crée `/opt/multi-agents/` et y écrit tous les fichiers (dashboard, Caddyfile, docker-compose.yml, image cloudcli, scripts de backup),
3. Génère un secret aléatoire pour le compte CloudCLI,
4. Configure le cron de sauvegarde quotidien,
5. Build l'image Docker et démarre la stack.

Passez directement à [l'étape 5](#-5-premier-accès).

> 📄 Un guide spécifique Debian pas à pas (captures d'écran mentales) existe dans [`GUIDE-DEBIAN-VIERGE.md`](./GUIDE-DEBIAN-VIERGE.md).

---

### 4.2 🟠 Ubuntu 22.04 / 24.04

Identique à Debian, à une différence près : si vous avez activé `ufw` (pare-feu par défaut sur Ubuntu Server), ouvrez les ports avant :

```bash
sudo -i
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 3001/tcp
ufw status
```

Puis lancez l'installateur :

```bash
curl -fsSL https://raw.githubusercontent.com/Tiij/VMREMOTEAGENT/main/setup.sh \
  | OLLAMA_API_KEY=sk-ollama-VOTRE-CLE HOSTNAME_PUBLIQUE=VOTRE.IP bash
```

> ℹ️ Le script détecte automatiquement Ubuntu via `/etc/os-release` et configure le bon dépôt Docker.

---

### 4.3 🎩 Fedora / RHEL 9 / Rocky 9 / AlmaLinux 9

Ces distributions utilisent `dnf` et `firewalld` au lieu d'`apt`/`ufw`. L'installateur automatique (`setup.sh`) est écrit pour Debian/Ubuntu ; sur les familles RHEL, quelques étapes manuelles sont nécessaires.

```bash
# Devenir root
sudo -i

# Mise à jour
dnf update -y

# Installer Docker (dépôt officiel)
dnf -y install dnf-plugins-core
dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
# Pour RHEL/Rocky/Alma, remplacez "fedora" par "centos" dans l'URL :
# dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin git cronie curl
systemctl enable --now docker

# Ouvrir les ports (firewalld par défaut sur Fedora/RHEL)
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --permanent --add-port=443/tcp
firewall-cmd --permanent --add-port=3001/tcp
firewall-cmd --reload

# Cloner le repo
mkdir -p /opt && cd /opt
git clone https://github.com/Tiij/VMREMOTEAGENT.git multi-agents
cd multi-agents

# Installer la stack SANS la partie apt (lancée en tant que script local)
OLLAMA_API_KEY=sk-ollama-VOTRE-CLE HOSTNAME_PUBLIQUE=VOTRE.IP NO_APT=1 bash setup.sh
```

> 💡 Si `setup.sh` échoue sur la partie `apt`, copiez les fichiers du repo dans `/opt/multi-agents/` puis utilisez `./install.sh` suivi de `docker compose up -d --build`.

---

### 4.4 💠 Arch Linux / Manjaro

Sur Arch, Docker est dans les dépôts officiels :

```bash
sudo -i
pacman -Syu --noconfirm
pacman -S --noconfirm docker docker-buildx docker-compose git cronie curl sudo
systemctl enable --now docker
systemctl enable --now cronie

# Ouvrir les ports (si ufw ou firewalld est installé ; sinon rien à faire
# car par défaut Arch n'a pas de firewall actif)
which ufw && ufw allow 80/tcp && ufw allow 443/tcp && ufw allow 3001/tcp || true

# Cloner et installer
mkdir -p /opt && cd /opt
git clone https://github.com/Tiij/VMREMOTEAGENT.git multi-agents
cd multi-agents
OLLAMA_API_KEY=sk-ollama-VOTRE-CLE HOSTNAME_PUBLIQUE=VOTRE.IP bash setup.sh
```

Si `setup.sh` bloque sur la partie apt (car Arch n'a pas `apt-get`), ajoutez `NO_APT=1` devant la commande :

```bash
NO_APT=1 OLLAMA_API_KEY=sk-ollama-VOTRE-CLE HOSTNAME_PUBLIQUE=VOTRE.IP bash setup.sh
```

---

### 4.5 🍎 macOS

Utilisez [Docker Desktop pour Mac](https://www.docker.com/products/docker-desktop/) (puce Intel ou Apple Silicon). Aucun déploiement distant ici : la stack tourne en local, utile pour tester ou pour avoir une interface web sympa à vos agents.

1. **Installer Docker Desktop** : https://www.docker.com/products/docker-desktop/
2. Ouvrez Docker Desktop et attendez qu'il dise "Engine running".
3. Ouvrez Terminal.app et lancez :

```bash
# Installer les outils en ligne de commande (si pas déjà présents)
xcode-select --install 2>/dev/null || true

# Cloner le repo
git clone https://github.com/Tiij/VMREMOTEAGENT.git
cd VMREMOTEAGENT
```

4. Comme `setup.sh` suppose un Linux (avec apt/systemd), il faut lancer les étapes à la main :

```bash
mkdir -p /tmp/ma-demo && cd /tmp/ma-demo
cp -r ~/VMREMOTEAGENT/{docker-compose.yml,Caddyfile,.env.example,dashboard,cloudcli,scripts} .
cp .env.example .env

# Éditez .env pour mettre votre clé Ollama et l'URL locale
sed -i '' 's|sk-ollama-votre-cle-ici|sk-ollama-VOTRE-CLE|' .env
sed -i '' 's|https://localhost|https://localhost|' .env   # garder localhost

# Générer une clé secrétaire aléatoire
SECRET=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 64)
sed -i '' "s|^WEBUI_SECRET_KEY=.*|WEBUI_SECRET_KEY=${SECRET}|" .env

# Lancer la stack
docker compose up -d --build
```

⚠️ Sur Mac, le port 443 peut être occupé par d'autres services (AirPlay, partages web). Vous pouvez changer le port dans `docker-compose.yml` (ex: `"8443:443"`) ou arrêter les services qui l'utilisent.

Accès :
- `https://localhost:8443/` si vous avez changé le port, sinon `https://localhost/` (acceptez l'avertissement).
- `https://localhost:3001/` pour CloudCLI directement.

> ⚠️ Le DNS `host.docker.internal` fonctionne sur Mac pour pointer vers l'hôte depuis le conteneur — utile si vous faites tourner Ollama en local sur le Mac hors Docker.

---

### 4.6 🪟 Windows WSL2

Plusieurs options :

**Option A — Docker Desktop avec WSL2 backend (recommandé)**
1. Installez [WSL2](https://learn.microsoft.com/fr-fr/windows/wsl/install) (PowerShell admin : `wsl --install`).
2. Installez [Docker Desktop](https://www.docker.com/products/docker-desktop/) et activez le backend WSL2 (Settings → Resources → WSL Integration).
3. Ouvrez un terminal **Ubuntu** depuis le menu Démarrer, puis suivez les étapes [Ubuntu 22.04/24.04](#42--ubuntu-2204--2404) (les commandes sont les mêmes dans WSL2).

```bash
# Dans la distro WSL Ubuntu
sudo apt update && sudo apt install -y ca-certificates curl git
git clone https://github.com/Tiij/VMREMOTEAGENT.git
cd VMREMOTEAGENT
sudo OLLAMA_API_KEY=sk-ollama-... HOSTNAME_PUBLIQUE=localhost bash setup.sh
```

Accès depuis le navigateur Windows : `https://localhost/` (acceptez l'avertissement).

**Option B — Docker dans WSL2 sans Docker Desktop**
C'est possible mais plus technique (utilisez la méthode [Ubuntu classique](#42--ubuntu-2204--2404) directement dans WSL2). Docker Desktop reste le plus simple.

---

### 4.7 ❄️ NixOS

Sur NixOS, activez Docker dans votre `configuration.nix` :

```nix
virtualisation.docker = {
  enable = true;
  enableRootless = false;  # ou true si vous préférez
};
```

Puis rebuild et installez :

```bash
sudo nixos-rebuild switch

# Vous avez besoin de git et cron
nix-shell -p git cronie curl

# Pare-feu (si activé)
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT || true
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT || true
sudo iptables -A INPUT -p tcp --dport 3001 -j ACCEPT || true

# Cloner et lancer (NO_APT car NixOS n'a pas apt)
git clone https://github.com/Tiij/VMREMOTEAGENT.git
cd VMREMOTEAGENT
sudo NO_APT=1 OLLAMA_API_KEY=sk-ollama-... HOSTNAME_PUBLIQUE=VOTRE.IP bash setup.sh
```

Si `setup.sh` a des problèmes avec le cron systemd, activez le service `cron` :
```nix
services.cron.enable = true;
```

---

### 4.8 ☁️ Cloud providers

Si vous choisissez un provider cloud, deux points d'attention :

#### Ouvrir les ports dans le pare-feu externe

Presque tous les clouds ont un pare-feu **hors de la VM** (Security Group sur AWS/OpenStack, Firewall chez Hetzner/OVH/DigitalOcean). **Les commandes `ufw` dans la VM ne suffisent pas** — il faut aussi ouvrir les ports dans le panel web du fournisseur.

Ports à ouvrir en **entrée** (inbound), depuis votre IP ou `0.0.0.0/0` :
- `80/tcp` (HTTP → redirigé vers HTTPS)
- `443/tcp` (HTTPS dashboard + code-server)
- `3001/tcp` (HTTPS CloudCLI agents)

Sur Oracle Cloud (Free Tier), le pare-feu par défaut est **extrêmement** restrictif : ajoutez explicitement les 3 ports dans le Security List ET dans `iptables` de la VM :

```bash
sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 3001 -j ACCEPT
sudo netfilter-persistent save 2>/dev/null || true
```

#### Clés SSH sur les providers

- **Hetzner, DigitalOcean, Vultr, Scaleway** : clé SSH préconfigurée, connexion directe en root avec `ssh root@<IP>`.
- **AWS EC2 / Lightsail** : utilisateur `ubuntu` (Ubuntu) ou `ec2-user` (Amazon Linux 2) — passez root avec `sudo -i` après connexion.
- **GCP** : utilisateur au nom de votre compte, puis `sudo -i`.
- **Azure** : utilisateur `azureuser` ou celui que vous avez choisi à la création, puis `sudo -i`.
- **Oracle Cloud** : utilisateur `ubuntu` ou `opc`, puis `sudo -i`.
- **OVH Public Cloud** : `ubuntu@<IP>` ou `debian@<IP>`, puis `sudo -i`.

#### Une fois la VM créée et les ports ouverts

Lancez simplement :

```bash
curl -fsSL https://raw.githubusercontent.com/Tiij/VMREMOTEAGENT/main/setup.sh \
  | sudo OLLAMA_API_KEY=sk-ollama-VOTRE-CLE HOSTNAME_PUBLIQUE=VOTRE.IP bash
```

Le script détecte l'OS et la plupart des providers automatiquement.

---

## 🔓 5. Premier accès

### 5.1 Attendre la fin du build

Le premier `docker compose up -d --build` télécharge et construit l'image cloudcli (Debian + Node 22 + Chromium + Claude Code + Codex + CloudCLI + code-server). Ça dure **5 à 15 minutes** selon la connexion et la puissance de la VM.

Vous pouvez suivre les logs :

```bash
cd /opt/multi-agents
docker compose logs -f cloudcli
```

Quand vous voyez ces deux lignes, c'est prêt :
```
cloudcli  | CloudCLI running on http://0.0.0.0:3001
cloudcli  | web server available on http://0.0.0.0:8080
```

Appuyez sur **Ctrl+C** pour quitter les logs (les conteneurs continuent de tourner).

Vérifiez l'état :
```bash
./scripts/status.sh
```

Vous devez voir les conteneurs `caddy` et `cloudcli` en `Up`.

### 5.2 Ouvrir le dashboard

Ouvrez votre navigateur (Chrome, Firefox, Safari, Edge) et allez sur :

```
https://<IP_PUBLIQUE>/
```

⚠️ **Alerte de certificat "non sécurisé"** : c'est normal en IP brute (certificat auto-signé Caddy). Pour passer :
- **Chrome/Edge** : Avancé → Continuer vers \<IP\>
- **Firefox** : Avancé… → Accepter le risque et continuer
- **Safari** : Afficher les détails → visiter ce site web

Vous devriez voir le **dashboard Apple-style** avec les 6 cartes :
- 🧠 Agents CloudCLI → port 3001
- 💻 Éditeur IDE → `/ide/`
- 🔑 Clé Ollama Cloud → lien externe
- 💾 Sauvegarder → rappel commande snapshot
- 📊 État → rappel commande status
- 📘 Documentation → README du projet

### 5.3 Configurer CloudCLI

1. Cliquez sur **Agents CloudCLI** (ou ouvrez `https://<IP>:3001/` directement).
2. CloudCLI vous demande de créer un **compte local** (email + mot de passe). C'est le mot de passe qui protège l'accès aux agents — choisissez-le **fort**.
3. Créez un projet ou ouvrez le projet par défaut.
4. Sélectionnez **Claude Code** ou **Codex** comme agent.
5. Envoyez une première mission test, par exemple :

> Crée un fichier `hello.html` contenant une page HTML "Bonjour depuis mes agents !"
> avec un peu de style, puis liste le dossier et ouvre le fichier dans le navigateur
> via `python3 -m http.server 8000` et `curl localhost:8000`.

Vous devriez voir l'agent réfléchir, créer le fichier, lancer les commandes, en temps réel.

### 5.4 Ouvrir code-server (VS Code web)

Retour au dashboard → cliquez sur **Éditeur IDE** (ou `https://<IP>/ide/`). Vous arrivez sur VS Code, ouvert sur `/home/agent/workspace` — le **même dossier** que celui des agents. Vous pouvez :

- éditer les fichiers à la main en parallèle,
- ouvrir le terminal intégré (`` Ctrl+` ``) où `claude`, `codex`, `git`, `node`, `python` sont préinstallés et préconfigurés avec votre clé Ollama,
- installer des extensions depuis le marketplace Open-VSX.

---

## 📱 6. Accès depuis le téléphone

1. Ouvrez `https://<IP>/` dans **Chrome** (Android) ou **Safari** (iPhone).
2. Acceptez l'avertissement de certificat (même manip que sur PC).
3. Connectez-vous.
4. Optionnel — ajoutez la page à l'écran d'accueil :
   - **Android/Chrome** : menu ⋮ → Ajouter à l'écran d'accueil
   - **iOS/Safari** : bouton partager □ → Sur l'écran d'accueil

La page s'ouvre ensuite comme une PWA (icône d'app, sans barre d'URL). CloudCLI est conçu pour être utilisé sur mobile/tablette : vous pouvez envoyer des missions, suivre les progrès, lire les diffs git, et même utiliser le terminal virtuel.

> 💡 Pour éviter l'avertissement de certificat sur téléphone (pénible sur iOS), utilisez un vrai nom de domaine (voir la section dédiée dans le README).

---

## 🛠️ 7. Usage quotidien

| Ce que vous voulez faire | Comment |
|---|---|
| Lancer une mission Claude Code | Dashboard → Agents CloudCLI → Nouveau projet → Claude Code |
| Lancer une mission Codex | Dashboard → Agents CloudCLI → Nouveau projet → Codex |
| Éditer du code en direct | Dashboard → Éditeur IDE (code-server) |
| Snapshot avant une mission risquée | `cd /opt/multi-agents && ./scripts/snapshot.sh <nom>` |
| Restaurer un snapshot | `./scripts/restore.sh <nom>` |
| Voir l'état de la stack | `./scripts/status.sh` |
| Voir les logs en direct | `docker compose logs -f cloudcli` |
| Changer le modèle LLM | Dans Claude : `/model <modele>:cloud` ; dans Codex : `codex -m <modele>` |
| Mettre à jour | `docker compose build --pull && docker compose up -d` |
| Arrêter | `docker compose stop` |
| Tout réinitialiser | `./scripts/factory-reset.sh` |
| Ouvrir un shell dans le conteneur | `docker compose exec -u agent cloudcli bash` |

---

## 🆘 8. Dépannage

| Symptôme | Solution |
|---|---|
| `ERR_CONNECTION_REFUSED` | `docker compose ps` → si aucun conteneur Up, relancez avec `docker compose up -d --build`. |
| **502 Bad Gateway** | Attendez 30-60 secondes (premier boot), ou regardez `docker compose logs cloudcli`. |
| **Certificat rouge** | Normal en IP brute. Acceptez l'avertissement une fois, ou mettez en place un domaine. |
| Agents en **"Auth error" / 401** | Clé Ollama incorrecte. Vérifiez `.env`, relancez `docker compose up -d`. |
| **Build OOM** (mémoire) | La VM manque de RAM. Minimum 4 Go ; ajoutez du swap : `fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile`. |
| **Connexion impossible** | Vérifiez le security-group/pare-feu de l'hébergeur, pas seulement `ufw`. Testez depuis votre PC : `curl -I http://<IP>` (ne doit pas timeout). |
| **Je ne peux pas me connecter en SSH** | Vos clés SSH sont mal configurées ; utilisez la console web/serial du fournisseur. |
| **code-server affiche "Service Unavailable"** | Le processus code-server n'a pas fini de démarrer ; attendez et rafraîchissez. |
| **J'ai cassé quelque chose** | `./scripts/restore.sh <nom-du-snap>` pour revenir en arrière. |
| **Mot de passe CloudCLI perdu** | `docker volume rm $(basename $(pwd))_cloudcli-data && docker compose up -d` (recrée un compte vide). |
| **Les snapshots cron ne se font pas** | Vérifiez que cron tourne : `systemctl status cron`. Vérifiez le log : `tail /var/log/cloudcli-snapshot.log`. |

### Obtenir de l'aide

Si rien ne résout le problème, créez une [issue sur GitHub](https://github.com/Tiij/VMREMOTEAGENT/issues) en joignant :
- L'OS et la version
- Le provider cloud si applicable
- La sortie de `./scripts/status.sh`
- Les 50 dernières lignes de `docker compose logs cloudcli`
- Ce que vous avez essayé

---

Bonnes missions avec vos agents ! 🤖💻📱
