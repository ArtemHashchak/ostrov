# «Острова» (Godot 4.7) — архитектура и правила

Концепт: Bed Wars на тропическом архипелаге — защити флаг (пока цел — возрождаешься), строй мосты через море с акулами, выживай. Графика и ощущение — как в The Forest (реализм, вид от первого лица). Платформа: ПК (Windows/Mac), рендер **Forward+**. Наши автотесты идут под xvfb в **gl_compatibility** — всё должно работать и там (без красивостей).

Движок: **Godot 4.7.2** (`/tmp/godot47/Godot_v4.7.2-stable_linux.x86_64`). Язык: **GDScript со статической типизацией** (`var x: int`, `func f() -> void`, `:=`).

## Папки
| Папка | Что | Владелец |
|---|---|---|
| `scripts/core/` | автозагрузки, RenderProfile | CORE |
| `scripts/world/` | рельеф, архипелаг, растительность, вода, небо | WORLD |
| `scripts/player/` | игрок, руки, взаимодействие | PLAYER (сейчас CORE) |
| `scripts/build/` | стройка из брёвен, мосты-плоты, флаг | BUILD |
| `scripts/sea/` | акулы, рыбы, море | SEA |
| `scripts/fauna/` | наземные животные, приручение | FAUNA |
| `scripts/survival/` | голод/жажда/вода/еда/огород/мусор | SURVIVAL |
| `scripts/bots/` | боты-соперники | BOTS |
| `scripts/ui/` | HUD, меню, инвентарь, крафт | UI |
| `scripts/supply/` | посылки спонсоров: самолёт, ящик на парашюте, дым, лут; современные предметы (автомат, дробовик, ракетница, граната, мачете, бензопила, горелка, бинокль, фонарик, рация, ласты, бронежилет, аптечка, консервы) | SUPPLY |
| `scenes/<модуль>/` | сцены модуля | владелец модуля |
| `assets/`, `addons/` | ассеты и аддоны (см. ASSETS.md) | ASSETS (остальные — только читают) |
| `tests/` | `test_<модуль>_*.gd` — тесты модулей | каждый свои |

**Правило параллельной работы:** каждый агент правит только свою папку `scripts/<модуль>/`, `scenes/<модуль>/` и свои тесты. `project.godot`, `scripts/core/*` и `ARCH.md` правит только CORE (или по прямой инструкции координатора). Нужен новый сигнал/общий API — попроси CORE (или допиши сигнал в конец `Events` с комментарием, кто добавил).

## Автозагрузки (порядок важен)
1. **Settings** (`scripts/core/settings.gd`, ALWAYS) — карта ввода создаётся в коде (`DEFAULT_KEYS`, мышь, геймпад, оси), переназначение `rebind_key()`, сохранение в `user://settings.cfg`; `mouse_sensitivity`, `fov`, `invert_y`, `is_compatibility_renderer()`.
   Действия: `move_forward/back/left/right, jump, sprint, crouch, interact, attack, aim, inventory, craft, pause, drop, hotbar_1..9, look_up/down/left/right` (геймпад).
2. **Events** (`scripts/core/events.gd`) — сигнальная шина. Модули не держат ссылки друг на друга, а шлют/слушают сигналы: `match_started, match_ended, flag_placed, flag_damaged, flag_destroyed, team_eliminated, character_spawned, character_damaged, character_died, interact_hint_changed, player_swing, player_stamina_changed, pause_toggled, toast, inventory_changed, item_crafted`.
3. **Items** (`scripts/core/items.gd`) — база предметов и рецептов. Модули регистрируют свои в `_ready()` своего узла: `Items.register_item(id, name, kind, stack, weight, data)`, `Items.register_recipe(id, output, needs, count, station)`. Файл не править.
4. **Game** (`scripts/core/game.gd`) — матч: команды (`TEAM_NAMES`, `team_color()`), флаги (`set_flag_placed`, `damage_flag`, `can_respawn`), время (`match_time`, `match_length` — 3 ч по умолчанию), `register_member`.

## Общие соглашения
- **Группы:** `characters` (все персонажи), `player`, `bots`, `animals`, `interactable` (по желанию), `choppable`, `buildable`.
- **Взаимодействие (E):** у объекта (или предка коллайдера до 6 уровней) методы `get_interact_text(player) -> String` и `interact(player) -> void`. Подсказка уходит в `Events.interact_hint_changed`.
- **Удар (ЛКМ):** игрок кидает луч на 2.2 м в момент удара анимации и вызывает у цели `on_hit(by, hit: Dictionary)`; плюс `Events.player_swing`.
- **Переноска:** `player.set_carrying_log(on, obj)` — бревно на плече (руки, скорость ×0.72); E без цели вызывает `interact()` у несомого объекта (положить).
- **Рендер:** окружение/свет — только через `RenderProfile.make_environment(hdri)` и `RenderProfile.make_sun()`: в Forward+ включаются SDFGI/SSAO/SSIL/объёмный туман, в compatibility — нет. Проверка: `RenderProfile.is_compat()` (в 4.x: нет RenderingDevice → OpenGL).
- **Вода:** `WaterFactory.make(size, subdiv)` — Forward+: LesusX Gerstner; compatibility: antz foam.
- **Материалы:** `TerrainMaterial.make()` (сплат песок/мокрый песок/трава/скала по высоте и уклону), `TerrainMaterial.pbr(set, uv_scale)` — PBR из `assets/textures/<set>/`.
- **Аддоны:** включены в project.godot: Terrain3D 1.0.1, Sky3D, MultiMesh Scatter. **Terrain3D в gl_compatibility (llvmpipe) не работает** — шейдер не компилируется («initializer of const variable must be a constant expression»), высоты = NaN. Поэтому: у игрока (Forward+) — Terrain3D; в тестах — запасной процедурный меш + `TerrainMaterial` (`RenderProfile.is_compat()`). WORLD обязан поддерживать оба пути.
- Тексты для игрока — по-русски.

## Тесты
- Запуск: `tests/run.sh tests/test_player.gd` (переменные: `GODOT=…`, `TEST_TIMEOUT=300`). Делает импорт при новых файлах, запускает под xvfb в gl_compatibility, пишет `tests/logs/<имя>.log`, скриншоты `tests/shots/<имя>_*.png`.
- Код выхода: 0 — успех; 1 — проваленные `check`; 2 — таймаут/ошибка загрузки; 3 — ошибки движка/скриптов в логе (аудио-ошибки контейнера игнорируются).
- Тест: `extends TestCase`, поля `scene_path` (по умолчанию тестовый остров; `""` — без сцены), `timeout_sec`; в `run()` — хелперы `await wait(s)`, `wait_frames(n)`, `press(action, s)`, `tap(action)` (доходит до `_unhandled_input`), `shot(name)`, `check(cond, msg)`. Пример — `tests/test_player.gd`.
- Пробы (не входят в набор): `tests/probes/` (напр. `probe_terrain3d.gd`).
- **Важно:** под llvmpipe кадр рисуется медленно — меряй время через `wait(sec)`/`physics_frame`, а не числом кадров рендера.

## Сцены
- `scenes/test/test_island.tscn` (+ `scripts/world/test_island.gd`) — остров-заглушка: рельеф на PBR-текстурах, HDRI-небо, вода по рендеру, камни/папоротники из ассетов, бревно (`TestLog`) и мишень (`TestTarget`), игрок. Главная сцена проекта, пока WORLD не сделает настоящую.
- `scenes/player/player.tscn` — игрок (`Player`, CharacterBody3D; дети создаются в коде).

## Как подключать модуль
1. Создай `scripts/<модуль>/<модуль>.gd` (корневой узел модуля) и при необходимости `scenes/<модуль>/…`.
2. Регистрация предметов — в `_ready()` модуля через `Items`.
3. Связь с другими — через `Events` и группы, а прямые вызовы — только по методам из этого файла.
4. Если нужна автозагрузка модуля — попроси CORE добавить строку в `[autoload]`.
5. Добавь `tests/test_<модуль>_*.gd`, прогони `tests/run.sh`, без ошибок в логе.
