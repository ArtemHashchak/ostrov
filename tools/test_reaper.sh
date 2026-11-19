#!/usr/bin/env bash
# Уборщик зависших тестов: убивает процессы Godot/xvfb тестов, которые живут
# дольше REAPER_MAX_MIN минут (по умолчанию 75 — больше любого TEST_TIMEOUT=3600),
# и ждущие в очереди flock-обёртки старше REAPER_WAIT_MIN (180) минут —
# обычно это остатки погибших агентов, держащие общую блокировку часами.
#   tools/test_reaper.sh [--dry]
set -u
MAX_MIN="${REAPER_MAX_MIN:-75}"
WAIT_MIN="${REAPER_WAIT_MIN:-180}"
DRY=0; [ "${1:-}" = "--dry" ] && DRY=1
killed=0
kill_tree() {  # pid
  local p="$1"
  for c in $(pgrep -P "$p" 2>/dev/null); do kill_tree "$c"; done
  if [ $DRY -eq 1 ]; then echo "[reaper] (dry) kill $p: $(ps -o args= -p "$p" | cut -c1-140)"; else kill -9 "$p" 2>/dev/null && killed=$((killed+1)); fi
}
while read -r pid et args; do
  [ -z "$pid" ] && continue
  case "$args" in
    *Godot_v4*runner.tscn*|*Godot_v4*--quit-after*|*xvfb-run*Godot_v4*|*Xvfb\ :*)
      if [ "$et" -gt $((MAX_MIN*60)) ]; then echo "[reaper] старый тест ${et}s: pid $pid"; kill_tree "$pid"; fi ;;
    flock*godot*.lock*)
      if [ "$et" -gt $((WAIT_MIN*60)) ]; then echo "[reaper] старая очередь ${et}s: pid $pid"; kill_tree "$pid"; fi ;;
  esac
done < <(ps -eo pid=,etimes=,args=)
# Xvfb без живого xvfb-run-родителя
for x in $(pgrep -x Xvfb 2>/dev/null); do
  pp=$(ps -o ppid= -p "$x" | tr -d ' ')
  if [ "$pp" = "1" ]; then echo "[reaper] осиротевший Xvfb $x"; kill_tree "$x"; fi
done
[ $DRY -eq 0 ] && [ $killed -gt 0 ] && echo "[reaper] убито процессов: $killed"
exit 0
