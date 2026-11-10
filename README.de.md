<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português</a> · <a href="README.fr.md">Français</a> · <b>Deutsch</b> · <a href="README.ru.md">Русский</a></p>

<p align="center"><img src="assets/banner.svg" alt="Claude Code Remote Control für macOS: dauerhaft laufender Hintergrunddienst über launchd" width="100%"></p>

<p align="center">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-green.svg"></a>
  <a href="https://github.com/sicaboy/claude-code-remote-control-launchd/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/sicaboy/claude-code-remote-control-launchd/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="Platform: macOS" src="https://img.shields.io/badge/platform-macOS-lightgrey.svg">
  <img alt="Shell: bash" src="https://img.shields.io/badge/shell-bash-4EAA25.svg">
  <img alt="Open source" src="https://img.shields.io/badge/open%20source-%E2%9D%A4-orange.svg">
  <a href="https://github.com/sicaboy/claude-code-remote-control-launchd/pulls"><img alt="PRs welcome" src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg"></a>
</p>

# Claude Code Remote Control for macOS

Führt **Remote Control** von [Claude Code](https://code.claude.com) (`claude remote-control`) als dauerhaft laufenden macOS-Hintergrunddienst aus (launchd-LaunchAgent). Ihr Mac erscheint als **Gerätekarte** im Code-Tab der Claude-App (und auf claude.ai/code), sodass Sie jederzeit vom Smartphone aus neue, unabhängige Sitzungen starten können – ohne ein offenes Terminal.

Es besteht aus einem kleinen LaunchAgent und einem Überwachungsskript. Es startet bei der Anmeldung, startet den Server neu, wenn er endet, und verhindert endlose Neustart-Schleifen.

> Inoffizielles Community-Projekt, weder mit Anthropic verbunden noch von Anthropic unterstützt.

## Installation (ein Befehl)

```bash
curl -fsSL https://raw.githubusercontent.com/sicaboy/claude-code-remote-control-launchd/main/install.sh | bash -s -- --workdir ~/projects --name "My Mac"
```

oder aus einem Klon des Repositorys:

```bash
git clone https://github.com/sicaboy/claude-code-remote-control-launchd && cd claude-code-remote-control-launchd
./install.sh --workdir ~/projects --name "My Mac"
```

| Option | Standard | Bedeutung |
| --- | --- | --- |
| `--workdir DIR` | `~/claude-rc` | Verzeichnis, in dem Sitzungen starten. Muss von Claude Code als **vertrauenswürdig** eingestuft sein (siehe unten). Nicht Ihr Home-Verzeichnis. |
| `--name NAME` | der Name des Macs | In der App angezeigter Gerätename |
| `--capacity N` | `10` | Maximale Zahl gleichzeitiger Sitzungen. Inaktive Sitzungen behalten ihren Platz; ist der Server voll, werden neue Sitzungen stillschweigend ignoriert. |
| `--spawn MODE` | `same-dir` | `same-dir` (gemeinsame Dateien) oder `worktree` (benötigt ein Git-Repository) |
| `--keep-awake` | aus | Hält `caffeinate -s`, solange der Server läuft, damit der Mac am Netzteil nicht in den Ruhezustand wechselt. Ändert keine Energieeinstellung des Systems. |

Ein erneuter Aufruf von `install.sh` mit neuen Optionen aktualisiert die Installation an Ort und Stelle.

**Vor der Installation:** Sie müssen angemeldet sein (`claude auth login`, mit einem claude.ai-Konto; API-Schlüssel funktionieren mit Remote Control nicht), und das Arbeitsverzeichnis muss einmal als vertrauenswürdig bestätigt werden: `cd ~/projects && claude` und die Abfrage akzeptieren. Das Installationsskript prüft beides und sagt Ihnen, was zu tun ist.

## Alltägliche Nutzung

```bash
./install.sh status        # Job-Status, Konfiguration, letzte Logzeilen
tail -f ~/.local/share/claude-code-remote-control/server.log
```

## Deinstallation (ein Befehl)

```bash
./uninstall.sh                       # entfernt Job, Skript, Konfiguration und Logs
./uninstall.sh --keep-logs           # Logs behalten
# ohne Klon:
curl -fsSL https://raw.githubusercontent.com/sicaboy/claude-code-remote-control-launchd/main/install.sh | bash -s -- uninstall
```

Die Deinstallation stoppt den Server und die Sitzungen, die er bedient.

## Funktionsweise

`~/Library/LaunchAgents/io.github.sicaboy.claude-code-remote-control.plist` führt `claude-code-remote-control.sh` mit `RunAtLoad` und `KeepAlive` aus. In jedem Zyklus macht das Skript Folgendes:

1. wartet auf das Netzwerk (bis zu 2 Min.);
2. prüft `claude auth status`; ist man abgemeldet, protokolliert es die Lösung und wartet 5 Min., statt ständig zu wiederholen;
3. bremst nach 3 Starts pro Stunde aus (5 Min. je weiterem Start, höchstens 30), damit ein defekter Server nicht endlos neu startet und Geistergeräte auf dem Smartphone hinterlässt;
4. führt `claude remote-control --spawn <Modus> --capacity <n> --name <Name>` in Ihrem Arbeitsverzeichnis aus;
5. wertet es als hängend, wenn innerhalb von 150 s keine HTTPS-Verbindung zustande kommt (z. B. wegen einer unsichtbaren Erststart-Abfrage), und startet neu;
6. schreibt alle 5 Min. einen Heartbeat und beim Beenden des Servers den Exit-Code samt den letzten Ausgabezeilen ins Log.

Zuerst entfernt es geerbte Variablen `CLAUDE*`, `ANTHROPIC_API_KEY` und `ANTHROPIC_AUTH_TOKEN`, damit nie die Identität einer anderen Sitzung übernommen wird.

Alles liegt in `~/.local/share/claude-code-remote-control/`. In den Systemeinstellungen unter Allgemein > Anmeldeobjekte & Erweiterungen erscheint der Eintrag als `claude-code-remote-control.sh` (nicht als schlichtes `bash`).

## Grenzen und Hinweise

- **Ruhezustand.** Ein schlafender Mac ist nicht erreichbar. Nutzen Sie `--keep-awake` (führt `caffeinate -s` nur aus, solange der Server läuft, und hilft nur am Netzteil) oder steuern Sie es selbst in den Energieeinstellungen. Dieses Werkzeug ändert nie die Energieeinstellungen des Systems. Das Verhalten bei geschlossenem Deckel ist nicht überprüft.
- **Anmeldung nach Neustart nötig.** Ein LaunchAgent läuft innerhalb einer angemeldeten Sitzung; mit FileVault und ohne automatische Anmeldung müssen Sie sich nach einem Neustart einmal anmelden.
- **Ablauf der Anmeldung.** Erneuern Sie sie bei Ablauf mit `claude auth login`. Das Log zeigt bei jedem Start das Ablaufdatum.
- **Neustarts beenden Sitzungen.** Ein Neustart des Servers (oder erneutes `install.sh`, oder Deinstallation) stoppt die Sitzungen, die er bedient. Die Verläufe bleiben auf der Festplatte.
- Es stützt sich auf das Verhalten von `claude remote-control` in aktuellen Claude-Code-Versionen; Optionen können sich ändern.

## Häufige Fragen

### Wie halte ich Claude Code Remote Control auf einem Mac dauerhaft am Laufen?

Installieren Sie diesen LaunchAgent. Er führt `claude remote-control` im Hintergrund aus, startet es bei der Anmeldung und startet es neu, wenn es endet – so bleibt Ihr Mac als Gerät in der Claude-App verfügbar.

### Läuft `claude remote-control` weiter, wenn ich das Terminal schließe oder neu starte?

Von allein nicht: Es ist ein Vordergrundprozess und gibt nach etwa 10 Minuten ohne Netzwerk auf. Unter launchd wird es automatisch neu gestartet und startet bei jeder Anmeldung. Nach einem Neustart mit FileVault müssen Sie sich einmal anmelden.

### Warum antworten neue Sitzungen vom Smartphone nicht?

Wahrscheinlich ist der Server voll: Inaktive Sitzungen behalten ihren Platz. Prüfen Sie `Capacity: n/N` in `server.out`, beenden Sie inaktive Sitzungen oder installieren Sie mit größerem `--capacity` neu.

### Muss der Mac wach bleiben?

Ja, ein schlafender Mac ist nicht erreichbar. Installieren Sie mit `--keep-awake`, um `caffeinate -s` zu halten, solange der Server läuft (nur am Netzteil), oder richten Sie es in den Energieeinstellungen ein.

### Wie deinstalliere ich es?

Führen Sie `./uninstall.sh` aus oder den curl-Einzeiler mit `uninstall`. Er entfernt LaunchAgent, Skript, Konfiguration und Logs.

## Entwicklung

```bash
bash test/test.sh      # smoke tests against a fake `claude`, no network
shellcheck -x -S warning install.sh scripts/claude-code-remote-control.sh test/test.sh
```

## Lizenz

[MIT](LICENSE)
