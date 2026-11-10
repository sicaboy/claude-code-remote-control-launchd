<p align="center"><b>English</b> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.ru.md">Русский</a></p>

<p align="center"><img src="assets/banner.svg" alt="Claude Code Remote Control for macOS: always-on background service via launchd" width="100%"></p>

<p align="center">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-green.svg"></a>
  <a href="https://github.com/sicaboy/claude-code-remote-control-launchd/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/sicaboy/claude-code-remote-control-launchd/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="Platform: macOS" src="https://img.shields.io/badge/platform-macOS-lightgrey.svg">
  <img alt="Shell: bash" src="https://img.shields.io/badge/shell-bash-4EAA25.svg">
  <img alt="Open source" src="https://img.shields.io/badge/open%20source-%E2%9D%A4-orange.svg">
  <a href="https://github.com/sicaboy/claude-code-remote-control-launchd/pulls"><img alt="PRs welcome" src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg"></a>
</p>

# Claude Code Remote Control for macOS

Run [Claude Code](https://code.claude.com) **Remote Control** (`claude remote-control`) as an always-on macOS background service (launchd LaunchAgent). Your Mac shows up as a **device card** in the Claude app's Code tab (and on claude.ai/code), so you can start new, independent sessions on it from your phone at any time, without leaving a terminal open.

It is a small LaunchAgent plus a supervisor script. It starts at login, restarts the server when it exits, and refuses to flap.

> Unofficial community project, not affiliated with or endorsed by Anthropic.

## Install (one command)

```bash
curl -fsSL https://raw.githubusercontent.com/sicaboy/claude-code-remote-control-launchd/main/install.sh | bash -s -- --workdir ~/projects --name "My Mac"
```

or from a clone:

```bash
git clone https://github.com/sicaboy/claude-code-remote-control-launchd && cd claude-code-remote-control-launchd
./install.sh --workdir ~/projects --name "My Mac"
```

| Option | Default | Meaning |
| --- | --- | --- |
| `--workdir DIR` | `~/claude-rc` | Directory sessions start in. Must be **trusted** by Claude Code (see below). Not your home directory. |
| `--name NAME` | the Mac's name | Device name shown in the app |
| `--capacity N` | `10` | Max concurrent sessions. Idle sessions keep their slot, so a full server silently ignores new ones. |
| `--spawn MODE` | `same-dir` | `same-dir` (shared files) or `worktree` (needs a git repo) |
| `--keep-awake` | off | Hold `caffeinate -s` while the server runs, so the Mac does not sleep on AC power. Does not change any system power setting. |

Re-running `install.sh` with new options updates the installation in place.

**Before you install:** be signed in (`claude auth login`, a claude.ai account; API keys do not work for Remote Control), and trust the work directory once: `cd ~/projects && claude`, accept the prompt. The installer checks both and tells you what to do.

## Everyday use

```bash
./install.sh status        # job state, config, last log lines
tail -f ~/.local/share/claude-code-remote-control/server.log
```

## Uninstall (one command)

```bash
./uninstall.sh                       # remove job, script, config and logs
./uninstall.sh --keep-logs           # keep the logs
# without a clone:
curl -fsSL https://raw.githubusercontent.com/sicaboy/claude-code-remote-control-launchd/main/install.sh | bash -s -- uninstall
```

Uninstalling stops the server and the sessions it is serving.

## How it works

`~/Library/LaunchAgents/io.github.sicaboy.claude-code-remote-control.plist` runs `claude-code-remote-control.sh` with `RunAtLoad` and `KeepAlive`. Each cycle the script:

1. waits for the network (up to 2 min);
2. checks `claude auth status`; if signed out it logs the fix and holds 5 min instead of hammering;
3. backs off after 3 starts in an hour (5 min per extra start, max 30), so a broken server cannot flap and leave ghost devices on your phone;
4. runs `claude remote-control --spawn <mode> --capacity <n> --name <name>` in your work directory;
5. treats "no established HTTPS connection within 150 s" as stuck (for example an invisible first-run prompt) and restarts it;
6. logs a heartbeat every 5 min, and logs the exit code and last output lines when the server exits.

It scrubs inherited `CLAUDE*`, `ANTHROPIC_API_KEY` and `ANTHROPIC_AUTH_TOKEN` variables first, so it never picks up another session's identity.

Everything lives in `~/.local/share/claude-code-remote-control/`. In System Settings > General > Login Items & Extensions the item appears as `claude-code-remote-control.sh` (not a bare `bash`).

## Limits and notes

- **Sleep.** A sleeping Mac is not reachable. Use `--keep-awake` (it runs `caffeinate -s` only while the server runs, and only helps on AC power), or manage it yourself in Energy settings. This tool never changes system power settings. Lid-closed behaviour is not verified.
- **Login needed after reboot.** A LaunchAgent runs inside a logged-in session; with FileVault and no auto-login, log in once after a reboot.
- **Sign-in expiry.** Renew with `claude auth login` when it expires. The log shows the expiry date at each start.
- **Restarts end sessions.** Restarting the server (or re-running `install.sh`, or uninstalling) stops the sessions it serves. Transcripts stay on disk.
- It relies on `claude remote-control` behaviour in current Claude Code releases; flags may change.

## FAQ

### How do I keep Claude Code Remote Control running all the time on a Mac?

Install this LaunchAgent. It runs `claude remote-control` in the background, starts it at login and restarts it when it exits, so your Mac stays available as a device in the Claude app.

### Does `claude remote-control` keep running after I close the terminal or reboot?

Not by itself: it is a foreground process and gives up after about 10 minutes without a network. Under launchd it is restarted automatically and starts at every login. After a reboot with FileVault you must log in once.

### Why do new sessions from my phone get no reply?

The server is probably at capacity: idle sessions keep their slot. Check `Capacity: n/N` in `server.out`, end idle sessions, or install with a higher `--capacity`.

### Does the Mac have to stay awake?

Yes, a sleeping Mac cannot be reached. Install with `--keep-awake` to hold `caffeinate -s` while the server runs (AC power only), or set it up in Energy settings.

### How do I uninstall it?

Run `./uninstall.sh`, or the curl one-liner with `uninstall`. It removes the LaunchAgent, script, config and logs.

## Development

```bash
bash test/test.sh      # smoke tests against a fake `claude`, no network
shellcheck -x -S warning install.sh scripts/claude-code-remote-control.sh test/test.sh
```

## License

[MIT](LICENSE)
