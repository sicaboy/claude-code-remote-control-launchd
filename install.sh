#!/bin/bash
# claude-code-remote-control installer: keep `claude remote-control` running on this Mac via a LaunchAgent.
#
#   ./install.sh [install] [--workdir DIR] [--name NAME] [--capacity N] [--spawn same-dir|worktree] [--keep-awake]
#   ./install.sh status
#   ./install.sh uninstall [--keep-logs]
#
# One-liner (no clone needed):
#   curl -fsSL https://raw.githubusercontent.com/sicaboy/claude-code-remote-control-launchd/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/sicaboy/claude-code-remote-control-launchd/main/install.sh | bash -s -- uninstall
set -u

REPO="sicaboy/claude-code-remote-control-launchd"
REF="${CLAUDE_RC_REF:-main}"
LABEL="io.github.sicaboy.claude-code-remote-control"
STATE_DIR="$HOME/.local/share/claude-code-remote-control"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SERVER="$STATE_DIR/claude-code-remote-control.sh"
DOMAIN="gui/$(id -u)"

say()  { printf '%s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

cmd="install"
case "${1:-}" in
  install|uninstall|status) cmd="$1"; shift ;;
  -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

WORKDIR="" NAME="" CAPACITY="10" SPAWN="same-dir" KEEP_LOGS=0 KEEP_AWAKE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --workdir)   WORKDIR="${2:-}"; shift 2 ;;
    --name)      NAME="${2:-}"; shift 2 ;;
    --capacity)  CAPACITY="${2:-}"; shift 2 ;;
    --spawn)     SPAWN="${2:-}"; shift 2 ;;
    --keep-logs) KEEP_LOGS=1; shift ;;
    --keep-awake) KEEP_AWAKE=1; shift ;;
    -h|--help)   sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
done

[ "$(uname -s)" = "Darwin" ] || die "macOS only (it uses launchd)."
[ "$(id -u)" -ne 0 ] || die "do not run as root; it installs a per-user LaunchAgent."

job_loaded() { launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; }
wait_unloaded() { local i=0; while job_loaded && [ "$i" -lt 60 ]; do sleep 1; i=$((i + 1)); done; }

do_status() {
  if job_loaded; then
    say "launchd job: loaded ($LABEL)"
    launchctl print "$DOMAIN/$LABEL" | grep -E '^\s*(state|pid|last exit code) =' | sed 's/^\s*/  /'
  else
    say "launchd job: not loaded"
  fi
  [ -f "$STATE_DIR/config.env" ] && { say "config:"; sed 's/^/  /' "$STATE_DIR/config.env"; }
  if [ -f "$STATE_DIR/server.log" ]; then say "last log lines ($STATE_DIR/server.log):"; tail -n 5 "$STATE_DIR/server.log" | sed 's/^/  /'; fi
}

do_uninstall() {
  if job_loaded; then
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null
    wait_unloaded
  fi
  rm -f "$PLIST"
  if [ "$KEEP_LOGS" = 1 ]; then
    rm -f "$SERVER" "$STATE_DIR/config.env"
    say "Removed the LaunchAgent and script. Logs kept in $STATE_DIR"
  else
    [ "$STATE_DIR" = "$HOME/.local/share/claude-code-remote-control" ] && rm -rf "$STATE_DIR"
    say "Removed the LaunchAgent, script, config and logs."
  fi
  say "Any running 'claude remote-control' server was stopped; this Mac leaves the Devices list shortly."
}

do_install() {
  case "$SPAWN" in same-dir|worktree) ;; *) die "--spawn must be same-dir or worktree" ;; esac
  case "$CAPACITY" in ''|*[!0-9]*) die "--capacity must be a positive integer" ;; esac
  [ "$CAPACITY" -ge 1 ] || die "--capacity must be at least 1"

  CLAUDE_BIN="$(command -v claude 2>/dev/null || true)"
  [ -n "$CLAUDE_BIN" ] || [ ! -x "$HOME/.local/bin/claude" ] || CLAUDE_BIN="$HOME/.local/bin/claude"
  [ -n "$CLAUDE_BIN" ] || die "Claude Code ('claude') not found. Install it first: https://code.claude.com/docs"

  [ -n "$WORKDIR" ] || WORKDIR="$HOME/claude-rc"
  case "$WORKDIR" in "~"*) WORKDIR="$HOME${WORKDIR#\~}" ;; esac
  mkdir -p "$WORKDIR" || die "cannot create $WORKDIR"
  WORKDIR="$(cd "$WORKDIR" && pwd -P)"
  [ "$WORKDIR" != "$HOME" ] || die "do not use your home directory: Claude Code never saves trust for it. Pick a project folder."
  case "$WORKDIR$NAME" in *[\<\>\&\"\'\$\`\\]*) die "workdir and name must not contain < > & \" ' \$ \` or backslash" ;; esac
  [ -n "$NAME" ] || NAME="$(scutil --get ComputerName 2>/dev/null || hostname -s)"
  case "$NAME" in *[\<\>\&\"\'\$\`\\]*) die "name must not contain < > & \" ' \$ \` or backslash" ;; esac

  # signed in? (Remote Control needs a claude.ai login, not an API key)
  if status_json="$(env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN "$CLAUDE_BIN" auth status 2>/dev/null)"; then
    case "$status_json" in *'"loggedIn": false'*|*'"loggedIn":false'*) die "Claude Code is signed out. Run: claude auth login" ;; esac
  fi

  # trusted directory? A non-TTY server exits with "Workspace not trusted" otherwise.
  if command -v python3 >/dev/null 2>&1; then
    trusted="$(WD="$WORKDIR" python3 -I -c '
import json, os
try:
    d = json.load(open(os.path.expanduser("~/.claude.json")))
    print("yes" if d.get("projects", {}).get(os.environ["WD"], {}).get("hasTrustDialogAccepted") else "no")
except Exception:
    print("unknown")' 2>/dev/null)"
    if [ "$trusted" = "no" ]; then
      die "$WORKDIR is not trusted by Claude Code yet. Run once, accept the trust prompt, then re-run this installer:
    cd '$WORKDIR' && claude"
    fi
  fi

  # fetch the server script (from this checkout, or from GitHub for the curl | bash route)
  mkdir -p "$STATE_DIR" "$HOME/Library/LaunchAgents"
  chmod 700 "$STATE_DIR"
  src_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
  if [ -f "$src_dir/scripts/claude-code-remote-control.sh" ]; then
    cp "$src_dir/scripts/claude-code-remote-control.sh" "$SERVER.new"
  else
    curl -fsSL "https://raw.githubusercontent.com/$REPO/$REF/scripts/claude-code-remote-control.sh" -o "$SERVER.new" \
      || die "could not download the server script for ref '$REF'"
  fi
  head -n1 "$SERVER.new" | grep -q '^#!/bin/bash' || die "downloaded server script looks wrong; aborting"
  chmod 755 "$SERVER.new" && mv "$SERVER.new" "$SERVER"

  cat > "$STATE_DIR/config.env" <<EOF
RC_CLAUDE_BIN='$CLAUDE_BIN'
RC_WORKDIR='$WORKDIR'
RC_NAME='$NAME'
RC_CAPACITY='$CAPACITY'
RC_SPAWN='$SPAWN'
RC_KEEP_AWAKE='$KEEP_AWAKE'
EOF

  # the program is the script itself, so Login Items shows "claude-code-remote-control.sh" rather than "bash"
  cat > "$PLIST.new" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$SERVER</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>ThrottleInterval</key>
	<integer>30</integer>
	<key>ExitTimeOut</key>
	<integer>20</integer>
	<key>StandardOutPath</key>
	<string>$STATE_DIR/launchd.log</string>
	<key>StandardErrorPath</key>
	<string>$STATE_DIR/launchd.log</string>
</dict>
</plist>
EOF
  plutil -lint "$PLIST.new" >/dev/null || die "generated plist is invalid"
  mv "$PLIST.new" "$PLIST"

  if job_loaded; then launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null; wait_unloaded; fi
  skip_lines="$(wc -l < "$STATE_DIR/server.log" 2>/dev/null || echo 0)"   # only look at log lines written from now on
  boot_err=""
  for _ in 1 2 3 4 5 6; do   # bootout can return before the old job is gone
    if boot_err="$(launchctl bootstrap "$DOMAIN" "$PLIST" 2>&1)"; then boot_err=""; break; fi
    sleep 5
  done
  [ -z "$boot_err" ] || die "launchctl bootstrap failed: $boot_err"

  say "Installed. Waiting for the server to register (up to 60 s)..."
  i=0
  while [ "$i" -lt 60 ]; do
    if tail -n +"$((skip_lines + 1))" "$STATE_DIR/server.log" 2>/dev/null | grep -q 'registered:'; then
      say "Up: this Mac should now appear as \"$NAME\" in the Claude app's Code tab / claude.ai/code."
      say "Status: ./install.sh status   Logs: $STATE_DIR/server.log   Remove: ./install.sh uninstall"
      return 0
    fi
    sleep 2; i=$((i + 2))
  done
  say "Installed, but not registered yet. Check: tail $STATE_DIR/server.log"
  say "Common cause: signed out (claude auth login) or an untrusted workdir (cd '$WORKDIR' && claude)."
}

case "$cmd" in
  install)   do_install ;;
  uninstall) do_uninstall ;;
  status)    do_status ;;
esac
