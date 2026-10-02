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
