# Единый визуальный ряд пака — отчёт калибровки

Сгенерировано `tools/style/style_unify.py` по `tools/style/style_config.json`. Оригиналы — `assets/user_pack/_style_orig/`.
Y — медианная линейная яркость альбедо по используемым текселям; «запечённый свет» — разброс низкочастотной log-яркости (меньше — ровнее).

| Модель / материал | Класс | Плотность px/м | Y до → после | Насыщ. до → после | Запеч. свет до → после | Шерох. до → после | Микродеталь |
|---|---|---|---|---|---|---|---|
| animal_shark_great_white.glb · Grey | shark_skin | 534 (в норме) | 0.064 → 0.069 | 0.05 → 0.05 | 0.924 → 0.924 | 0.44 → 0.44 | denticle, период 3.2 px (6 мм), сила 0.10 |
| animal_shark_great_white.glb · Gums | special_keep | — | — | — | — | — | без изменений (глаза/зубы/дёсны) |
| animal_shark_great_white.glb · Teeth | special_keep | — | — | — | — | — | без изменений (глаза/зубы/дёсны) |
| animal_shark_great_white.glb · Eyes | special_keep | — | — | — | — | — | без изменений (глаза/зубы/дёсны) |
| item_shell_junonia.glb · MAT_JunoniaShell | mollusc_shell | 2980 (в норме) | 0.392 → 0.366 | 0.49 → 0.49 | 0.246 → 0.214 | 0.26 → 0.26 | ridges, период 6.0 px (2 мм), сила 0.12 |
| item_dried_fish.glb · M_Fabric | fabric_rope | 1964 (в норме) | 0.130 → 0.133 | 0.21 → 0.21 | 0.165 → 0.137 | 0.80 → 0.80 | — |
| item_dried_fish.glb · M_Metal | metal_rusty | 2604 (в норме) | 0.220 → 0.220 | 0.00 → 0.00 | 0.047 → 0.047 | 0.33 → 0.35 | — |
| item_dried_fish.glb · M_DriedFishAtlas | dried_organic | 237 (НИЖЕ нормы (усилена микродеталь)) | 0.127 → 0.128 | 0.20 → 0.20 | 0.159 → 0.138 | 0.42 → 0.62 | пропущена: черта 8 мм = 1.9 px (< 3 px) |
| tree_palm_coconut_user.glb · Coconut | foliage | — | 0.129 → 0.129 | 0.61 → 0.56 | — | 0.60 → 0.60 | — |
| tree_palm_coconut_user.glb · FrondStem | foliage | — | 0.184 → 0.130 | 0.54 → 0.54 | — | 1.00 → 0.72 | — |
| tree_palm_coconut_user.glb · Leaflet | foliage | — | 0.208 → 0.130 | 0.59 → 0.58 | — | 0.70 → 0.70 | — |
| tree_palm_coconut_user.glb · Bark | bark | 623 (в норме) | 0.076 → 0.076 | 0.22 → 0.22 | 0.118 → 0.096 | 1.00 → 0.94 | fibres, период 6.2 px (10 мм), сила 0.12 |
| crab_user.glb · crab | crustacean | 912 (в норме) | 0.142 → 0.143 | 0.37 → 0.37 | 0.379 → 0.300 | 0.36 → 0.38 | bumps, период 3.6 px (4 мм), сила 0.18 |
| seaweed_algae_atlas.png · seaweed_algae_atlas.png | algae | — | 0.134 → 0.134 | 0.63 → 0.62 | 0.600 → 0.600 | — | — |
| fish_discus.res · fish_discus | fish_scales | 1554 (в норме) | 0.043 → 0.060 | 0.39 → 0.32 | 1.476 → 1.269 | — | у морских видов шейдер берёт только альбедо: шероховатость/микродеталь задаёт шейдер вида |
| fish_redfish.res · fish_redfish | fish_scales | 858 (в норме) | 0.274 → 0.276 | 0.47 → 0.47 | 0.459 → 0.400 | — | у морских видов шейдер берёт только альбедо: шероховатость/микродеталь задаёт шейдер вида |
| fish_tropical_spotted.res · fish_tropical_spotted | fish_scales | 2108 (в норме) | 0.299 → 0.299 | 0.32 → 0.31 | 0.301 → 0.264 | — | у морских видов шейдер берёт только альбедо: шероховатость/микродеталь задаёт шейдер вида |
| shark_pack8.res · shark_pack8 | shark_skin | 569 (в норме) | 0.047 → 0.070 | 0.09 → 0.08 | 1.082 → 1.082 | — | у морских видов шейдер берёт только альбедо: шероховатость/микродеталь задаёт шейдер вида |
| octopus.res · octopus | cephalopod | — | — | — | — | — | текстура-заглушка 64x64 — цвет задаёт шейдер вида (params color_a/color_b), не трогаем |
| squid_biolum.res · squid_biolum | cephalopod | — | — | — | — | — | текстура-заглушка 64x64 — цвет задаёт шейдер вида (params color_a/color_b), не трогаем |
