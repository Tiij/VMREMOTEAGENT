# Changelog

Toutes les modifications notables de VMREMOTEAGENT sont documentées ici.
Le format s'inspire de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).
Le versionning suit [SemVer](https://semver.org/lang/fr/) : `MAJEUR.MINEUR.PATCH`.

---

## [1.2.0] — 2026-10-02

### Ajouté
- **Système de mise à jour automatique** (`scripts/update.sh`) :
  - Vérifie la dernière version disponible sur GitHub (channel `stable`,
    `beta` ou `dev`) en comparant le fichier `VERSION` distant.
  - Affiche le changelog de la version cible avant toute action.
  - Crée un **snapshot de précaution** avant toute mise à jour
    (nommé `pre-update-<ancienne>-to-<nouvelle>-<date>`).
  - Télécharge le nouvel installateur, valide sa syntaxe bash avant
    exécution, le met dans `./setup.sh`, puis le lance en mode `update`.
  - **Healthcheck post-update** (30s) : attend que le dashboard réponde.
  - **Rollback automatique** si la nouvelle version ne démarre pas
    (restaure le snapshot de précaution).
  - Modes : `--check` (dry-run), `--yes` (sans confirmation),
    `--force` (réinstallation même si à jour), `--channel <stable|beta|dev>`.
  - Fichier `VERSION` racine exposant la version installée.
- **7ème carte** "🚀 Mettre à jour" dans le dashboard avec la commande à
  lancer et la mention du rollback automatique.
- Carte "État/Réparer" renommée, intégrée avec le système de MAJ.

### Modifié
- **setup.sh** v1.2.0 : génère maintenant `VERSION` et `scripts/update.sh`
  dans le dossier d'installation.
- **README** : nouvelle section "Mises à jour" et update.sh dans la
  structure, les commandes utiles, et le dépannage.

---

## [1.1.0] — 2026-10-02

### Ajouté
- Idempotence de l'installateur (diagnostic 9 points avant action).
- Modes adaptatifs auto-détectés : install / repair / update / light-restart
  / rebuild / reinstall.
- Snapshot de précaution avant modification d'une install existante.
- Préservation OLLAMA_API_KEY et WEBUI_SECRET_KEY en réparation/mise à jour.
- Healthcheck post-install (30s) et fichier d'état `.vmremoteagent.state`.
- `scripts/doctor.sh` : diagnostic + réparation automatique standalone.
- Message d'erreur non-root pédagogique dans setup.sh et install.sh.

---

## [1.0.0] — 2026-10-01

### Ajouté
- Release initiale : dashboard Apple-style, CloudCLI sur :3001, code-server
  sur /ide/, Caddy HTTPS, installateur une commande, 5 scripts de backup,
  README et tutoriels multi-OS, licence propriétaire.

---

## Channels de mise à jour

| Channel | Branche | Usage |
|---|---|---|
| `stable` (défaut) | `main` | Versions taguées, testées. |
| `beta`   | `beta` | Prochaine version, pour les testeurs. |
| `dev`    | `dev`  | Dernier commit, instable. |

Pour changer de channel :
```bash
sudo ./scripts/update.sh --channel beta
```

---

## [1.3.0] — 2026-10-02

### Ajouté
- **Bloc de vérification système (12 points)** en début d'installation :
  * Architecture (amd64 / arm64 / armv7) avec mapping ARCH_DOCKER
  * CPU (nproc), avertissement si <2 coeurs
  * Disque disponible sur le dossier d'installation, erreur si <5 Go
  * RAM (MemTotal), erreur si <2 Go, **création automatique d'un swap 2 Go**
    si RAM <4 Go et espace disque >15 Go (évite les OOM au build sur
    les petites VM type 2 Go)
  * Distribution et détection automatique du gestionnaire de paquets
    (apt / dnf / yum / pacman / apk / zypper / brew) via `/etc/os-release`
    (ID et ID_LIKE, fallback intelligent)
  * Présence de systemd (avertissement si absent)
  * Connectivité Internet vers 5 hôtes critiques (github.com, ollama.com,
    registry-1.docker.io, deb.nodesource.com, raw.githubusercontent.com)
  * Vérification des ports 80/443/3001 avec nom du processus qui les
    occupe (avertissement si occupé par autre chose que Docker/Caddy)
  * Confirmation interactive si des problèmes critiques sont détectés
    (sauf NONINTERACTIVE=1)
- **Installation automatique des dépendances multi-distro** :
  * Debian/Ubuntu/Mint/Pop!/Raspbian/Kali/Zorin : apt
  * Fedora/RHEL/Rocky/Alma/Oracle/Amazon : dnf (fallback yum)
  * Arch/Manjaro/EndeavourOS : pacman
  * Alpine : apk (openrc)
  * openSUSE/SLES : zypper
  * macOS : détection de Docker Desktop uniquement
  * Paquets installés dans tous les cas : ca-certificates, curl, git,
    wget, sudo, nano, gnupg, vim, cron, coreutils, procps, jq, iptables,
    tar, findutils.
- **Installation de Docker multi-distro** avec le repo officiel docker.com
  (yum/dnf, apt, pacman, apk, zypper) ; activation + démarrage du service
  via systemd ou service/openrc ; ajout de l'utilisateur au groupe
  `docker` si lancé via sudo.

### Modifié
- setup.sh : les deux premières étapes sont explicitement numérotées
  **1. Vérification** / **2. Installation des dépendances** ; les blocs
  qui suivent (diagnostic d'état existant, écriture des configs, build,
  healthcheck) restent inchangés mais fonctionnent maintenant sur les
  distros non-Debian.
- Le message d'erreur non-root est conservé (il vient en tout début
  de script, avant toute modification système).

---

## [1.4.0] — 2026-10-02

### Ajouté
- **TUI (Terminal User Interface) avec whiptail** : l'installateur utilise
  whiptail (installé automatiquement via apt/dnf/pacman/apk/zypper si
  absent) pour afficher des boîtes de dialogue, menus, invites de saisie
  et une barre de progression (gauge) pendant l'installation. Bascule
  automatiquement en mode texte brut si le terminal n'est pas
  interactif, si whiptail est indisponible, si `NOTUI=1` ou
  `NONINTERACTIVE=1` est défini.
- **Verrou d'installation PID** (`/var/run/vmremoteagent-install.lock`)
  qui empêche de lancer deux installations en parallèle. Les verrous
  orphelins (processus mort) sont détectés et nettoyés.
- **Assistant d'onboarding (wizard) interactif** :
  * écran de bienvenue expliquant les étapes,
  * menu d'action si une installation existante est détectée (réparer,
    mettre à jour, rebuild, réinstaller, voir l'état),
  * invite de saisie masquée (passwordbox) pour la clé Ollama,
  * invite de saisie pour l'IP/host (avec détection automatique par
    défaut et conservation de la valeur précédente),
  * invite pour le dossier d'installation,
  * écran récapitulatif avant installation avec confirmation.
- **Barre de progression en temps réel** qui passe de 5% → 100% à
  travers les 8 étapes : démarrage, vérification système, dépendances,
  Docker, diagnostic existant, écriture configs, cron, build/démarrage,
  healthcheck, finalisation.
- **Détection explicite du succès / échec final** :
  * Écran `✅ Installation réussie` avec les URLs, la procédure de
    première visite, les commandes utiles, en whiptail ou texte.
  * Écran `✘ Échec de l'installation` qui affiche les consignes de
    diagnostic (logs, `./scripts/doctor.sh --fix`, relance idempotente,
    restauration de snapshot). Le code de retour est 1 en cas d'échec.
  * Le fichier d'état `.vmremoteagent.state` est systématiquement
    écrit, même en cas d'échec (`state=failed` + `fail_date`), pour que
    la prochaine relance parte directement en mode réparation.
- **Gestion propre des signaux** (INT/TERM/HUP/EXIT) : le verrou est
    toujours supprimé et le terminal est restauré (`stty sane`) à la
    sortie, même si l'utilisateur appuie sur Ctrl+C.

### Amélioré
- `cleanup_lock()` est enregistré dans un `trap` EXIT et nettoie aussi
  le FIFO de la barre de progression.
- Si `docker compose up` échoue, le script ne s'arrête plus brutalement
  via `die()` : il marque l'état `failed` et tombe sur l'écran d'échec
  avec les consignes, au lieu de laisser l'utilisateur sans retour.
- Les invites interactives du mode texte prennent des valeurs par
  défaut et acceptent les réponses vides.
- La détection du host existant depuis `.env` est conservée d'une
  relance à l'autre (pas de re-demande inutile).
