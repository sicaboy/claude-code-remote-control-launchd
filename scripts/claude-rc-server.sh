#!/bin/bash
# claude-rc-server.sh - run `claude remote-control` (server mode) so this Mac shows up as a device
# card at the top of the Claude app's Code tab and the phone / claude.ai/code can start new,
# independent sessions here. Run by the launchd job installed by claude-rc-launchd
# (RunAtLoad + KeepAlive). It runs ONE server cycle and exits when the server exits; launchd then
# restarts it (ThrottleInterval 30 s).
#
# Where it shows up / how to trace it:
#   System Settings > General > Login Items & Extensions > "Allow in the Background": an entry
#   named after this file (claude-rc-server.sh); its magnifier button reveals this file.
#   log, one line per event: <state dir>/server.log
#
#   no network ................ wait up to ~2 min, then exit (launchd retries)
#   signed out ................ hold 5 min, log the fix (`claude auth login`), then exit
#   >= 3 starts in the last hour  back off 5 min per extra start (max 30 min), so a broken server
#                                 cannot flap and leave ghost devices on the phone
#   server up, but no established :443 connection within 150 s
#                                 treated as stuck (e.g. an invisible first-run prompt): stop it,
#                                 log why, exit
#   server exits .............. log exit code and the last output lines, exit (launchd restarts)
#
# Settings come from <state dir>/config.env (written by install.sh):
#   RC_CLAUDE_BIN  path to the claude binary      RC_WORKDIR   trusted directory to serve
#   RC_NAME        device name shown in the app    RC_CAPACITY  max concurrent sessions
#   RC_SPAWN       same-dir | worktree
# Test hooks (env): RC_STATE_DIR RC_SKIP_NET RC_NET_URL RC_NET_WAIT RC_CONN_PORT RC_REG_WAIT
#                   RC_POLL RC_HOLD RC_BACKOFF_UNIT

# Never inherit another Claude Code session's identity (bridge / messaging variables), and Remote
# Control does not work with API-key auth. Only variable NAMES are read here.
for v in $(env | sed -n 's/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
umask 077
DIR="${RC_STATE_DIR:-$HOME/.local/share/claude-rc-launchd}"
# shellcheck disable=SC1091
[ -f "$DIR/config.env" ] && . "$DIR/config.env"
CLAUDE="${RC_CLAUDE_BIN:-$HOME/.local/bin/claude}"
WORKDIR="${RC_WORKDIR:-$HOME}"
NAME="${RC_NAME:-$(scutil --get ComputerName 2>/dev/null || hostname -s)}"
CAPACITY="${RC_CAPACITY:-10}"
SPAWN="${RC_SPAWN:-same-dir}"
LOG="$DIR/server.log"
OUT="$DIR/server.out"
STARTS="$DIR/server-starts.epoch"
NET_WAIT="${RC_NET_WAIT:-120}"
REG_WAIT="${RC_REG_WAIT:-150}"
POLL="${RC_POLL:-5}"
CONN_PORT="${RC_CONN_PORT:-443}"
HOLD="${RC_HOLD:-300}"
UNIT="${RC_BACKOFF_UNIT:-300}"

mkdir -p "$DIR"
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S%z')" "$*" >> "$LOG"; }
if [ -f "$LOG" ] && [ "$(wc -l < "$LOG")" -gt 800 ]; then
  tail -n 400 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

# run_to SECONDS CMD... : run with a time limit (macOS has no `timeout`)
run_to() {
  local limit="$1" pid watcher rc
  shift
  "$@" < /dev/null &
  pid=$!
  ( i=0; while [ "$i" -lt "$limit" ]; do sleep 1; kill -0 "$pid" 2>/dev/null || exit 0; i=$((i + 1)); done
    kill "$pid" 2>/dev/null ) > /dev/null 2>&1 &
  watcher=$!
  wait "$pid" 2>/dev/null
  rc=$?
  wait "$watcher" 2>/dev/null
  return "$rc"
}

tail_out() { tail -n 5 "$OUT" 2>/dev/null | tr '\n' '|' | cut -c1-400; }

cd "$WORKDIR" 2>/dev/null || { log "HOLD: workdir $WORKDIR is missing; retrying in ${HOLD}s"; sleep "$HOLD"; exit 1; }

# 1. network
net_ok() {
  [ "${RC_SKIP_NET:-0}" = 1 ] && return 0
  curl -s -o /dev/null -m 8 "${RC_NET_URL:-https://api.anthropic.com/}"
}
waited=0
until net_ok; do
  waited=$((waited + 5))
  if [ "$waited" -ge "$NET_WAIT" ]; then
    log "no network for ${NET_WAIT}s; exiting so launchd retries"
    exit 0
  fi
  sleep 5
done

# 2. signed in? (a parse failure is not treated as signed out, to avoid a self-inflicted outage)
st=$(run_to 30 "$CLAUDE" auth status 2>/dev/null)
li=$(printf '%s' "$st" | python3 -I -c '
import sys, json
try:
    d = json.load(sys.stdin)
    print("%s %s" % ("yes" if d.get("loggedIn") else "no", d.get("loginExpiresAt") or "-"))
except Exception:
    print("unknown -")' 2>/dev/null)
case "$li" in
  no*)
    log "HOLD: signed out ('claude auth status' says loggedIn=false). Fix: run 'claude auth login'. Retrying in ${HOLD}s"
    sleep "$HOLD"
    exit 0
    ;;
esac

# 3. restart guard
now=$(date +%s)
recent=$(awk -v n="$now" 'n - $1 < 3600' "$STARTS" 2>/dev/null | wc -l | tr -d ' ')
if [ "${recent:-0}" -ge 3 ]; then
  pause=$((UNIT * (recent - 2)))
  [ "$pause" -gt 1800 ] && pause=1800
  log "BACKOFF: $recent starts in the last hour; waiting ${pause}s before the next one"
  sleep "$pause"
fi
printf '%s\n' "$(date +%s)" >> "$STARTS"
tail -n 20 "$STARTS" > "$STARTS.tmp" && mv "$STARTS.tmp" "$STARTS"

# 4. start the server (stdout is block-buffered when not a terminal, so $OUT can lag behind)
tree() { local p="$1" k; echo "$p"; for k in $(pgrep -P "$p" 2>/dev/null); do tree "$k"; done; }
has_conn() {
  local pl
  pl=$(tree "$pid" | paste -sd, -)
  [ -n "$pl" ] || return 1
  lsof -nP -a -p "$pl" -iTCP -sTCP:ESTABLISHED 2>/dev/null | grep -Eq -- "->[^ ]+:${CONN_PORT} \(ESTABLISHED\)"
}
stop_server() {
  local all i=0
  all=$(tree "$pid" | tr '\n' ' ')
  # shellcheck disable=SC2086
  kill $all 2>/dev/null
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 10 ]; do sleep 1; i=$((i + 1)); done
  # shellcheck disable=SC2086
  kill -9 $all 2>/dev/null
}

: > "$OUT"
log "start: claude remote-control --spawn $SPAWN --capacity $CAPACITY --name '$NAME' (cwd $PWD; signed in/expires: ${li:-unknown})"
"$CLAUDE" remote-control --spawn "$SPAWN" --capacity "$CAPACITY" --name "$NAME" < /dev/null >> "$OUT" 2>&1 &
pid=$!
t0=$(date +%s)
trap 'log "signal received; stopping server pid=$pid"; stop_server; exit 0' TERM INT HUP

# 5. wait until the server holds an established connection to the API
registered=0
while kill -0 "$pid" 2>/dev/null; do
  if has_conn; then registered=1; break; fi
  [ $(( $(date +%s) - t0 )) -ge "$REG_WAIT" ] && break
  sleep "$POLL"
done
if ! kill -0 "$pid" 2>/dev/null; then
  wait "$pid" 2>/dev/null; rc=$?
  log "EXIT before registering: rc=$rc after $(( $(date +%s) - t0 ))s; last output: $(tail_out)"
  exit 0
fi
if [ "$registered" = 0 ]; then
  log "STUCK: no established :${CONN_PORT} connection within ${REG_WAIT}s (invisible first-run prompt?). Stopping it; last output: $(tail_out)"
  stop_server
  exit 0
fi
log "registered: server pid=$pid holds an established :${CONN_PORT} connection after $(( $(date +%s) - t0 ))s"

# 6. supervise until it exits; heartbeat every 5 min, keep the output file small
hb=$(date +%s)
while kill -0 "$pid" 2>/dev/null; do
  sleep "$POLL"
  if [ $(( $(date +%s) - hb )) -ge 300 ]; then
    hb=$(date +%s)
    if has_conn; then c=yes; else c=no; fi
    log "alive: pid=$pid up=$(( hb - t0 ))s procs=$(tree "$pid" | wc -l | tr -d ' ') api_conn=$c"
    if [ "$(wc -c < "$OUT" 2>/dev/null || echo 0)" -gt 5000000 ]; then : > "$OUT"; fi
  fi
done
wait "$pid" 2>/dev/null; rc=$?
log "server exited: rc=$rc after $(( $(date +%s) - t0 ))s; last output: $(tail_out)"
exit 0
