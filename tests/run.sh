#!/usr/bin/env bash
# Запуск теста под xvfb в gl_compatibility.
#   tests/run.sh tests/test_player.gd [--keep]
# Лог: tests/logs/<имя>.log, скриншоты: tests/shots/<имя>_*.png
# Код выхода: 0 — успех; 1 — проваленные проверки; 2 — таймаут; 3 — ошибки движка/скриптов в логе.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/tmp/godot47/Godot_v4.7.2-stable_linux.x86_64}"
TEST="${1:?укажи файл теста, напр. tests/test_player.gd}"
NAME="$(basename "$TEST" .gd)"
LOG="$ROOT/tests/logs/$NAME.log"
mkdir -p "$ROOT/tests/logs" "$ROOT/tests/shots"
# Импорт (кэш class_name и ресурсов) — нужен после новых файлов.
if [ ! -f "$ROOT/.godot/global_script_class_cache.cfg" ] || [ -n "$(find "$ROOT/scripts" "$ROOT/tests" "$ROOT/scenes" -newer "$ROOT/.godot/global_script_class_cache.cfg" -name '*.gd' -o -newer "$ROOT/.godot/global_script_class_cache.cfg" -name '*.tscn' 2>/dev/null | head -1)" ]; then
  timeout 600 "$GODOT" --headless --path "$ROOT" --import >"$ROOT/tests/logs/_import.log" 2>&1 || true
fi
# XVFB_SCREEN=2560x1440 — запуск в большом окне (проверка масштаба интерфейса).
SCREEN="${XVFB_SCREEN:-1280x720}"
RES_ARGS=()
[ -n "${XVFB_SCREEN:-}" ] && RES_ARGS=(--resolution "$SCREEN")
timeout "${TEST_TIMEOUT:-300}" xvfb-run -a -s "-screen 0 ${SCREEN}x24" "$GODOT" --path "$ROOT" \
  --rendering-driver opengl3 --rendering-method gl_compatibility "${RES_ARGS[@]}" \
  res://tests/runner.tscn -- --test="res://${TEST#./}" >"$LOG" 2>&1
CODE=$?
# Ошибки движка/скриптов (аудио в контейнере нет — игнорируем).
ERRS="$(grep -E 'SCRIPT ERROR|Parse Error|ERROR:|Invalid (call|get|set|access)|Nonexistent function' "$LOG" \
  | grep -vE 'ALSA|audio|AudioDriver|init_output_device|status < 0|PulseAudio' || true)"
grep -E '^\[test\]' "$LOG"
if [ -n "$ERRS" ]; then
  echo "---- ошибки в логе ----"; echo "$ERRS" | head -40
  [ $CODE -eq 0 ] && CODE=3
fi
echo "exit=$CODE  лог: $LOG"
exit $CODE
