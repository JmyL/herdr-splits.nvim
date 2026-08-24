#!/usr/bin/env bash
# Mocked-herdr tests for scripts/herdr-nav.sh.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
nav="$root/scripts/herdr-nav.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

calls="$tmp/calls"
edges="$tmp/edges.json"
process="$tmp/process.json"
conf="$tmp/herdr-splits.conf"
mock="$tmp/herdr"

cat >"$mock" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$CALLS"
case "${1:-} ${2:-}" in
'pane current')
  printf '%s\n' '{"pane_id":"p1"}'
  ;;
'pane process-info')
  cat "$PROCESS"
  ;;
'pane edges')
  cat "$EDGES"
  ;;
'pane zoom' | 'pane focus' | 'pane send-keys')
  exit 0
  ;;
*)
  printf 'unexpected herdr invocation: %s\n' "$*" >&2
  exit 99
  ;;
esac
EOF
chmod +x "$mock"

run_nav() {
  : >"$calls"
  CALLS="$calls" PROCESS="$process" EDGES="$edges" EDGES_AFTER="$tmp/edges-after.json" \
    HERDR_BIN_PATH="$mock" HERDR_SPLITS_CONFIG="$conf" \
    bash "$nav" "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  if [ -s "$calls" ]; then
    printf 'calls:\n%s\n' "$(cat "$calls")" >&2
  fi
  exit 1
}

assert_no_call() {
  if grep -q "$1" "$calls"; then
    fail "expected no call matching '$1'"
  fi
}

assert_call() {
  if ! grep -q "$1" "$calls"; then
    fail "expected a call matching '$1'"
  fi
}

printf '%s\n' '{"name":"bash"}' >"$process"
printf '%s\n' '{"result":{"edges":{"left":false,"right":true,"up":true,"down":true},"zoomed":true}}' >"$edges"

# Zoomed + unzoom disabled: stay put. Do not unzoom or focus a neighbor.
printf '%s\n' 'unzoom_on_nav=false' 'nav_at_edge=stop' >"$conf"
run_nav left
assert_no_call 'pane zoom'
assert_no_call 'pane focus'
assert_no_call 'pane send-keys'

# Zoomed + unzoom enabled: unzoom, then focus using the refreshed edges.
printf '%s\n' 'unzoom_on_nav=true' 'nav_at_edge=stop' >"$conf"
printf '%s\n' '{"result":{"edges":{"left":false,"right":true,"up":true,"down":true},"zoomed":false}}' >"$tmp/edges-after.json"
cat >"$mock" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$CALLS"
case "${1:-} ${2:-}" in
'pane current')
  printf '%s\n' '{"pane_id":"p1"}'
  ;;
'pane process-info')
  cat "$PROCESS"
  ;;
'pane edges')
  if grep -q 'pane zoom' "$CALLS" 2>/dev/null; then
    cat "$EDGES_AFTER"
  else
    cat "$EDGES"
  fi
  ;;
'pane zoom' | 'pane focus' | 'pane send-keys')
  exit 0
  ;;
*)
  printf 'unexpected herdr invocation: %s\n' "$*" >&2
  exit 99
  ;;
esac
EOF
chmod +x "$mock"
printf '%s\n' '{"result":{"edges":{"left":false,"right":true,"up":true,"down":true},"zoomed":true}}' >"$edges"
run_nav left
assert_call 'pane zoom --off --current'
assert_call 'pane focus --direction left --current'

# Neovim pane: always forward the chord; zoom is Neovim's problem.
printf '%s\n' '{"name":"nvim"}' >"$process"
printf '%s\n' 'unzoom_on_nav=false' 'nav_key_left=alt+h' >"$conf"
run_nav left
assert_call 'pane send-keys p1 alt+h'
assert_no_call 'pane zoom'
assert_no_call 'pane focus'

printf 'ok\n'
