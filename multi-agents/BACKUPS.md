# 🛡️ Sauvegardes & restauration : protéger la VM contre les agents

Les agents Claude Code / Codex ont accès au shell, à git, à npm/pip,
etc. Ils peuvent installer des paquets, créer/supprimer des fichiers,
et — s'ils se trompent — casser l'environnement de travail.
Même si CloudCLI tourne dans un conteneur Docker (donc sans accès
système à la VM hôte), il faut pouvoir revenir en arrière **rapidement**.

Cette stack fournit deux niveaux de sauvegarde complémentaires :

| Niveau | Quoi | Quand |
|---|---|---|
| **🥇 Snapshot de la VM entière** | TOUT (OS + config Docker + stack) | Avant une "grosse mission" ou toute install système |
| **🥈 Snapshot de la stack** | Contenu CloudCLI + code-server + projets | Automatique tous les jours + à la demande |

---

## 🥇 Niveau 1 : Snapshot de la VM (recommandé, le plus simple)

C'est la protection la plus forte. **Tous les providers cloud
(Hetzner, OVH, DigitalOcean, Vultr, AWS, GCP, Azure, Scaleway...)
proposent des snapshots en 1 clic.**

### Quand prendre un snapshot
- Juste **avant de donner une mission destructrice** à un agent
  (ex: *"migre ce projet de Next.js 14 à Next.js 15 et adapte toutes
  les routes"*, *"refactorise toute la base de code en TypeScript"*,
  *"déploie en production"*, etc.).
- Avant toute installation système (`apt install`, modification de
  Docker, changement de port, etc.).
- Toutes les semaines si tu utilises la stack régulièrement.

### Comment
1. Éteins proprement depuis l'intérieur (optionnel mais plus sûr) :
   ```bash
   cd /opt/multi-agents
   docker compose stop
   ```
2. Sur le panel de ton hébergeur : **Créer un snapshot** (souvent
   dans "Sauvegardes" / "Snapshots"). Ça prend entre 1 et 5 minutes
   selon la taille du disque.
3. Redémarre la VM ou redémarre la stack :
   ```bash
   docker compose start
   ```

Si l'agent casse tout : tu recliques sur le snapshot → **restaurer**
→ la VM redémarre dans l'état exact où elle était au moment du
snapshot. Rien d'autre à faire.

> 💡 Beaucoup d'hébergeurs proposent aussi des **sauvegardes
> automatiques quotidiennes** (souvent pour 10-20% du prix de la VM).
> Active-les si c'est une option : ça te sauve même si la VM ne
> démarre plus du tout.

---

## 🥈 Niveau 2 : Snapshot de la stack (out-of-band, sans panel cloud)

Même si tu as des snapshots VM, les scripts de backup dans `scripts/`
te permettent de sauvegarder/restaurer juste la stack CloudCLI
(sans devoir restaurer toute la VM). C'est utile quand :
- Tu veux revenir à un état antérieur **des projets seulement**,
- Tu veux copier une configuration d'une VM à une autre,
- Tu veux garder des snapshots quotidiens automatiques.

### Ce que ça sauvegarde
Tous les **volumes Docker** de la stack :
- `cloudcli-data` → comptes utilisateur CloudCLI, préférences UI, DB SQLite
- `claude-data` → sessions Claude Code, MCP, skills
- `codex-data` → config Codex
- `codeserver-data` / `codeserver-config` → extensions et config VS Code
- `projects` → le workspace `/home/agent/workspace` (tous les projets)
- `caddy-data` / `caddy-config` → certificats TLS

Plus les fichiers de config du host : `docker-compose.yml`, `Caddyfile`,
`.env`, le dossier `cloudcli/`.

### Prendre un snapshot manuel

```bash
cd /opt/multi-agents
./scripts/snapshot.sh
```

Ou avec un nom explicite (utilisez-le avant une grosse mission agent) :
```bash
./scripts/snapshot.sh avant-migration-next15
```

Les archives sont stockées dans `backups/` :
```bash
ls -lh backups/
```

### Lister les snapshots disponibles
```bash
ls -lh backups/*.tar.gz
```

### Restaurer un snapshot

⚠️ **La restauration remplace les données actuelles** par celles du
snapshot. Pense à prendre un snapshot de l'état courant avant
restaurer, au cas où :

```bash
./scripts/snapshot.sh avant-restauration
./scripts/restore.sh avant-migration-next15
```

La stack est arrêtée, les volumes supprimés puis ré-importés, et la
stack redémarre automatiquement.

### Reset complet (remise à zéro)
Si tu veux tout effacer et repartir à zéro :
```bash
./scripts/factory-reset.sh
```

### Sauvegardes automatiques quotidiennes

**`install.sh` installe déjà le cron quotidien pour toi**
(lien `/etc/cron.daily/cloudcli-snapshot`). Aucune action
supplémentaire n'est nécessaire. Pour vérifier :

```bash
cd /opt/multi-agents
./scripts/status.sh
ls -l /etc/cron.daily/cloudcli-snapshot
```

Par défaut :
- Les sauvegardes tournent **tous les jours** (heure définie dans `/etc/crontab` pour `cron.daily`, typiquement 6h25),
- **14 snapshots "auto-\*"** sont conservés (soit ~2 semaines),
- les snapshots **manuels** sont purgés après **30 jours**,
- les logs sont dans `/var/log/cloudcli-snapshot.log`.

Pour un **horaire précis** (ex: 3h00) ou changer le nombre de snapshots
conservés, ajoute une entrée crontab personnalisée :

```bash
# Exemple : tous les jours à 3h du matin, garder 30 snapshots
(crontab -l 2>/dev/null | grep -v cloudcli-snapshot; \
 echo "0 3 * * * SNAPSHOT_KEEP=30 /opt/multi-agents/scripts/auto-snapshot.sh >> /var/log/cloudcli-snapshot.log 2>&1") | crontab -
crontab -l | grep cloudcli
```

Après la première nuit, vérifie que les snapshots arrivent :
```bash
ls -lh backups/auto-*.tar.gz
tail /var/log/cloudcli-snapshot.log
```

---

## 💡 Bonnes pratiques avant de confier une grosse mission à un agent

1. **Git d'abord.** Si le projet est un repo git :
   ```bash
   cd /home/agent/workspace/mon-projet   # ou via le terminal intégré
   git status
   git add -A && git commit -m "wip: avant agent"
   git checkout -b agent/experiment
   ```
   Si l'agent casse tout : `git reset --hard HEAD` ou tu supprimes
   la branche. C'est la restauration la plus rapide pour du code.
   CloudCLI a un panneau Git intégré qui voit aussi ces commits.

2. **Snapshot manuel.**
   ```bash
   cd /opt/multi-agents
   ./scripts/snapshot.sh "avant-<mission>"
   ```

3. **Snapshot VM côté hébergeur** (optionnel mais recommandé si la
   mission implique des changements d'infra : install de paquets
   système, Docker, changements réseau).

4. **Donne un périmètre clair à l'agent.**
   Dans le prompt : *"Travaille uniquement dans ./mon-projet. Ne
   touche pas au système (pas de apt, pas de docker, pas de
   modification de /etc). Ne supprime aucun fichier sans demander."*
   Claude Code et Codex respectent généralement ces consignes si
   elles sont explicites.

5. **Reste à proximité au début.**
   Pour une mission sensible, garde un œil sur le terminal CloudCLI
   et appuie sur **Échap** ou **Ctrl+C** si tu vois l'agent partir
   en vrille (ex: enchaînement de `rm -rf`, installations massives,
   appels réseaux suspects, etc.).

---

## 🔒 Pourquoi les agents ne peuvent pas casser la VM hôte

Par défaut cette stack isole les agents :

| Couche | Protection |
|---|---|
| **Isolation Docker** | Les agents tournent dans un conteneur. Ils ne peuvent pas accéder aux fichiers de la VM hôte hors des volumes montés. |
| **Pas d'accès Docker socket** | Le socket `/var/run/docker.sock` n'est **pas** monté : les agents ne peuvent ni lancer/arrêter d'autres conteneurs, ni s'échapper via Docker. |
| **Pas de privilèges root** | `claude` et `codex` tournent en tant qu'utilisateur `agent` (uid 1000) dans le conteneur. |
| **Sortie réseau par défaut** | Les agents peuvent joindre Internet (pour cloner des repos, installer des packages, appeler Ollama Cloud), mais Caddy n'expose que 80/443 : les ports 3001/8080 ne sont pas accessibles hors localhost sans passer par le reverse proxy. |
| **Mots de passe CloudCLI** | Compte local obligatoire avant de pouvoir utiliser l'interface. |

Si tu montes un jour le Docker socket (pour que les agents puissent
eux-mêmes lancer des conteneurs), ou si tu ajoutes d'autres services,
repasse par un snapshot VM AVANT de donner ce pouvoir aux agents.

---

## 📤 Exporter un snapshot vers ton PC

Pour rapatrier une sauvegarde sur ton ordinateur :
```bash
# Depuis ton PC :
scp root@<IP_VM>:/opt/multi-agents/backups/avant-migration-next15.tar.gz ./
```

Restaure-le ensuite sur une autre VM en copiant le fichier dans
`/opt/multi-agents/backups/` puis en lançant `./scripts/restore.sh
avant-migration-next15`.
