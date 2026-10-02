# ⚡ Guide : Debian/Ubuntu VIERGE — Démarrage en 5 minutes

> Guide ultra-court pour une VM Debian **12/13** ou Ubuntu **22.04/24.04**
> qui sort tout juste du panel de l'hébergeur. Aucune connaissance
> requise : vous copiez-collez trois commandes.
> Pour les autres OS, voir [`TUTORIEL-INSTALLATION.md`](./TUTORIEL-INSTALLATION.md).

---

## 📋 Ce dont vous avez besoin avant de commencer

1. Une VM fraîche avec **Debian 12 Bookworm** ou **Ubuntu 24.04 LTS**
   (Hetzner CX11/CX22, OVH VPS, DigitalOcean Droplet, Scaleway DEV1,
   Oracle Cloud Free Tier, Raspberry Pi 5 sous Pi OS Bookworm 64-bit,
   Proxmox, VirtualBox, etc.).
2. Les **ports 80, 443 et 3001** ouverts dans le security-group /
   pare-feu de votre hébergeur.
3. Une **clé API Ollama Cloud** : https://ollama.com/settings/keys
   (commence par `sk-ollama-...`).
4. L'**IP publique** de la VM (affichée dans le panel de l'hébergeur).

---

## 🚀 3 commandes pour tout installer

### 1. Connectez-vous en SSH à la VM

Depuis votre PC (Windows : PowerShell / WSL ; macOS / Linux : Terminal) :

```bash
ssh root@<IP_PUBLIQUE_DE_LA_VM>
```

Si votre hébergeur vous a donné un utilisateur non-root (`debian`, `ubuntu`, `opc`, `azureuser`…) :

```bash
ssh ubuntu@<IP_PUBLIQUE_DE_LA_VM>
sudo -i
```

Vérifiez que vous êtes bien root :
```bash
whoami        # doit afficher "root"
```

### 2. Lancez l'installateur une commande

Remplacez les valeurs par votre clé API et votre IP :

```bash
curl -fsSL https://raw.githubusercontent.com/Tiij/VMREMOTEAGENT/main/setup.sh \
  | OLLAMA_API_KEY=sk-ollama-VOTRE-CLE HOSTNAME_PUBLIQUE=VOTRE.IP bash
```

Exemple réel :
```bash
curl -fsSL https://raw.githubusercontent.com/Tiij/VMREMOTEAGENT/main/setup.sh \
  | OLLAMA_API_KEY=sk-ollama-a1b2c3d4e5f6... HOSTNAME_PUBLIQUE=203.0.113.42 bash
```

> 💡 Si vous ne mettez pas les variables, le script vous demandera
> la clé interactivement et tentera de détecter l'IP automatiquement :
>
> ```bash
> curl -fsSL https://raw.githubusercontent.com/Tiij/VMREMOTEAGENT/main/setup.sh | sudo bash
> ```

⏳ Le script :
- Installe Docker si absent (2-3 min),
- Crée `/opt/multi-agents/` avec tous les fichiers,
- Build l'image (5-15 min au premier lancer),
- Configure les snapshots automatiques quotidiens,
- Affiche les URLs finales.

### 3. Ouvrez le dashboard dans votre navigateur

Quand le script affiche ✅ **Installation terminée !**, allez sur :

```
https://<IP_PUBLIQUE>/
```

Acceptez l'avertissement de certificat auto-signé, et vous voilà sur le dashboard. Cliquez sur **Agents CloudCLI**, créez votre compte (mot de passe fort), et envoyez votre première mission.

---

## 🔗 Les 3 URLs à retenir

| URL | Service |
|---|---|
| `https://<IP>/` | **Dashboard** — page d'accueil avec tous les raccourcis |
| `https://<IP>:3001/` | **CloudCLI** — pilotage des agents Claude Code / Codex |
| `https://<IP>/ide/` | **code-server** — VS Code web sur le même workspace |

---

## 🧪 Premier test (recommandé)

Dans CloudCLI, créez un projet avec Claude Code et envoyez :

> Crée un fichier `hello.py` qui affiche "Bonjour depuis ma VM !",
> puis exécute-le avec python3.

Si l'agent crée le fichier, lance `python3 hello.py` et vous répond
"Bonjour depuis ma VM !", tout fonctionne. 🎉

---

## 💾 Vérifiez les sauvegardes

L'installateur a déjà configuré un cron quotidien. Pour tester sans attendre :

```bash
cd /opt/multi-agents
./scripts/snapshot.sh premier-test
ls -lh backups/
./scripts/status.sh
```

---

## 🔐 (Optionnel mais recommandé) Vrai nom de domaine + certificat valide

Le certificat auto-signé déclenche un avertissement à chaque connexion, ce qui est pénible sur téléphone. Pour un cadenas vert automatique :

1. Achetez un domaine et créez un enregistrement **A** pointant vers l'IP de la VM.
2. Attendez la propagation DNS (2-5 min) : `ping agents.votretld.tld` doit répondre avec votre IP.
3. Sur la VM :

```bash
cd /opt/multi-agents
nano Caddyfile
```

Remplacez :
- `https://:443 {` par `agents.votretld.tld {`
- `https://:3001 {` par `agents.votretld.tld:3001 {`
- Supprimez les deux lignes `tls internal`.

4. Redémarrez :
```bash
docker compose restart caddy
```

Au bout de 10-30 secondes, https://agents.votretld.tld s'ouvre avec le cadenas vert. Caddy obtient et renouvelle automatiquement les certificats Let's Encrypt.

---

## 🛟 Si ça ne marche pas

| Symptôme | Solution rapide |
|---|---|
| `docker compose ps` ne montre rien | Attendez la fin du build, ou relancez : `cd /opt/multi-agents && docker compose up -d --build` |
| Je ne peux pas joindre l'IP | Ports 80/443/3001 pas ouverts dans le security-group de l'hébergeur |
| Erreur 502 | Attendez 60 secondes (premier démarrage de CloudCLI) |
| Les agents renvoient 401 | Vérifiez la clé dans `.env` : `cat /opt/multi-agents/.env | grep OLLAMA_API_KEY` |
| J'ai tout cassé | `./scripts/snapshot.sh sauvetage && ./scripts/restore.sh premier-test` |

Guide de dépannage complet : [`TUTORIEL-INSTALLATION.md` § 8](./TUTORIEL-INSTALLATION.md#-8-dépannage).
Documentation sauvegardes : [`BACKUPS.md`](./BACKUPS.md).

---

Bonnes missions ! 🤖💻📱
