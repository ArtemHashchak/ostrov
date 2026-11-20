#!/usr/bin/env bash
# Наборы тестов.
#   tests/run_suite.sh smoke            — быстрый набор (логика, headless, параллельно), после каждого коммита
#   tests/run_suite.sh module <имя>     — все tests/test_<имя>*.gd в быстром режиме (headless, параллельно)
#   tests/run_suite.sh full             — всё: логика параллельно headless, рендер-тесты (## test-class: render)
#                                         по одному под xvfb со снимками; перед сборкой
#   tests/run_suite.sh list <имена...>  — указанные тесты в быстром режиме
# Итог: таблица в tests/logs/_suite_<режим>.txt. Код выхода 0 — всё зелёное.
# Окружение: LOGIC_SLOTS (по умолчанию 2), TEST_TIMEOUT.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
MODE="${1:-smoke}"; shift || true
"$ROOT/tools/test_reaper.sh" >/dev/null 2>&1 || true

# Быстрый набор: чистая логика и лёгкие сцены (каждый ≲ 1 мин headless).
SMOKE=(test_game_rules test_fauna_models test_sea_model test_corals test_coconut_drop
       test_main_menu test_ui_inventory test_build_wall test_combat_dummy test_bots_gather)

RENDER=()   # тесты, которым нужен настоящий рендер (пиксели)
for f in tests/test_*.gd; do
  grep -q '^## test-class: render' "$f" && RENDER+=("$(basename "$f" .gd)")
done
is_render() { local n="$1"; for r in "${RENDER[@]:-}"; do [ "$r" = "$n" ] && return 0; done; return 1; }

LIST=()
case "$MODE" in
  smoke) LIST=("${SMOKE[@]}") ;;
  module) for f in tests/test_${1:?имя модуля}*.gd; do LIST+=("$(basename "$f" .gd)"); done ;;
  list) LIST=("$@") ;;
  full) for f in tests/test_*.gd; do LIST+=("$(basename "$f" .gd)"); done ;;
  *) echo "режим: smoke | module <имя> | full | list <тесты>"; exit 2 ;;
esac

OUT="tests/logs/_suite_${MODE}.txt"
mkdir -p tests/logs /tmp/claude-0/suite
RES=/tmp/claude-0/suite/res_$$; : > "$RES"
T0=$(date +%s)
run_one() {  # имя  режим(logic|render)
  local n="$1" kind="$2" s rc to
  s=$(date +%s)
  # свой таймаут теста: строка «## test-timeout: <сек>» (иначе TEST_TIMEOUT или 300/1500)
  to=$(sed -n 's/^## test-timeout: *\([0-9]*\).*/\1/p' "tests/$n.gd" | head -1)
  export TEST_TIMEOUT="${to:-${TEST_TIMEOUT:-300}}"
  if [ "$kind" = "render" ]; then
    TEST_LOW=1 "$ROOT/tools/godot_slots.sh" render "$ROOT/tests/run.sh" "tests/$n.gd" --shots >/dev/null 2>&1; rc=$?
  else
    "$ROOT/tools/godot_slots.sh" logic "$ROOT/tests/run.sh" "tests/$n.gd" --fast >/dev/null 2>&1; rc=$?
  fi
  printf "%-32s %-6s exit=%s %5ss\n" "$n" "$kind" "$rc" "$(( $(date +%s) - s ))" >> "$RES"
}
N="${LOGIC_SLOTS:-2}"
for n in "${LIST[@]}"; do
  [ -f "tests/$n.gd" ] || { echo "нет tests/$n.gd"; continue; }
  if [ "$MODE" = "full" ] && is_render "$n"; then
    run_one "$n" render &
  else
    # не больше N логических одновременно (сами слоты тоже держат очередь)
    while [ "$(jobs -rp | wc -l)" -ge $((N + 1)) ]; do sleep 1; done
    run_one "$n" logic &
  fi
done
wait
{
  echo "Набор: $MODE   время: $(( $(date +%s) - T0 )) с   ($(date '+%F %T'))"
  sort "$RES"
} | tee "$OUT"
rm -f "$RES"
grep -q 'exit=[^0]' "$OUT" && exit 1 || exit 0
