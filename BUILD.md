# Сборка «Островов»

Готовые сборки — во вкладке **Releases** репозитория (собираются GitHub Actions: `.github/workflows/release.yml`, запуск — Actions → «Release builds» → Run workflow, или пуш тега `v*`).

Собрать самому:
1. Godot **4.7.2** и шаблоны экспорта 4.7.2 (github.com/godotengine/godot/releases/tag/4.7.2-stable; в редакторе: Editor → Manage Export Templates).
2. Открыть проект в редакторе (первый импорт ~2 мин) или `godot --headless --path . --import`.
3. Экспорт (пресеты уже в `export_presets.cfg`):
   - `godot --headless --path . --export-release "Windows" build/windows/Ostrova.exe`
   - `godot --headless --path . --export-release "macOS" build/macos/Ostrova.zip`
