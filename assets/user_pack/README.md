# Пак моделей пользователя (Артём)

Источник — личный пак моделей пользователя (внешний SSD, папка MODELS). Исходные архивы в репозиторий не кладутся;
здесь только результат нормализации `tools/asset_normalize.py` под бюджеты из ASSETS.md («Бюджеты для своих моделей»).

- `animals/animal_shark_great_white.glb` — «Realistic Animated Great White Shark»: 24k → 7.1k треуг., 29 костей,
  анимации swim, swim_fast, bite, bite_2, idle, turn_left/right, hurt, die, eat; тело 2048, зубы/дёсны/глаза 256.
- `trees/tree_palm_coconut_user.glb` — «CoconutPalm» (SpeedTree, FBX): 224k → 8.7k треуг., 10 → 4 материала.
  В архиве НЕТ текстур (FBX ссылается на .tga с чужого диска C:\…), поэтому ствол — кора `palm_bark`
  из проекта, листва/кокосы — цвет. Листочки заменены ромбами (2 треуг. на листочек).
- `seaweed/seaweed_algae_atlas.png` — атлас 2048×1024 из 8 фото водорослей «Green-Algae» (563 МБ → 1.4 МБ),
  для «карточных» водорослей с расталкиванием пловцами (shaders/sea_push.gdshaderinc).

Отчёт до/после — `REPORT.md`, `report.json`. Повторить: `python3 tools/asset_normalize.py <batch.json>`.
