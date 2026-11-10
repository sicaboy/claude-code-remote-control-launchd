#!/bin/bash
# Smoke tests for scripts/claude-code-remote-control.sh against a fake `claude`. No network, no real Claude.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER="$ROOT/scripts/claude-code-remote-control.sh"
T="$(mktemp -d)"
trap 'kill $(jobs -p) $LISTENER 2>/dev/null; rm -rf "$T"' EXIT
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

mkfake() { # mkfake MODE -> fake claude in $T/claude
  cat > "$T/claude" <<EOF
#!/bin/bash
case "\$1" in
  auth) echo '{"loggedIn": ${LOGGED_IN:-true}, "loginExpiresAt": "2099-01-01T00:00:00Z"}' ;;
  remote-control)
    case "$1" in
      exit)    echo "boom"; exit 3 ;;
      hang)    sleep 60 ;;
      connect) python3 -I -c "import socket,time; s=socket.create_connection(('127.0.0.1',\${RC_CONN_PORT})); time.sleep(60)" ;;
    esac ;;
esac
EOF
  chmod +x "$T/claude"
}
run() { # run STATE_NAME ... -> runs the server with test hooks, state in $T/<name>
  local n="$1"; shift
  mkdir -p "$T/$n/work"
  printf "RC_CLAUDE_BIN='%s'\nRC_WORKDIR='%s'\nRC_NAME='t'\nRC_CAPACITY='3'\n" "$T/claude" "$T/$n/work" > "$T/$n/config.env"
  env RC_STATE_DIR="$T/$n" RC_SKIP_NET=1 RC_POLL=1 "$@" bash "$SERVER"
}

mkfake exit
run exit RC_REG_WAIT=10 >/dev/null 2>&1
grep -q 'EXIT before registering: rc=3' "$T/exit/server.log" && ok "exit before registering is logged" || bad "exit path"
grep -q "capacity 3 --name 't'" "$T/exit/server.log" && ok "config.env is honoured" || bad "config"

mkfake hang
run hang RC_REG_WAIT=3 >/dev/null 2>&1
grep -q 'STUCK' "$T/hang/server.log" && ok "stuck server is detected" || bad "stuck path"

LOGGED_IN=false mkfake exit
run out RC_HOLD=1 >/dev/null 2>&1
grep -q 'HOLD: signed out' "$T/out/server.log" && ok "signed-out is held, not started" || bad "signed-out path"

# registered + clean TERM shutdown, with a local listener standing in for :443
mkfake connect
PORT=$((20000 + RANDOM % 20000))
python3 -I -c "
import socket,time
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(('127.0.0.1',$PORT)); s.listen(5)
c=[]
while True:
    c.append(s.accept()[0])" &
LISTENER=$!
disown "$LISTENER"
sleep 1
run conn RC_CONN_PORT=$PORT RC_REG_WAIT=20 >/dev/null 2>&1 &
SP=$!
for _ in $(seq 1 20); do grep -q 'registered:' "$T/conn/server.log" 2>/dev/null && break; sleep 1; done
grep -q 'registered:' "$T/conn/server.log" && ok "registered once a connection is established" || bad "register path"
pkill -TERM -f "$SERVER" 2>/dev/null; wait "$SP" 2>/dev/null
grep -q 'signal received' "$T/conn/server.log" && ok "TERM stops the server cleanly" || bad "TERM path"

[ "$fail" = 0 ] && echo "all passed" || { echo "FAILED"; exit 1; }
