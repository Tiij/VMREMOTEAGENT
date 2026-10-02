# 🆕 Guide : installer la stack depuis une VM Debian VIERGE
## (Debian 12 Bookworm, sans rien d'installé)

> Durée estimée : **20-30 minutes**.
> Aucune connaissance requise : tu copies-colle les commandes.

---

## 📋 Ce dont tu as besoin avant de commencer

1. Une VM **Debian 12 Bookworm** (achetée chez Hetzner, OVH, DigitalOcean,
   Vultr, Scaleway, ou même une VM locale sous Proxmox/VirtualBox).
2. Un accès **SSH en tant que root** (ce qui est le cas la plupart du temps
   sur une VM fraîchement créée).
3. Les **ports 80 et 443 ouverts** dans le pare-feu de l'hébergeur
   ("Security Group", "Firewall", "Pare-feu" selon le provider).
4. Une **clé API Ollama Cloud** :
   - Va sur https://ollama.com/settings/keys
   - Crée un compte / connecte-toi
   - Clique **"Create API key"**, donne-lui un nom (ex: `ma-vm-agents`)
   - Copie la clé qui commence par `sk-ollama-...`

---

## 🚀 Étape 1 — Se connecter en SSH à la VM

Depuis ton PC (Windows : PowerShell/WSL ; macOS/Linux : Terminal) :

```bash
ssh root@<IP_PUBLIQUE_DE_TA_VM>
```

Si ton hébergeur t'a donné un utilisateur non-root (par exemple `debian`
ou `ubuntu`), connecte-toi avec lui puis passe root :
```bash
ssh debian@<IP_PUBLIQUE_DE_TA_VM>
sudo -i
```

> 💡 Vérifie que tu es bien root :
> ```bash
> whoami
> ```
> Ça doit afficher `root`.

---

## 🚀 Étape 2 — Mettre Debian à jour

```bash
apt update && apt upgrade -y
apt install -y ca-certificates curl git wget sudo nano
```

---

## 🚀 Étape 3 — Installer Docker (officiel)

```bash
# Ajout de la clé GPG officielle de Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Ajout du dépôt Docker
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian bookworm stable" \
  > /etc/apt/sources.list.d/docker.list

# Installation
apt update
apt install -y docker-ce docker-ce-cli containerd.io \
               docker-buildx-plugin docker-compose-plugin

# Activation au démarrage
systemctl enable --now docker
```

Vérifie que Docker fonctionne :
```bash
docker --version
docker run --rm hello-world
```

Si tu vois le message de bienvenue de Docker, c'est gagné.

---

## 🚀 Étape 4 — Ouvrir les ports dans le pare-feu (si ufw est activé)

Sur une Debian nue, `ufw` n'est généralement pas installé par défaut,
mais si c'est le cas :

```bash
which ufw && ufw allow 80/tcp && ufw allow 443/tcp || echo "ufw non installé, on passe"
```

⚠️ **Sur le cloud (Hetzner, OVH, DigitalOcean, AWS…), il faut
impérativement ouvrir les ports 80 et 443 DANS LE PANNEAU DE
L'HÉBERGEUR**, pas seulement dans la VM. Cherche "Firewall" ou
"Security Groups" dans leur interface web.

Pour tester qu'ils sont ouverts depuis ton PC :
```bash
# (depuis ton PC, pas la VM)
curl -I http://<IP_DE_LA_VM>
```
Tu obtiendras une erreur "Connexion refusée" pour l'instant
(Caddy n'est pas encore démarré), mais pas de "timeout" : si ça
timeout, les ports ne sont pas ouverts.

---

## 🚀 Étape 5 — Récupérer le code

### Option A — Cloner depuis le repo GitHub (quand il sera pushé)
```bash
mkdir -p /opt
cd /opt
git clone https://github.com/Tiij/VMREMOTEAGENT.git multi-agents
cd multi-agents
```

### Option B — Créer les fichiers à la main (si tu n'as pas encore pushé)
Suis la section de droite dans le **TUTORIEL-INSTALLATION.md**, ou copie
les 7 fichiers nécessaires par SCP depuis ton PC :
```bash
# Depuis ton PC (PowerShell ou Terminal) :
scp -r /chemin/vers/multi-agents root@<IP_DE_LA_VM>:/opt/
```

Dans tous les cas, termine avec :
```bash
cd /opt/multi-agents
ls
```

Tu dois voir `docker-compose.yml`, `Caddyfile`, `.env.example`,
`install.sh`, `cloudcli/`, `scripts/`, etc.

---

## 🚀 Étape 6 — Lancer l'installation

Le script `install.sh` va :
- vérifier Docker,
- créer le fichier `.env`,
- générer une clé secrète aléatoire,
- installer cron pour les sauvegardes automatiques quotidiennes.

```bash
chmod +x install.sh
./install.sh
```

---

## 🚀 Étape 7 — Configurer ta clé API Ollama Cloud

Édite le fichier `.env` :
```bash
nano .env
```

Remplace uniquement la ligne `OLLAMA_API_KEY=...` par ta vraie clé,
et mets l'**IP publique** de ta VM dans `WEBUI_URL` :

```ini
OLLAMA_API_KEY=sk-ollama-abc123-ta-vraie-cle-ici
WEBUI_URL=https://203.0.113.42
ENABLE_SIGNUP=true
WEBUI_SECRET_KEY=...      # déjà généré par install.sh, ne pas toucher
```

Pour enregistrer dans nano :
- **Ctrl+O** → **Entrée** (enregistre)
- **Ctrl+X** (quitte)

---

## 🚀 Étape 8 — Démarrer la stack

```bash
docker compose up -d --build
```

⚠️ Le **premier build** dure 5 à 15 minutes : il télécharge Debian,
Node.js 22, Chromium, CloudCLI, Claude Code, Codex, code-server…
Patiente. Tu peux suivre les logs en temps réel avec :
```bash
docker compose logs -f cloudcli
```

Quand tu vois des lignes comme :
```
cloudcli  | CloudCLI running on http://0.0.0.0:3001
cloudcli  | web server available on http://0.0.0.0:8080
```
c'est prêt. Appuie sur **Ctrl+C** pour quitter les logs.

Vérifie que les deux conteneurs tournent bien :
```bash
docker compose ps
```

Tu dois voir **`cloudcli`** et **`caddy`** en état **`Up`**.

---

## 🚀 Étape 9 — Premier accès depuis ton PC

Ouvre ton navigateur (Chrome/Firefox/Safari/Edge) et va sur :
```
https://<IP_PUBLIQUE_DE_TA_VM>/
```

### ⚠️ Alerte de certificat "non sécurisé"
C'est **normal** : comme tu n'as pas de nom de domaine, Caddy utilise
un certificat auto-signé. Pour passer l'avertissement :
- **Chrome/Edge** : clique **"Avancé"** → **"Continuer vers <IP> (dangereux)"**
- **Firefox** : **"Avancé..."** → **"Accepter le risque et continuer"**
- **Safari** : **"Afficher les détails"** → **"visiter ce site web"**

### Créer ton compte CloudCLI
À la première visite, CloudCLI te demande une adresse email et un
**mot de passe**. Choisis un mot de passe **fort** : c'est la clé
d'entrée de tous tes agents.

### Premier test
1. Clique sur **"New Project"** ou ouvre le workspace par défaut.
2. Choisis **Claude Code** comme agent.
3. Envoie un message simple :
   > Crée un fichier `hello.txt` contenant "Bonjour depuis ma VM !",
   > puis liste les fichiers du dossier.
4. Tu devrais voir l'agent réfléchir, écrire le fichier, lancer `ls`,
   et te confirmer le résultat en quelques secondes.

Si ça fonctionne, ta stack est opérationnelle 🎉

---

## 🚀 Étape 10 — Ouvrir code-server (VS Code web)

Dans un nouvel onglet :
```
https://<IP_PUBLIQUE_DE_TA_VM>/ide/
```

Tu arrives sur **VS Code dans ton navigateur**, sur le même dossier
de travail que CloudCLI (`/home/agent/workspace`). Tu peux :
- éditer les fichiers à la main,
- ouvrir le terminal intégré (`` Ctrl+` ``) où `claude`, `codex`,
  `git`, `node`, `python` sont tous préinstallés,
- installer des extensions depuis le marketplace Open-VSX.

---

## 🚀 Étape 11 — Vérifier les sauvegardes automatiques

L'installateur a déjà configuré le cron quotidien. Vérifie :
```bash
./scripts/status.sh
```

Tu dois voir une ligne :
```
✔ Sauvegarde automatique (cron.daily) : /opt/multi-agents/scripts/auto-snapshot.sh
```

Pour faire un **premier snapshot de test** maintenant, sans attendre
cette nuit :
```bash
./scripts/snapshot.sh premiere-sauvegarde
ls -lh backups/
```

Les sauvegardes automatiques se feront ensuite tous les jours
(vers 6h25 du matin par défaut sur Debian). Les logs seront dans
`/var/log/cloudcli-snapshot.log`.

---

## 🚀 Étape 12 — Accès depuis le téléphone 📱

1. Ouvre `https://<IP_PUBLIQUE_DE_TA_VM>/` dans **Chrome** (Android)
   ou **Safari** (iPhone), accepte l'avertissement de certificat.
2. Connecte-toi avec ton compte CloudCLI.
3. Ajoute la page à l'écran d'accueil :
   - **Chrome Android** : ⋮ → **"Ajouter à l'écran d'accueil"**
   - **Safari iPhone** : □ (partager) → **"Sur l'écran d'accueil"**
4. L'icône apparaît comme une app classique. Tu peux lancer et
   suivre les agents depuis ton téléphone comme depuis ton PC.

---

## 🔐 (Optionnel mais recommandé) Utiliser un vrai nom de domaine

Avec un domaine, le certificat devient automatiquement valide
(Let's Encrypt) : plus d'avertissement, même sur téléphone.

1. Achète un domaine (ex: `agents.mondomaine.tld`) chez Namecheap,
   Gandi, OVH, Cloudflare…
2. Crée un enregistrement DNS de type **A** qui pointe vers
   l'IP publique de ta VM.
3. Attends que ça se propage (quelques minutes).
4. Sur la VM, édite le `Caddyfile` :
   ```bash
   nano /opt/multi-agents/Caddyfile
   ```
   Remplace la première ligne `:80, :443 {` par ton domaine :
   ```caddy
   agents.mondomaine.tld {
   ```
   Supprime la ligne `tls internal` (elle force le cert auto-signé).
5. Redémarre Caddy :
   ```bash
   docker compose restart caddy
   ```
6. Au bout de 10-30s, ouvre `https://agents.mondomaine.tld` : le
   cadenas vert doit s'afficher ✅.

---

## 🎯 Utilisation quotidienne

| Action | Commande / URL |
|---|---|
| Lancer une mission Claude Code | `https://<IP>/` → nouveau projet → Claude Code |
| Lancer une mission Codex | `https://<IP>/` → nouveau projet → Codex |
| Éditer en IDE web | `https://<IP>/ide/` |
| Snapshot avant une mission risquée | `./scripts/snapshot.sh nom-du-snap` |
| Restaurer un snapshot | `./scripts/restore.sh nom-du-snap` |
| Voir les logs | `docker compose logs -f cloudcli` |
| État de la stack | `./scripts/status.sh` |
| Arrêter la stack | `docker compose stop` |
| Redémarrer la stack | `docker compose up -d` |
| Mettre à jour | `docker compose build --pull && docker compose up -d` |
| Reset complet | `./scripts/factory-reset.sh` |

---

## 🆘 Dépannage express

| Symptôme | Solution |
|---|---|
| `ERR_CONNECTION_REFUSED` | Les conteneurs ne tournent pas : `docker compose ps`, `docker compose logs cloudcli` |
| Erreur **502 Bad Gateway** | Le conteneur cloudcli est encore en train de booter, attends 30-60s |
| "Auth error" / 401 des agents | Mauvaise `OLLAMA_API_KEY` dans `.env`. Re-vérifie et `docker compose up -d` |
| Le build plante en OOM | Manque de RAM : il faut au moins 2 Go. Vérifie avec `free -h`. |
| Je ne peux pas me connecter du tout | Ports 80/443 pas ouverts dans le security-group de l'hébergeur |
| J'ai cassé quelque chose | `./scripts/restore.sh <nom-du-snap>` pour revenir à un état sain |
| Mdp CloudCLI perdu | `docker volume rm multi-agents_cloudcli-data` puis `docker compose up -d` (reset du compte) |

---

## 🎉 C'est prêt !

Tu as maintenant, sur ta VM Debian toute neuve :
- ✅ **Docker + Docker Compose**
- ✅ **CloudCLI** (UI web/mobile multi-agents) avec **Claude Code** + **Codex**
- ✅ **code-server** (VS Code web) sur le même workspace
- ✅ Reverse proxy **HTTPS** (Caddy)
- ✅ **Sauvegardes automatiques quotidiennes** (14 jours conservés)
- ✅ Tout ça alimenté par **Ollama Cloud**, sans GPU nécessaire

Bonnes missions avec tes agents ! 🤖💻📱
