#!/usr/bin/env bash
# Семафор на запуск Godot.
#   tools/godot_slots.sh render <cmd...>  — один рендер-слот (xvfb/llvmpipe тяжёлый):
#                                         общий /tmp/claude-0/godot.lock (совместим со старым flock).
#   tools/godot_slots.sh logic  <cmd...>  — LOGIC_SLOTS (по умолчанию 2) лёгких headless-слотов.
set -u
KIND="${1:?render|logic}"; shift
LOCKDIR=/tmp/claude-0; mkdir -p "$LOCKDIR"
if [ "$KIND" = "render" ]; then
  exec flock "$LOCKDIR/godot.lock" "$@"
fi
N="${LOGIC_SLOTS:-2}"
while true; do
  for i in $(seq 1 "$N"); do
    exec 9>"$LOCKDIR/godot_logic_$i.lock"
    if flock -n 9; then "$@"; rc=$?; flock -u 9; exit $rc; fi
  done
  sleep 2
done
