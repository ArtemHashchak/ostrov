# ASSETS — ресурсы проекта «Острова»

Все ресурсы взяты с GitHub, лицензии проверены. Рядом с каждой группой лежит файл лицензии.
Объём: `assets/` ≈ 295 МБ, `addons/` ≈ 76 МБ (итого ≈ 370 МБ, лимит 1,5 ГБ).

Импорт проверен на Godot **4.7.2** (`--headless --import`): все 42 GLB, 18 OBJ, все PNG/JPG, 6 HDR и 77 звуков импортируются без ошибок.
Есть только безвредные предупреждения: «OBJ: Ambient light … ignored in PBR» и «HDR: Ignoring unsupported header».

Превью-сцена: `tools/asset_preview.gd`.
- Запуск: `godot --path <проект> --rendering-method gl_compatibility -s res://tools/asset_preview.gd -- <папка_для_png>`.
- Скриншоты: `tests/shots/assets_beach.png`, `assets_props.png`, `assets_jungle.png`, `assets_ocean.png`.

| Лицензия | Что требуется |
|---|---|
| CC0 | атрибуция не требуется (но мы её всё равно ведём) |
| MIT | в билд класть текст лицензии |
| **CC BY 4.0** | **обязательна строка в титрах** (см. «Звуки») |

---

## 1. Аддоны (`addons/`) — НЕ включены в project.godot

### 1.1 Terrain3D 1.0.1 — `addons/terrain_3d/` (MIT)

- **Авторы:** Cory Petkovsek & Roope Palmroos (TokisanGames).
- **Источник:** копия с бинарниками из MIT-репозитория `LesusX/Water-Shader`. Сами релизы Terrain3D отсюда недоступны.
- **Совместимость:** GDExtension, `compatibility_minimum = 4.4`. Работает на 4.4–4.7.
- **Платформы:** оставлены бинарники только для Windows, Linux и macOS (Android, iOS и Web удалены).
- **Что даёт:** PBR-терраин со сплатом до 32 текстур, скульптинг в редакторе, дыры под пещеры, LOD (clipmap).
- **Включение (CORE):**
  1. Project Settings → Plugins → Terrain3D → Enable.
  2. Перезапустить редактор (GDExtension подхватится сам через `terrain.gdextension`).
- **Ограничение:** в gl_compatibility Terrain3D 1.0 работает частично. Для основной игры нужен рендер **Forward+**.
- **Запасной путь:** для тестов в compatibility — свой процедурный меш + сплат-шейдер на текстурах из раздела 2.
- **Свежая версия:** Terrain3D 1.1 (нужен Godot ≥ 4.5) можно поставить из AssetLib в редакторе.
- **Примечание:** бинарники в автотестах не запускались, это сторонний нативный код.

### 1.2 Sky3D 2.2-dev — `addons/sky_3d/` (MIT)

- **Автор:** TokisanGames (Cory Petkovsek). Источник: `github.com/TokisanGames/Sky3D`.
- **Что даёт:** смена дня и ночи, солнце, луна с фазами, звёзды, облака, туман, управление экспозицией.
- **Совместимость:** Godot 4.3+, рендеры Forward+, Mobile и Compatibility.
- **Включение:**
  1. Plugins → Sky3D → Enable.
  2. В сцену добавить узел `Sky3D` (он заменяет WorldEnvironment и DirectionalLight).

### 1.3 MultiMesh Scatter — `addons/multimesh_scatter/` (MIT)

- **Автор:** arcaneenergy. Источник: `github.com/arcaneenergy/godot-multimesh-scatter`.
- **Что даёт:** разброс травы, кустов, камней и пальм через MultiMeshInstance3D по коллизии терраина.
- **Включение:**
  1. Plugins → MultiMesh Scatter → Enable.
  2. Добавить узел `MultiMeshScatter`, задать mesh и физическую маску.

### 1.4 Вода — `addons/ostrova_water/` (не плагин, а шейдеры; включать не нужно)

**`antz_foam_water/` (MIT, Antz / antzGames, `github.com/antzGames/Godot-Foam-Water`)**
- **Рекомендуется для старта:** работает в Compatibility, Mobile и Forward+. На скриншоте `assets_ocean.png` — именно он.
- **Использование:** `water_material.tres` на PlaneMesh или QuadMesh с сильной сабдивизией.
- **Внутри:**
  - `foam_water.tscn` — демо-сцена;
  - `textures/` — пена, шум, песок дна (Poly Haven aerial_beach_01, CC0);
  - `ocean-waves.mp3` — из демо; его лицензия не указана отдельно, в релиз не брать — используйте звуки из раздела 5.
- **Изменение:** пути `res://` переписаны на `res://addons/ostrova_water/antz_foam_water/...`.

**`lesusx_gerstner/` (MIT, LesusX, `github.com/LesusX/Water-Shader`)**
- **Что это:** океан на волнах Герстнера — 8 волн, каустика, пена у берега, Beer's law, пики волн.
- **Рендер:** использует `hint_screen_texture` и `hint_depth_texture`, поэтому рассчитан на **Forward+**.
- **Текстуры:** `textures/` — каустика, пена, 4 карты нормалей воды.
- **Использование:** ShaderMaterial с `water_shader.gdshader` на сабдивизированном плейне.
  - Заполнить `edge_foam_texture` (foam.jpg) и цвета.
  - Для плавучести брёвен и мостов повторить формулу Герстнера в GDScript (те же `wave_1..8`).

---

## 2. PBR-текстуры (`assets/textures/`) — CC0

**Формат.** `<имя>/<имя>_{albedo,normal,roughness,ao,height[,opacity]}.png`.
- **Poly Haven:** 512 px, источник `Papyszoo/CC0-Public-Domain-Textures`.
- **ambientCG:** 1K.
- **Лицензия:** `textures/LICENSE_CC0.txt`.

| Группа | Наборы (источник) |
|---|---|
| Песок / пляж | coast_sand_01, damp_sand (мокрый песок), coast_sand_rocks_02, coral_gravel, low_tide_rocks (Poly Haven) |
| Земля / трава | leafy_grass, sparse_grass, forest_ground_04, brown_mud_leaves_01, forest_leaves_02 (Poly Haven); Moss002 (ambientCG) |
| Камень / вулкан | rocky_terrain_02, cliff_side, dark_rock, mossy_rock, seaside_rock (Poly Haven); Lava002 (ambientCG) |
| Кора / дерево | palm_bark, palm_tree_bark, bark_brown_02, weathered_planks, rough_wood (Poly Haven); Bamboo001A (ambientCG) |
| Листья (с opacity) | Leaf001, Leaf002, Leaf003 (ambientCG) — карточки пальмовых листьев и кустов |
| Верёвка / ткань | Rope001, Rope002, Net001A, Fabric004, ThatchedRoof001A (ambientCG) |

**Как использовать**
- StandardMaterial3D: albedo → Albedo, normal → Normal Map, roughness → Roughness (канал Red), ao → AO.
  - Ровно так делает `tex_mat()` в `tools/asset_preview.gd`.
- **Нормали.** У ambientCG — OpenGL (+Y), Godot ожидает именно его. У Poly Haven конвенция не проверена.
  - Если рельеф выглядит «вдавленным», включите в импорте `normal_map → Invert Y`.
- Для листьев: Transparency = Alpha Scissor, Cull = Disabled, alpha брать из `_opacity.png` (или упаковать в альфу albedo).

---

## 3. Модели (`assets/models/`)

### 3.1 `polyhaven/` — 37 GLB (CC0, Poly Haven)

- **Источник:** конвертация из `wild-fields-1648` (упакованные меши → GLB, конвертер `tools/pack_to_glb.py`).
- **Лицензия:** модели CC0; код репо — MIT (`LICENSE_wild-fields-1648_MIT.txt`, `CREDITS_wild-fields-1648.md`).
- **Качество:** полигонаж снижен, текстуры 512 px, материал ORM (roughness/metal/ao). Хорошо для LOD и массового разброса.

| Группа | Модели |
|---|---|
| Камни | boulder_01, boulder_02, rock_07, stone_01, rock_moss_set_01_rock01–06, rock_moss_set_02_rock07–13 |
| Дерево / растения | tree_stump_01, tree_stump_02 (пни!), dead_tree_trunk (бревно / плавник), shrub_02_a–d, fern_02_a–d (папоротник, alpha mask) |
| Пляжный мусор / лут | wooden_barrels_01_barrel01/02, wine_barrel_01, wooden_crate_01/02, wooden_bucket_01, wicker_basket_01, wooden_ladder, cannon_01 |

### 3.2 `polyhaven_obj/` — 18 OBJ (CC0, Poly Haven)

- **Источник:** `RazorEdge-wyh/unity-nature-pbr-asset-library`. Лицензия и титры: `LICENSE_CC0.txt`, `CREDITS_unity-nature-pbr-asset-library.md`.
- **Модели:**
  - трава: grass_medium_01, grass_medium_02, grass_bermuda_01;
  - растения: shrub_03, shrub_04, shrub_sorrel_01, weed_plant_02, periwinkle_plant, calathea_orbifolia_01, moss_01;
  - коряги и корни: dead_tree_trunk_02, dry_branches_medium_01, root_cluster_01, single_root;
  - утварь: wooden_lantern_01, carved_wooden_plate, ceramic_pot, brass_pot_01.
- **Удалены 9 моделей:** в источнике у них нет UV — anthurium, bark_debris, pachira_aquatica, rock_09, sand_rocks_small, shrub_01, treasure_chest, tree_small_02, wooden_bowl_01.
- **Текстуры:** `*_Albedo.png`, `*_Normal.jpg`, `*_Mask.png`.
  - Mask — юнитевская HDRP-маска: R = metallic, G = AO, B = detail, A = smoothness (= 1 − roughness).
  - OBJ-импортёр Godot подхватывает только albedo и normal из .mtl.
- **Трава и листья:** импортированный материал не включает альфу, поэтому листья рисуются «палками».
  - Нужно задать свой StandardMaterial3D с Alpha Scissor и Cull Disabled, альфа из albedo PNG.
  - Удобнее сохранить меш как `.res` и назначить материал-override.

### 3.3 `ships/dutch_ship_medium_2k.glb` (CC0, Poly Haven)

- **Авторы:** James Ray Cock, Nicolò Zubbini, Rico Cilliers. Взят через `nauvalrizz/senja-assets`.
- **Применение:** голландский парусник (27 МБ, 2K-текстуры) — торговый корабль или затонувший остов.
- **Совет:** для остова повернуть, утопить и отключить паруса.

### 3.4 `khronos/` (CC0, `KhronosGroup/glTF-Sample-Assets`)

- `BarramundiFish.glb` — реалистичная рыба (Microsoft, CC0), для еды и подводной фауны.
- `Lantern.glb` — фонарь (sbtron / Microsoft, CC0).
- `WaterBottle.glb` — бутылка воды (Microsoft, CC0), для мусорного пляжа.

### 3.5 `arms_placeholder/` (CC0, wriks, `github.com/wwwriks/wrad-arms`)

- **Что это:** FPS-руки — 1200 треугольников, IK-риг, 2 цвета кожи, 512 px.
- **Стиль:** ретро (Half-Life 1), **только заглушка** для отладки вида от первого лица и анимаций удара или рубки.
- В игре **не используется**: руки от первого лица теперь свои (см. 3.6).

### 3.6 `fp_hands/` (свои, генерируются кодом проекта)

- `fp_arm.json` — кисть и предплечье (9k треуг., 17 костей, веса скиннинга, цвет кожи и затенение в вершинах), рукав с закатанным краем, ремешок часов. Генератор: `tools/gen_fp_hands.py` (SDF → marching cubes → упрощение; нужны numpy, scikit-image, fast-simplification). Сборка и позы пальцев — `scripts/player/fp_hands.gd`, кожа — `scripts/player/fp_skin.gdshader`. Сторонних ассетов нет.
- Проверено на GitHub (2026-11): `gdquest-demos/godot-4-FPS-arms` — модели CC-BY-NC-SA (некоммерческая, не подходит); `Ayush-Mohanty/FPS-Arms-3D` (MIT) — руки в тактических перчатках с автоматом, происхождение модели неясно, стиль не наш.

---

## 4. HDRI неба (`assets/hdri/`) — CC0, Poly Haven, 1K .hdr

| Файл | Время суток |
|---|---|
| kloofendal_48d_partly_cloudy_puresky | день, облака, чистое небо без земли — основной |
| kiara_1_dawn | рассвет |
| spruit_sunrise | восход |
| venice_sunset | закат |
| satara_night | ночь |
| moonless_golf | тёмная ночь |

**Использование:** `PanoramaSkyMaterial.panorama = load(...hdr)`, Environment → Background Sky, Ambient Sky.
С Sky3D HDRI не нужны: можно оставить их для меню или для отражений.

---

## 5. Звуки (`assets/sounds/`)

### 5.1 `oculus_pack/` — 74 OGG, **CC BY 4.0**

- **Источник:** «Oculus Audio Pack 01» by Oculus VR, LLC, через `facebookincubator/Meta-open-sound`.
- **Лицензия:** `LICENSE_CC-BY-4.0.txt`, `ATTRIBUTION.md`.
- **Обязательно в титрах игры:**
  > "Oculus Audio Pack 01" by Oculus VR, LLC (https://developers.meta.com/vr/downloads/package/oculus-audio-pack-1/), licensed under CC BY 4.0. Files renamed to the UCS naming convention; OGG previews transcoded from the original WAVs.

| Категория | Файлы |
|---|---|
| Прибой / море | AMBSea_BeachWavesStonesBirds_LOOP_01, WATRWave_OceanWaves_LOOP_01, WATRLap_WaterLapping_LOOP_01, AMBUndwtr_Underwater_LOOP_01, WATRBubl_WaterBubbles_LOOP_01 |
| Пресная вода | WATRFlow_CreekInWoods_LOOP_01, WATRFall_Waterfall_LOOP_01 |
| Лес / ветер / дождь | AMBForst_Forest_LOOP_01, AMBForst_Night_LOOP_01, AMBForst_ForestBirds_OS_01–03, WINDVege_LightWindTreesBirds_LOOP_01, WINDVege_WindTreesBirdsFlies_LOOP_01, RAINVege_ForestRain_LOOP_01, RAINInt_ForestCabinRain_LOOP_01 |
| Рубка / дерево | **WEAPAxe_WoodCutAxe_OS_01**, TOOLHand_WoodCutSaw_OS_01, WOODImpt_LargeWoodDrop_OS_01 (падение бревна), WOODFric_LargeWoodMetalDrag_OS_01, WOODFric_CreaksCreepy_OS_01/02 (скрип мостов) |
| Шаги | FEETHmn_Shoe{Dirt,Grass,Wood}{Walk 01–04, Run 01–03, Land 01} — песок ≈ Dirt, мосты = Wood |
| Лодка / флаг | BOATRow_RowboatOarRowing_OS_01–03, CLOTHFlp_FlagFlapping_LOOP_01 (наш флаг!) |
| Игрок | HMNBrth_MaleBreathing (усталость), VOXEfrt_Male01Effort, VOXMale_Male01Hurt_01/02, VOXMale_Male01Death_01, CLOTHMvmt_ClothingMovement_01/02, OBJBag_KnapsackLeather{Open,Close} (инвентарь) |
| Бой | SWSH_Swoosh_OS_01–03 (взмах), FGHTImpt_PunchRegular_01/02, FGHTImpt_Kick_01, GORESqsh_BloodSquishSlimy_01, METLImpt_MetalHitSurface_01 |
| Животные | ANMLFarm_PigSqueal_OS_01/02 (кабан), BIRDFowl_Duck_OS_01 |
| UI | UIClick_Wood{Confirm,Open,Close}, UIAlert_WoodError |

### 5.2 `sfx-kit/` — 3 WAV, CC0 (`wyzowl/sfx-kit`)

props-splash.wav (всплеск), cinematic-thunder-big.wav (гроза), foley-wood-touch.wav. Лицензия: `LICENSE_CC0.txt`.

---

## 6. Чего не хватает (не найдено на GitHub в реалистичном виде под свободной лицензией)

| Нужно | Что делать |
|---|---|
| **Кокосовые пальмы**, тропические деревья | Процедурная пальма: изогнутый ствол из сегментов с `palm_bark` / `palm_tree_bark` + карточки листьев `Leaf00x` (opacity). Либо скачать CC0 пальмы Poly Haven вручную (сайт недоступен из нашей среды) и положить через десктоп-приложение. |
| Акулы, крабы, змеи, черепахи, крокодил, птицы, обезьяны | Реалистичных CC0/CC-BY на GitHub нет (только low-poly). Вариант: Sketchfab CC-BY модели, скачанные пользователем вручную; на старте — процедурные/простые меши-заглушки. Для рыб — BarramundiFish. |
| Реалистичные FPS-руки, человек с ригом | Руки сделаны процедурно (3.6). Если найдётся сканированная модель: glTF/GLB, CC0/CC-BY, кисть+предплечье до локтя, 5–20k треуг., PBR-текстуры кожи 2K (albedo/normal/roughness), кости: forearm, hand, thumb1–3, index1–3, middle1–3, ring1–3, pinky1–3 (локальная -Z вдоль кости, +Y — тыл). Тело целиком — MakeHuman (CC0 экспорт). |
| Топор, нож, копьё, инструменты | Не найдено. Простое моделирование в Blender (топорище — цилиндр + `rough_wood`, лезвие — `dark_rock`/металл) или процедурно в Godot. |
| Кокос, ракушки, плавник, бутылки | Плавник — `dead_tree_trunk`/`single_root`; бутылка — `WaterBottle.glb`; кокос — сфера с `palm_bark`. Ракушек нет. |
| Звук: крики чаек, тропические птицы, огонь/костёр, акула, плеск плавания | Ветер/птицы леса есть; огня нет. Можно дополнить с Freesound (CC0-фильтр) вручную. |

## 7. Технические заметки

- **KTX2.** Godot не импортирует .ktx2.
  - Конвертация через транскодер three.js: `tools/ktx2_to_png.js` (UASTC+Zstd → RGBA PNG). Нужны `npm i three pngjs` и рядом `basis_cjs.js` = `three/examples/jsm/libs/basis/basis_transcoder.js` + `module.exports = BASIS` (wasm положить рядом).
- **Упакованные JSON-меши** конвертируются в GLB скриптом `tools/pack_to_glb.py`.
- **Обход сети не использовался.** Сайты polyhaven.com и ambientcg.com из нашей среды недоступны, их ресурсы взяты из зеркальных репозиториев на GitHub.
- **Рекомендуемая версия Godot — 4.7.x.** Terrain3D 1.0.1 требует ≥ 4.4, Sky3D — ≥ 4.3.

---

## Бюджеты для своих моделей

Цель — стабильные 60 FPS на «высоком» на современных ноутбуках (Apple M-серия, RTX 3050 и выше) и плавная игра на «низком» на встроенной графике. Ниже лимиты для одной модели. Проверка: `godot --headless --path . -s res://tools/asset_audit.gd -- res://assets/<папка_пака>` (отчёт ещё и в `user://asset_audit.txt`).

### Треугольники, поверхности, текстуры

| Категория (по имени файла или папки) | Треугольники LOD0 | Поверхностей (материалов) | Текстуры |
|---|---|---|---|
| Дерево / пальма | до 12 000 | до 3 (ствол, крона, кокосы) | 2048, крона — атлас с альфой |
| Куст | до 3 000 | до 2 | 1024 |
| Растение / трава / папоротник | 1 500 / 400 / 1 500 | 1–2 | 512–1024 |
| Камень / валун | до 4 000 | 1 | 2048 для валунов, 1024 для мелких |
| Животное | до 10 000 | до 3 | 2048 (мелкие звери — 1024) |
| Персонаж / руки от первого лица | до 25 000 | до 4 | 2048 |
| Деталь постройки (бревно, стена, крыша) | до 3 000 | до 2 | 2048, общий атлас дерева |
| Целая постройка / остов корабля | до 20 000 / 40 000 | до 4 / 6 | 2048 |
| Предмет / оружие | до 2 500 / 6 000 | до 2 | 1024 |

- **Поверхностей важнее, чем треугольников.** Каждая поверхность — отдельный вызов отрисовки (и ещё по одному на каждый каскад тени). Объединяйте материалы в атлас.
- **Текстуры.** Стороны — степень двойки. Больше 2048 — только для крупных объектов. Набор: albedo, normal, ORM (AO/roughness/metallic в одной текстуре). Отдельные roughness и metallic не нужны.
- **Сжатие.** В 3D — VRAM Compressed с mipmaps (Godot ставит само, если текстура используется в 3D; аудит предупредит про Lossless). Для macOS включено ETC2/ASTC.

### LOD

- **Автоматические LOD.** В импорте включено «Generate LODs», это стоит по умолчанию для всего проекта (`importer_defaults`). Godot сам строит упрощённые уровни. Порог управляется пресетом графики (`mesh_lod_threshold`).
- **Свой дальний LOD для деревьев и крупных камней.** Желателен: отдельный файл `<имя>_lod1.glb` (≈ 25 % треугольников, без мелких веток). Дальние деревья рисуются группами MultiMesh. Подключение файлов `_lod1` к FLORA делается при интеграции пака, автоматически они пока не подхватываются.
- **Дальность видимости.** Задаётся автоматически по размеру объекта: мелочь до 45–75 м и без тени, средние до 130 м, крупные до 300–600 м (`scripts/core/auto_lod.gd`). Своя дальность у узла (`visibility_range_end`) имеет приоритет. Мета `no_auto_lod` отключает авто-LOD.

### Формат и соглашения

- **Формат.** glTF 2.0 (`.glb`). 1 единица = 1 метр, ось Y вверх, лицо модели — по −Z. Масштаб и поворот применить (Apply Transform) до экспорта.
- **Пивот.** Деревья, камни, постройки — у основания (в точке касания земли). Предметы — в центре.
- **Коллизии в glb** (суффиксы имён узлов Godot):
  - `-col` — меш + статическая коллизия по нему;
  - `-colonly` — только коллизия (невидимая), простая форма;
  - `-convcolonly` — выпуклая коллизия.

  Для деревьев и камней — простые формы (цилиндр ствола, 1–3 выпуклые оболочки), не trimesh всей модели. Подвижным объектам (звери, брёвна, предметы) — только примитивы.
- **Листья.** Alpha Scissor (не Alpha Blend), Cull Disabled; в материале не включать «Transparency: Alpha» — прозрачные объекты дорогие и не пишут глубину.
- **Анимации.** Для зверей и персонажей — скелет до 60 костей, до 4 весов на вершину.
- **Имена.** `категория_имя[_вариант][_lod1].glb`, например `tree_palm_02.glb`, `rock_boulder_01_lod1.glb`, `animal_boar.glb`. Аудит по ним определяет бюджет.

## Единый визуальный ряд (модели разных авторов)

Модели пака пользователя приходят от разных авторов: разная яркость и насыщенность текстур, запечённый свет, блеск, плотность текселей. Сводим их к одному реалистичному ряду в два слоя.

**При импорте** — `python3 tools/style/style_unify.py` (настройки — `tools/style/style_config.json`, отчёт — `assets/user_pack/STYLE_REPORT.md`):
1. маска используемых текселей по UV (поля атласа не искажают замеры);
2. альбедо: снятие лишнего запечённого света (сила по классу), медиана линейной яркости — в диапазон класса по таблицам PBR-альбедо, мягкий потолок пересветов и пол «угля», приглушение лишней насыщенности;
3. шероховатость/металл: медиана — в диапазон класса, разброс сохраняется, у органики металл = 0;
4. плотность текселей px/м в игровом масштабе (нормы по категориям; выше нормы — уменьшение текстуры, ниже — отметка в отчёте);
5. микродеталь класса (чешуйки, бугорки панциря, поры, гребни раковин, волокна коры) вмешивается в карту нормалей с периодом в метрах — одинаковая фактура вблизи.

Оригиналы один раз копируются в `assets/user_pack/_style_orig/` (те же пути) и всегда берутся оттуда — повторный запуск даёт тот же результат. Новая модель: добавить её в `style_config.json` (класс каждого материала, игровой размер, категория плотности) и запустить скрипт; морские `.res` скрипт выгружает/загружает сам через `tools/style/sea_res_io.gd`.

**В кадре** — `StyleGrade` (`scripts/core/style_grade.gd`): мягкий LUT 32³ после тонмаппинга (лёгкая S-кривая, тени в бирюзу, света тёплые, живее зелень и вода, кожа и песок не трогаются) и узкая автоэкспозиция (только Forward+). Подключён в `SkyWeather`.

**Проверка глазами** — «Полка стиля» на полигоне (точка «Полка стиля»): все модели пака рядом при одном свете, эталоны серый 18 % / белый 80 % / чёрный 3 %, F7 — до/после (оригиналы + без LUT), F8 — свет (день, пасмурно, закат, ночь), тот же ряд морских видов под водой у пирса.
