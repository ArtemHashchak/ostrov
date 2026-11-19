#!/usr/bin/env bash
# Запуск теста.
#   tests/run.sh tests/test_player.gd           — как раньше: xvfb + gl_compatibility, со скриншотами
#   tests/run.sh tests/test_player.gd --fast    — быстро: headless (без окна и GPU), снимков нет,
#                                                 только логика; можно гонять параллельно (TEST_FAST=1 — то же)
#   tests/run.sh a.gd,b.gd,c.gd --fast          — несколько тестов в ОДНОМ процессе Godot
# Лог: tests/logs/<имя>.log, скриншоты: tests/shots/<имя>_*.png
# Код выхода: 0 — успех; 1 — проваленные проверки; 2 — таймаут; 3 — ошибки движка/скриптов в логе.
# Окружение: TEST_TIMEOUT (сек), XVFB_SCREEN=2560x1440, TEST_LOW=1 (облегчённая графика в рендере).
# Мир архипелага кэшируется (.godot/test_cache) — повторные запуски строят его в разы быстрее.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/tmp/godot47/Godot_v4.7.2-stable_linux.x86_64}"
TEST="${1:?укажи файл теста, напр. tests/test_player.gd}"
shift
FAST="${TEST_FAST:-0}"
for a in "$@"; do
  case "$a" in
    --fast) FAST=1 ;;
    --shots) FAST=0 ;;
  esac
done
# Один или несколько тестов (через запятую).
IFS=',' read -r -a LIST <<< "$TEST"
RES_LIST=()
for t in "${LIST[@]}"; do t="${t#./}"; RES_LIST+=("res://$t"); done
if [ ${#LIST[@]} -gt 1 ]; then
  NAME="suite_$(basename "${LIST[0]}" .gd)_x${#LIST[@]}"
  TARG="--tests=$(IFS=,; echo "${RES_LIST[*]}")"
else
  NAME="$(basename "${LIST[0]}" .gd)"
  TARG="--test=${RES_LIST[0]}"
fi
LOG="$ROOT/tests/logs/$NAME.log"
mkdir -p "$ROOT/tests/logs" "$ROOT/tests/shots" /tmp/claude-0
# Импорт (кэш class_name и ресурсов) — нужен после новых файлов. Под своей блокировкой,
# чтобы параллельные тесты не импортировали одновременно.
if [ ! -f "$ROOT/.godot/global_script_class_cache.cfg" ] || [ -n "$(find "$ROOT/scripts" "$ROOT/tests" "$ROOT/scenes" -newer "$ROOT/.godot/global_script_class_cache.cfg" -name '*.gd' -o -newer "$ROOT/.godot/global_script_class_cache.cfg" -name '*.tscn' 2>/dev/null | head -1)" ]; then
  flock /tmp/claude-0/godot_import.lock timeout 600 "$GODOT" --headless --path "$ROOT" --import >"$ROOT/tests/logs/_import.log" 2>&1 || true
fi
export OSTROVA_TERRAIN_CACHE=1
if [ "$FAST" = "1" ]; then
  export OSTROVA_TEST_FAST=1
  timeout "${TEST_TIMEOUT:-300}" "$GODOT" --headless --path "$ROOT" \
    res://tests/runner.tscn -- "$TARG" >"$LOG" 2>&1
  CODE=$?
else
  [ "${TEST_LOW:-0}" = "1" ] && export OSTROVA_TEST_LOW=1
  # XVFB_SCREEN=2560x1440 — запуск в большом окне (проверка масштаба интерфейса).
  SCREEN="${XVFB_SCREEN:-1280x720}"
  RES_ARGS=()
  [ -n "${XVFB_SCREEN:-}" ] && RES_ARGS=(--resolution "$SCREEN")
  timeout "${TEST_TIMEOUT:-300}" xvfb-run -a -s "-screen 0 ${SCREEN}x24" "$GODOT" --path "$ROOT" \
    --rendering-driver opengl3 --rendering-method gl_compatibility "${RES_ARGS[@]}" \
    res://tests/runner.tscn -- "$TARG" >"$LOG" 2>&1
  CODE=$?
fi
# Ошибки движка/скриптов (аудио в контейнере нет — игнорируем; в headless — нет рендера).
ERRS="$(grep -E 'SCRIPT ERROR|Parse Error|ERROR:|Invalid (call|get|set|access)|Nonexistent function' "$LOG" \
  | grep -vE 'ALSA|audio|AudioDriver|init_output_device|status < 0|PulseAudio' || true)"
grep -E '^\[test\]' "$LOG" | grep -v 'shot (пропущен'
if [ -n "$ERRS" ]; then
  echo "---- ошибки в логе ----"; echo "$ERRS" | head -40
  [ $CODE -eq 0 ] && CODE=3
fi
echo "exit=$CODE  лог: $LOG"
exit $CODE
