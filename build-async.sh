#!/usr/bin/env bash
# Detached wrapper around build.sh — the build takes ~10-20 min.
#   ./build-async.sh start | status [--json] | wait | log | stop
set -euo pipefail
cd "$(dirname "$0")"

LOG=build.log
PID=build.pid
EXIT=build.exit

running() { [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; }

case "${1:-status}" in
  start)
    running && { echo "already running (pid $(cat $PID))"; exit 1; }
    rm -f "$EXIT"
    nohup bash -c 'bash ./build.sh; rc=$?; echo $rc > '"$EXIT"'; rm -f '"$PID"'; \
      [ $rc -eq 0 ] || echo "BUILD_FAILED rc=$rc"' > "$LOG" 2>&1 &
    echo $! > "$PID"
    echo "started (pid $(cat $PID)) — ./build-async.sh wait"
    ;;
  status)
    if running; then state=running; rc=
    elif [ -f "$EXIT" ]; then rc=$(cat "$EXIT"); [ "$rc" = 0 ] && state=success || state=failed
    else state=idle; rc=; fi
    if [ "${2:-}" = --json ]; then
      printf '{"state":"%s","rc":%s,"pid":%s}\n' "$state" "${rc:-null}" "$( [ -f $PID ] && cat $PID || echo null)"
    else
      echo "$state ${rc:+(rc=$rc)}"
      [ -f "$LOG" ] && tail -3 "$LOG"
    fi
    ;;
  wait)
    while running; do sleep 10; done
    rc=$(cat "$EXIT" 2>/dev/null || echo 1)
    tail -5 "$LOG" 2>/dev/null
    exit "$rc"
    ;;
  log)  tail -f "$LOG" ;;
  stop) running && kill "$(cat $PID)" && echo stopped || echo "not running" ;;
  *)    echo "usage: $0 {start|status [--json]|wait|log|stop}" >&2; exit 1 ;;
esac
