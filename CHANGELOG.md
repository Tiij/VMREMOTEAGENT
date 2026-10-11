# Changelog

Toutes les modifications notables de VMREMOTEAGENT sont documentées ici.
Le format s'inspire de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).
Le versionning suit [SemVer](https://semver.org/lang/fr/) : `MAJEUR.MINEUR.PATCH`.

---

## [1.4.8] — 2026-10-11

### Corrigé
- **Installation tuée en silence via `curl … | bash` après le snapshot** :
  `scripts/snapshot.sh` lançait `docker compose exec -T cloudcli …` sans
  rediriger son entrée. Sous un installateur exécuté depuis une pipe
  (`curl -fsSL … | bash`), Docker consommait le stdin hérité — c'est-à-dire
  **la suite du script source** — et bash atteignait une fin de fichier
  fictive au beau milieu de l'installation (arrêt propre, code 0, sans
  aucune erreur, juste après « Snapshot de sauvegarde créé »). Désormais
  `</dev/null` protège le source du script.
- **Crash `BASH_SOURCE[0]: unbound variable` (ligne 2368)** au recopiage de
  `setup.sh` dans `/opt/multi-agents/setup.sh` : en exécution pipée il n'y a
  aucun fichier source, `BASH_SOURCE` est vide et l'expansion nue mourait
  sous `set -u` juste après « Fichiers de config écrits », en plein milieu
  d'une réparation. (C'était exactement le crash constaté sur VMRA-007.)
- **Wizard texte aveugle + variables polluées** : `inputbox`, `passwordbox`,
  `menu`, `yesno` et `msgbox` en mode texte affichaient leurs questions sur
  **stdout**, que le wizard capture (`HOST=$(inputbox …)`) : les invites
  étaient donc invisibles et **les variables récupéraient tout le texte du
  prompt collé à la réponse** (l'utilisateur tapait à l'aveugle, le récap
  affichait les blocs de prompt à la place des valeurs). Les questions
  partent maintenant sur stderr (`$INTERACTIVE_OUT`), les variables ne
  contiennent plus que la réponse saisie.
- **Menu qui retournait la mauvaise option sur saisie texte** : taper
  « repair » rendait `[ "$R" -lt 1 ]` en erreur entière, puis `$((R-1))`
  évaluait une variable inexistante → index -1 → **la 5ème entrée** (« status »)
  était retournée silencieusement. Le menu accepte désormais le nom de
  l'option (insensible à la casse), un numéro, ou une saisie vide.
- **Ouverture du fd de saisie au top-level** : l'ouverture de `/dev/tty`
  (fd 7) se faisait à l'intérieur des sous-shells `$( … )` du wizard ; un
  exec raté à cet endroit tue tout le script (exit 1 silencieux via set -e).
  Le fd est maintenant ouvert une seule fois hors capture, fermé proprement
  à la sortie (trap), et réutilisé partout.

### Testé
- VM Debian 12 x86_64 (2 vCPU / 2048 Mo, conteneurs actifs) : réinstallation
  complète **pipée** (`cat setup.sh | env … bash`) jusqu'à l'écran final,
  wizard interactif réel via pseudo-TTY (réponses invisibles avant,
  visibles et propres maintenant), snapshot/restore intacts.

---

## [1.4.7] — 2026-10-11

### Corrigé
- **`./scripts/doctor.sh --fix` ne réparait rien sur une installation sans clé API**
  ("mode sans IA") : la relance de `setup.sh` mourait immédiatement avec
  `OLLAMA_API_KEY absent`, laissant l'installation cassée. Le drapeau
  `ALLOW_NO_API_KEY` est désormais relu depuis le `.env` existant avant le
  contrôle de la clé, et le doctor le transmet à la relance.
- `setup.sh` écrasait la config permanente à chaque réparation/mise à jour :
  `ALLOW_NO_API_KEY` et `SNAPSHOT_KEEP` personnalisés retombaient à leurs
  défauts (0 et 3). Ils sont maintenant préservés comme les autres secrets.

### Testé
- Validation complète sur VM Debian 12 (2 vCPU / 2048 Mo) : installation,
  healthcheck, limites mémoire, snapshot/restore, redémarrage, agents
  Claude et Codex répondant via Ollama Cloud, puis cycle
  casse → `doctor --fix` → réparation.

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

## [1.4.5] — 2026-10-03

### Corrigé
- **Erreur `unknown flag: --parallel`** au lancement de `docker compose up` :
  `--parallel` n'est un flag que de la sous-commande `docker compose build`,
  pas de `docker compose up`. Remplacé par les variables d'environnement
  appropriées pour limiter la concurrence sur les machines ARM64 à faible
  RAM :
  - `DOCKER_BUILDKIT=0` (désactive BuildKit, moins consommateur que le
    builder classique en RAM sur les petits VPS ARM64),
  - `COMPOSE_PARALLEL_LIMIT=1` (force Compose à ne builder qu'une couche
    à la fois).
  Ce correctif s'ajoute à ceux du 1.4.4 (npm séquentiel, heap Node
  limité, swap 4 Go).

---

## [1.4.4] — 2026-10-03

### Corrigé
- **Build Docker qui plante avec `exit code: 137`** (SIGKILL / OOM Out of
  Memory) à l'étape `npm install -g @anthropic-ai/claude-code
  @openai/codex @cloudcli-ai/cloudcli` sur les VMs avec peu de RAM
  (typiquement ARM64 avec 1-2 Go de RAM, sur lesquelles npm
  consomme 2.5-3 Go de RAM au pic quand il installe les trois paquets
  en parallèle).
  - Les trois paquets npm sont maintenant installés **séparément**
    (trois couches Docker distinctes) au lieu d'une seule commande,
    divisant le pic mémoire par ~3.
  - `NODE_OPTIONS="--max-old-space-size=1024"` force Node à se limiter
    à 1 Go de heap, évitant les explosions mémoire.
  - `NPM_CONFIG_JOBS=1` + `NPM_CONFIG_MAXSOCKETS=1` désactive le
    parallélisme npm pour réduire l'empreinte.
  - Concurrence BuildKit désactivée (`--parallel=0`) sur ARM64 avec
    moins de 2.5 Go de RAM, pour éviter que plusieurs couches ne
    soient buildées en parallèle.
  - Swap automatique augmenté à **4 Go** (au lieu de 2 Go) sur les
    machines ARM64 ≤ 2.5 Go de RAM.
- **Chromium retiré de l'image Docker** (sauve ~400 Mo et réduit la
  conso RAM/pic au build) : il n'est pas utilisé en serveur et peut
  être réinstallé à la main si besoin.
- Message d'avertissement clair affiché si la RAM est insuffisante et
  que le build risque d'échouer, avec la consigne (augmenter à 4 Go).

---

## [1.4.3] — 2026-10-02

### Corrigé
- **Erreur "bash: line 2013: syntax error: unexpected end of file"** : le
  script était parfois **tronqué en milieu de téléchargement** quand
  l'utilisateur lançait `curl … | bash` directement (la connexion TCP
  se fermait avant la fin, bash exécutait ce qu'il avait reçu et
  rencontrait un `fi`/`esac` non fermé à la ligne de coupure).
- **Ajout d'un installateur sûr `install.sh`** qui :
  1. Télécharge `setup.sh` dans un fichier temporaire (avec `--retry 3`
     et `--max-time 60`),
  2. Vérifie la syntaxe bash (`bash -n`) avant de l'exécuter,
  3. Vérifie la présence du marqueur de fin `_VMRA_EOF_MARKER=1` ajouté
     à la fin de `setup.sh` pour détecter toute troncature silencieuse.
- **Marqueur d'intégrité** `_VMRA_EOF_MARKER=1` ajouté en fin de
  `setup.sh`. Il NE DOIT PAS être supprimé ; si curl tronque le
  téléchargement, ce marqueur est absent et le script ne s'exécute
  pas.

### À noter
- La méthode recommandée est désormais d'utiliser `install.sh` (plus
  petit, 58 lignes, moins de risque de troncature) plutôt que de piper
  directement `setup.sh` dans bash. Les deux méthodes restent
  supportées mais `install.sh` est plus robuste.

---

## [1.4.2] — 2026-10-02

### Corrigé
- **Blocage apparent après "Assistant d'intégration..." en mode
  `curl | sudo bash`** : quand l'utilisateur lançait l'installateur via
  un pipe ET fournissait déjà `OLLAMA_API_KEY` et `HOSTNAME_PUBLIQUE`,
  le wizard essayait quand même de poser des questions (adresse,
  dossier, récap). Les prompts texte s'affichaient sur stdout (bufferisé
  en mode pipe) et `read </dev/tty` attendait une saisie invisible — le
  script paraissait bloqué à l'étape "Assistant d'intégration..." alors
  qu'il attendait une touche Entrée que l'utilisateur ne voyait pas.
  → **Auto-skip du wizard** si stdin n'est pas un TTY ET que
  `OLLAMA_API_KEY` + `HOSTNAME_PUBLIQUE` sont déjà fournis. Le script
  enchaîne directement l'installation sans aucune invite.
- Détection robuste du TTY de contrôle (`/dev/tty` ou stderr) pour
  afficher les messages même en mode pipé.

---

## [1.4.1] — 2026-10-02

### Corrigé
- **Bug critique `curl | bash`** : les invites interactives (`yesno`,
  `inputbox`, `passwordbox`, `menu`) lisaient depuis stdin au lieu de
  `/dev/tty`. Quand l'installateur était lancé via
  `curl -fsSL URL | sudo bash`, stdin contenait le source du script
  lui-même : les `read` consommèrent donc le code au lieu d'attendre
  une saisie utilisateur, provoquant l'erreur
  `syntax error: operand expected (error token is ""$DETECTED_ACTION"")`
  à la ligne 250 puis la sortie prématurée du script.
  → Ajout d'un helper `prompt_read` / `prompt_read_silent` qui ouvre
  `/dev/tty` quand stdin n'est pas un terminal, et remplacement de tous
  les `read` interactifs du wizard par ces helpers. En l'absence de TTY
  (CI, cron), `NONINTERACTIVE=1` est forcé automatiquement.
- **`fi` manquant dans le bloc NO_BUILD/healthcheck** : en mode
  `NO_BUILD=1`, le script tombait dans la boucle de healthcheck et
  `set -e` le terminait avant d'écrire le state file et l'écran final
  de succès.
- **Fonction `bad()` absente au top-level** (n'existait que dans le
  scope des scripts embarqués).
- **Heredocs manquants** `scripts/update.sh` et `VERSION` dans
  l'installateur embarqué (l'updater et le fichier de version
  n'étaient pas écrits à l'install).
- **`software-properties-common`** rendu optionnel sur Debian
  trixie/testing où le paquet n'existe pas.
- **Vérification root déplacée avant la bannière** pour que le
  message "lancez avec sudo" s'affiche même si `/opt` n'existe pas.

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
