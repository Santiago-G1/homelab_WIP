#!/bin/sh
# Fetch every URL in $CONFIG_DIR/urls.txt, then wait and repeat. `-u` updates an
# existing epub in place, so re-runs do not accumulate duplicates.
#
# Editing urls.txt or sending SIGHUP runs the list again immediately.
set -eu

CONFIG_DIR="${CONFIG_DIR:-/config}"
OUT_DIR="${OUT_DIR:-/out}"
URLS="${CONFIG_DIR}/urls.txt"
PERSONAL="${CONFIG_DIR}/personal.ini"
REFRESH_HOURS="${REFRESH_HOURS:-12}"
IS_ADULT="${IS_ADULT:-true}"
POLL_SECONDS="${POLL_SECONDS:-30}"
STAMP="${CONFIG_DIR}/.last-run"

log() { printf '%s fetcher: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

reload=0
trap 'log "SIGHUP received"; reload=1' HUP

mkdir -p "$CONFIG_DIR" "$OUT_DIR"
umask 022

# Seed an empty list on first start.
if [ ! -f "$URLS" ]; then
  cp /opt/fetcher/urls.example.txt "$URLS"
  log "no urls.txt, seeded an empty one at $URLS"
fi

fetch_all() {
  # Written before the list is read: an empty list is still a finished pass.
  : > "$STAMP"

  # Comments and blank lines are ignored, so urls.txt can document itself.
  urls=$(grep -vE '^[[:space:]]*(#|$)' "$URLS" || true)
  if [ -z "$urls" ]; then
    log "urls.txt has no entries yet"
    return 0
  fi

  failed=0
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    log "fetching $url"
    # Answer the CLI's interactive prompt; nobody is there to type it.
    set -- -f epub -u -o "is_adult=${IS_ADULT}"
    if [ -f "$PERSONAL" ]; then
      set -- "$@" -c "$PERSONAL"
    fi
    # </dev/null keeps the engine from swallowing the URL list.
    if (cd "$OUT_DIR" && fanficfare "$@" "$url" </dev/null); then
      log "ok $url"
    else
      failed=$((failed + 1))
      log "FAILED $url"
    fi
  done <<EOF_URLS
$urls
EOF_URLS

  if [ "$failed" -ne 0 ]; then
    log "$failed url(s) failed, see the engine output above"
  fi
}

wait_for_work() {
  deadline=$(( $(date +%s) + REFRESH_HOURS * 3600 ))
  seen=$(cksum "$URLS" 2>/dev/null || echo none)
  log "idle: next scheduled pass in ${REFRESH_HOURS}h (edit urls.txt or send SIGHUP to run now)"
  while [ "$reload" -eq 0 ] && [ "$(date +%s)" -lt "$deadline" ]; do
    # A sleep `wait` can interrupt when the trap fires.
    sleep "$POLL_SECONDS" &
    wait $! || true
    [ "$reload" -eq 0 ] || break
    now=$(cksum "$URLS" 2>/dev/null || echo none)
    if [ "$now" != "$seen" ]; then
      log "urls.txt changed, running now"
      break
    fi
  done
}

while :; do
  fetch_all || log "a pass ended with an error"
  reload=0
  wait_for_work
done
