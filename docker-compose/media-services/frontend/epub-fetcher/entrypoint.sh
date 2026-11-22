#!/bin/sh
# Fetch every URL listed in $CONFIG_DIR/urls.txt, then wait and repeat.
#
# `-u` updates an existing epub in place, so a document that publishes new
# parts is appended instead of downloaded from scratch. The output name is
# derived from the source, so re-runs do not accumulate duplicates.
#
# The wait is not a blind sleep: editing urls.txt or sending SIGHUP runs the
# list again immediately, so adding a URL never means waiting for the timer.
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

# Seeded once so the container has something to read and can say what to do.
if [ ! -f "$URLS" ]; then
  cp /opt/fetcher/urls.example.txt "$URLS"
  log "no urls.txt, seeded an empty one at $URLS"
fi

fetch_all() {
  # The stamp means "a pass finished", not "every URL worked": it is written
  # before the list is read, so an empty list still counts as a healthy pass.
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
    # is_adult answers the mature-content gate: without it the CLI aborts when
    # nobody is there to type yes.
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
    # A background sleep that `wait` can interrupt when the trap fires.
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
