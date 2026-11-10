<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português</a> · <b>Français</b> · <a href="README.de.md">Deutsch</a> · <a href="README.ru.md">Русский</a></p>

<p align="center"><img src="assets/banner.svg" alt="Claude Code Remote Control pour macOS : service d'arrière-plan permanent via launchd" width="100%"></p>

<p align="center">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-green.svg"></a>
  <a href="https://github.com/sicaboy/claude-code-remote-control-launchd/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/sicaboy/claude-code-remote-control-launchd/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="Platform: macOS" src="https://img.shields.io/badge/platform-macOS-lightgrey.svg">
  <img alt="Shell: bash" src="https://img.shields.io/badge/shell-bash-4EAA25.svg">
  <img alt="Open source" src="https://img.shields.io/badge/open%20source-%E2%9D%A4-orange.svg">
  <a href="https://github.com/sicaboy/claude-code-remote-control-launchd/pulls"><img alt="PRs welcome" src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg"></a>
</p>

# Claude Code Remote Control for macOS

Exécutez **Remote Control** de [Claude Code](https://code.claude.com) (`claude remote-control`) comme un service macOS permanent en arrière-plan (LaunchAgent launchd). Votre Mac apparaît comme une **carte d'appareil** dans l'onglet Code de l'app Claude (et sur claude.ai/code) : vous pouvez ainsi démarrer à tout moment de nouvelles sessions indépendantes depuis votre téléphone, sans laisser un terminal ouvert.

Il s'agit d'un petit LaunchAgent accompagné d'un script superviseur. Il démarre à l'ouverture de session, relance le serveur quand il s'arrête et évite les redémarrages en boucle.

> Projet communautaire non officiel, sans lien avec Anthropic ni approbation de sa part.

## Installation (une seule commande)

```bash
curl -fsSL https://raw.githubusercontent.com/sicaboy/claude-code-remote-control-launchd/main/install.sh | bash -s -- --workdir ~/projects --name "My Mac"
```

ou depuis un clone du dépôt :

```bash
git clone https://github.com/sicaboy/claude-code-remote-control-launchd && cd claude-code-remote-control-launchd
./install.sh --workdir ~/projects --name "My Mac"
```

| Option | Par défaut | Signification |
| --- | --- | --- |
| `--workdir DIR` | `~/claude-rc` | Dossier dans lequel démarrent les sessions. Il doit être **approuvé** par Claude Code (voir ci-dessous). Pas votre dossier personnel. |
| `--name NAME` | le nom du Mac | Nom de l'appareil affiché dans l'app |
| `--capacity N` | `10` | Nombre maximal de sessions simultanées. Les sessions inactives gardent leur place : quand le serveur est plein, les nouvelles sessions sont ignorées sans message. |
| `--spawn MODE` | `same-dir` | `same-dir` (fichiers partagés) ou `worktree` (nécessite un dépôt git) |
| `--keep-awake` | désactivé | Maintient `caffeinate -s` tant que le serveur tourne, pour que le Mac ne se mette pas en veille sur secteur. Ne modifie aucun réglage d'énergie du système. |

Relancer `install.sh` avec de nouvelles options met l'installation à jour sur place.

**Avant d'installer :** soyez connecté (`claude auth login`, avec un compte claude.ai ; les clés d'API ne fonctionnent pas avec Remote Control) et approuvez une fois le dossier de travail : `cd ~/projects && claude`, puis acceptez l'invite. L'installateur vérifie les deux et vous indique quoi faire.

## Utilisation courante

```bash
./install.sh status        # état de la tâche, configuration, dernières lignes du journal
tail -f ~/.local/share/claude-code-remote-control/server.log
```

## Désinstallation (une seule commande)

```bash
./uninstall.sh                       # supprime la tâche, le script, la configuration et les journaux
./uninstall.sh --keep-logs           # conserve les journaux
# sans cloner le dépôt :
curl -fsSL https://raw.githubusercontent.com/sicaboy/claude-code-remote-control-launchd/main/install.sh | bash -s -- uninstall
```

La désinstallation arrête le serveur et les sessions qu'il prend en charge.

## Fonctionnement

`~/Library/LaunchAgents/io.github.sicaboy.claude-code-remote-control.plist` exécute `claude-code-remote-control.sh` avec `RunAtLoad` et `KeepAlive`. À chaque cycle, le script :

1. attend le réseau (2 min au maximum) ;
2. vérifie `claude auth status` ; si vous êtes déconnecté, il consigne la solution et attend 5 min au lieu d'insister ;
3. applique un délai après 3 démarrages en une heure (5 min par démarrage supplémentaire, 30 au maximum), pour qu'un serveur défaillant ne tourne pas en boucle et ne laisse pas d'appareils fantômes sur le téléphone ;
4. exécute `claude remote-control --spawn <mode> --capacity <n> --name <nom>` dans votre dossier de travail ;
5. considère le serveur bloqué s'il n'y a pas de connexion HTTPS établie en 150 s (par exemple, une invite de premier lancement invisible) et le relance ;
6. écrit un signal de vie toutes les 5 min et, à l'arrêt du serveur, le code de sortie et les dernières lignes de sortie.

Il commence par supprimer les variables héritées `CLAUDE*`, `ANTHROPIC_API_KEY` et `ANTHROPIC_AUTH_TOKEN`, afin de ne jamais reprendre l'identité d'une autre session.

Tout se trouve dans `~/.local/share/claude-code-remote-control/`. Dans Réglages Système > Général > Éléments de connexion et extensions, l'élément apparaît sous le nom `claude-code-remote-control.sh` (et non un simple `bash`).

## Limites et remarques

- **Veille.** Un Mac en veille est injoignable. Utilisez `--keep-awake` (il exécute `caffeinate -s` uniquement tant que le serveur tourne, et n'aide que sur secteur) ou gérez-le vous-même dans les réglages d'énergie. Cet outil ne modifie jamais les réglages d'énergie du système. Le comportement écran fermé n'est pas vérifié.
- **Connexion nécessaire après un redémarrage.** Un LaunchAgent s'exécute dans une session ouverte ; avec FileVault et sans ouverture de session automatique, connectez-vous une fois après un redémarrage.
- **Expiration de la connexion.** Renouvelez-la avec `claude auth login` à l'expiration. Le journal indique la date d'expiration à chaque démarrage.
- **Un redémarrage termine les sessions.** Redémarrer le serveur (ou relancer `install.sh`, ou désinstaller) arrête les sessions qu'il prend en charge. Les transcriptions restent sur le disque.
- Il s'appuie sur le comportement de `claude remote-control` dans les versions actuelles de Claude Code ; les options peuvent changer.

## FAQ

### Comment garder Claude Code Remote Control actif en permanence sur un Mac ?

Installez ce LaunchAgent. Il exécute `claude remote-control` en arrière-plan, le démarre à l'ouverture de session et le relance quand il s'arrête : votre Mac reste disponible comme appareil dans l'app Claude.

### `claude remote-control` continue-t-il de tourner après la fermeture du terminal ou un redémarrage ?

Pas tout seul : c'est un processus d'avant-plan qui abandonne après environ 10 minutes sans réseau. Sous launchd, il est relancé automatiquement et démarre à chaque ouverture de session. Après un redémarrage avec FileVault, il faut se connecter une fois.

### Pourquoi les nouvelles sessions créées depuis mon téléphone ne répondent-elles pas ?

Le serveur est probablement plein : les sessions inactives gardent leur place. Consultez `Capacity: n/N` dans `server.out`, terminez les sessions inactives ou réinstallez avec un `--capacity` plus grand.

### Le Mac doit-il rester éveillé ?

Oui, un Mac en veille est injoignable. Installez avec `--keep-awake` pour maintenir `caffeinate -s` tant que le serveur tourne (sur secteur uniquement), ou réglez-le dans les réglages d'énergie.

### Comment le désinstaller ?

Lancez `./uninstall.sh`, ou la commande curl avec `uninstall`. Elle supprime le LaunchAgent, le script, la configuration et les journaux.

## Développement

```bash
bash test/test.sh      # smoke tests against a fake `claude`, no network
shellcheck -x -S warning install.sh scripts/claude-code-remote-control.sh test/test.sh
```

## Licence

[MIT](LICENSE)
