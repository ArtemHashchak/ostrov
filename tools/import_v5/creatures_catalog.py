#!/usr/bin/env python3
"""Каталог ассетов агента B (docs/V5_AGENTS.md, контракт 1): существа, море, предметы, оружие, персонажи, транспорт.
Пишет assets/catalog/{creatures,sea,items,weapons,characters,vehicles}.json. Запуск из корня репо:
    python3 tools/import_v5/creatures_catalog.py
Записи с no_spawn = true уже призываются своими реестрами (Animal/UserClipRig, SeaSkel, пак моря) — консоль их не дублирует."""
import json, os
K = "KODAK/Остров/MODELS/"
U = "res://assets/user_pack/"
LIC = "модели пользователя (KODAK)"
def e(id, name, cat, scene, size, zones, src, collision="none", hitbox="box", climate=True, tags=(), **kw):
    d = {"id": id, "name": name, "category": cat, "scene": scene, "lod": kw.pop("lod", []), "zones": list(zones),
         "size_m": list(size), "collision": collision, "hitbox": hitbox, "density": kw.pop("density", 1.0),
         "cluster": kw.pop("cluster", 0.0), "source": K + src, "license": LIC, "climate_ok": climate, "tags": list(tags)}
    d.update(kw)
    return d
creatures = [
    # уже в игре (Animal + UserClipRig): только запись каталога
    e("snake_green_pit_viper", "Зелёная куфия", "creature", U + "animals/snakes/snake_green_pit_viper.glb", (0.9, 0.08, 0.1), ["jungle", "lowland_forest"], "Змеи/Зелёная куфия", tags=["snake", "venom"], no_spawn=True, spawn_id="snake"),
    e("snake_blue_pit_viper", "Синяя куфия", "creature", U + "animals/snakes/snake_blue_pit_viper.glb", (0.75, 0.07, 0.1), ["jungle"], "Змеи/Синяя куфия (Trimeresurus insularis)", tags=["snake", "venom"], no_spawn=True, spawn_id="snake"),
    e("snake_ball_python", "Королевский питон", "creature", U + "animals/snakes/snake_ball_python.glb", (1.3, 0.12, 0.15), ["jungle", "lowland_forest"], "Змеи/Королевский питон", climate=False, tags=["snake"], no_spawn=True, spawn_id="python"),
    e("snake_carpet_python", "Ковровый питон", "creature", U + "animals/snakes/snake_carpet_python.glb", (1.8, 0.14, 0.18), ["jungle", "rocks"], "Змеи/Ковровый питон", tags=["snake"], no_spawn=True, spawn_id="python"),
    e("varan_komodo", "Комодский варан", "creature", U + "animals/varan/varan_komodo.glb", (2.6, 0.6, 0.6), ["beach", "lowland_forest", "dunes"], "Ящерицы/Варан (комодский)", collision="solid", tags=["predator"], no_spawn=True, spawn_id="monitor"),
    e("iguana_green", "Зелёная игуана", "creature", U + "animals/iguana/iguana_green.glb", (1.5, 0.3, 0.3), ["rocks", "palm_belt", "beach"], "Ящерицы/Игуана зелёная", no_spawn=True, spawn_id="iguana"),
    e("salamander_fire", "Огненная саламандра", "creature", U + "animals/salamander/salamander_fire.glb", (0.2, 0.05, 0.06), ["jungle", "cave"], "Ящерицы/Саламандра огненная", climate=False, no_spawn=True, spawn_id="salamander"),
    e("lizard_user", "Ящерица", "creature", U + "animals/lizard/lizard_user.glb", (0.3, 0.06, 0.08), ["rocks", "palm_belt"], "Ящерицы/Ящерица (готовая модель)", no_spawn=True),
    e("centipede_giant", "Гигантская сколопендра", "insect", U + "animals/centipede/centipede_giant.glb", (0.28, 0.03, 0.05), ["jungle", "cave"], "Насекомые/Сколопендра гигантская", tags=["venom"], no_spawn=True, spawn_id="centipede"),
    e("spider_tarantula", "Паук-птицеед", "insect", U + "animals/spider/spider_tarantula.glb", (0.2, 0.08, 0.2), ["jungle", "lowland_forest"], "Насекомые/Паук-птицеед", tags=["venom"], no_spawn=True, spawn_id="spider"),
    e("hermit_crab_brown", "Рак-отшельник", "creature", U + "animals/hermit_crab/hermit_crab_brown.glb", (0.15, 0.1, 0.12), ["beach"], "SEA/Краб-отшельник (бурый)", no_spawn=True, spawn_id="hermit_crab"),
    e("crab_user", "Краб", "creature", U + "animals/crab/crab_user.glb", (0.3, 0.12, 0.25), ["beach"], "SEA/Animals and fish (crab.blend)", no_spawn=True, spawn_id="crab"),
    e("bat_user", "Летучая мышь", "creature", U + "animals/bat/bat_user.glb", (0.35, 0.05, 0.15), ["cave", "jungle"], "Звери/Летучая мышь (бурая)", no_spawn=True, spawn_id="bat"),
    e("parrot_pionus_bluehead", "Синеголовый попугай", "bird", U + "animals/parrots/parrot_pionus_bluehead.glb", (0.27, 0.27, 0.1), ["jungle", "lowland_forest"], "Птицы/Попугай синеголовый", climate=False, no_spawn=True, spawn_id="parrot"),
    e("parrot_kea", "Попугай кеа", "bird", U + "animals/parrots/parrot_kea.glb", (0.37, 0.3, 0.12), ["rocks", "forest_edge"], "Птицы/Попугай кеа", climate=False, no_spawn=True, spawn_id="parrot"),
    e("parrot_macaw_red", "Красный ара", "bird", U + "animals/parrots/parrot_macaw_red.glb", (0.69, 0.45, 0.15), ["jungle", "lowland_forest"], "Птицы/Попугай ара", climate=False, no_spawn=True, spawn_id="parrot", tags=["v5"]),
    # новые v5: статичные модели (клипов у автора нет) — призываются консолью, общий хитбокс
    e("frog_tree", "Лягушка", "creature", U + "animals/frog/animal_frog.glb", (0.08, 0.06, 0.1), ["jungle", "mangrove"], "Ящерицы/Лягушка (готовая модель FBX)", scale=0.2, hp=4.0, tags=["v5", "static"]),
    e("butterfly", "Бабочка", "insect", U + "animals/insects/insect_butterfly.glb", (0.1, 0.03, 0.05), ["jungle", "forest_edge", "palm_belt"], "Насекомые/Бабочка (готовая модель)", scale=0.013, height=0.8, hp=1.0, tags=["v5", "static"]),
    e("parrot_amazon_perch", "Попугай амазон (на ветке)", "creature", U + "animals/parrots/bird_amazon_parrot.glb", (0.31, 0.19, 0.1), ["jungle", "lowland_forest"], "Птицы/Попугай амазон (готовая модель)", climate=False, scale=0.01, hp=6.0, drops=[{"id": "feather", "n": 2}], tags=["v5", "static"]),
]
skel = [("clownfish", "Рыба-клоун", "Рыбы/Рыба-клоун", "animal_fish_clownfish.glb", 0.1), ("tang_blue", "Синий хирург", "Рыбы/Хирург синий", "animal_fish_tang_blue.glb", 0.25),
        ("tang_yellow", "Жёлтый хирург", "Рыбы/Жёлтый хирург", "animal_fish_tang_yellow.glb", 0.18), ("tang_regal", "Королевский хирург", "Рыбы/Королевский хирург", "animal_fish_tang_regal.glb", 0.25),
        ("triggerfish_clown", "Пятнистый спинорог", "Рыбы/Спинорог-клоун", "animal_fish_triggerfish_clown.glb", 0.3), ("angel_emperor", "Императорский ангел", "Рыбы/Императорский ангел (взрослый)", "animal_fish_angel_emperor.glb", 0.37),
        ("angel_emperor_juv", "Императорский ангел (молодь)", "Рыбы/Императорский ангел (молодой)", "animal_fish_angel_emperor_juv.glb", 0.14), ("angel_blueyellow", "Сине-жёлтый ангел", "Рыбы/Рыба-ангел сине-жёлтая", "animal_fish_angel_blueyellow.glb", 0.35),
        ("copperband", "Пинцетник", "Рыбы/Хелмон (пинцетник)", "animal_fish_copperband.glb", 0.16), ("mandarin", "Мандаринка", "Рыбы/Мандаринка", "animal_fish_mandarin.glb", 0.06),
        ("aulonocara", "Аулонокара красная", "Рыбы/Аулонокара красная", "animal_fish_aulonocara_red.glb", 0.13), ("discus", "Дискус", "Рыбы/Дискус", "animal_fish_discus.glb", 0.16),
        ("barracuda", "Барракуда", "Рыбы/Барракуда", "animal_fish_barracuda.glb", 1.3), ("giant_grouper", "Гигантский групер", "Рыбы/Гигантский групер (гуаса)", "animal_fish_giant_grouper.glb", 1.85),
        ("moray", "Мурена", "Мурена", "animal_moray_eel.glb", 1.5), ("stingray", "Хвостокол", "Скат", "animal_ray_stingray.glb", 2.08), ("manta", "Манта", "Скат манта", "animal_ray_manta.glb", 3.46),
        ("dolphin", "Афалина", "Дельфин афалина", "animal_dolphin_bottlenose.glb", 2.62), ("squid_red", "Красный кальмар", "Кальмар (красный)", "animal_squid_red.glb", 0.58),
        ("turtle_green", "Зелёная черепаха", "Зелёная морская черепаха", "animal_turtle_green.glb", 1.32), ("turtle_hawksbill", "Бисса", "Черепаха бисса", "animal_turtle_hawksbill.glb", 1.08),
        ("lobster", "Лобстер", "Лобстер", "animal_lobster.glb", 0.56), ("shrimp_pistol", "Креветка-щелкун", "Креветка-щелкун", "animal_shrimp_pistol.glb", 0.074),
        ("starfish_orange", "Морская звезда", "Морская звезда (оранжевая)", "animal_starfish_orange.glb", 0.22), ("starfish_spiny", "Колючая звезда", "Морская звезда (колючая)", "animal_starfish_spiny.glb", 0.31),
        ("seacucumber_spotted", "Голотурия пятнистая", "Морской огурец (пятнистый)", "animal_seacucumber_spotted.glb", 0.27), ("seacucumber_grey", "Голотурия серая", "Морской огурец (серый)", "animal_seacucumber_grey.glb", 0.23),
        ("seahorse_yellow", "Морской конёк", "Морской конёк", "animal_seahorse_yellow.glb", 0.158), ("sardine", "Сардина", "Рыбы/Сардины (косяк)", "animal_fish_sardine.glb", 0.186),
        ("tuna", "Желтопёрый тунец", "Рыбы/Тунец (готовая модель)", "animal_fish_tuna.glb", 1.4)]
ZONES = {"barracuda": ["ocean", "reef_slope"], "giant_grouper": ["reef_slope"], "manta": ["ocean", "lagoon"], "dolphin": ["ocean", "lagoon"], "tuna": ["ocean"],
         "turtle_green": ["lagoon", "reef_slope"], "turtle_hawksbill": ["reef_crest", "reef_slope"], "stingray": ["lagoon"], "sardine": ["ocean", "lagoon"]}
sea = [e("sea_" + i, n, "sea", U + "sea_skel/" + f, (L, L * 0.4, L * 0.3), ZONES.get(i, ["reef_crest", "reef_slope", "lagoon"]), "SEA/" + s,
         collision="solid" if L >= 1.8 else "none", no_spawn=True, spawn_id=i, tags=(["v5"] if i == "tuna" else [])) for i, n, s, f, L in skel]
sea += [e("sea_piranha", "Пиранья", "sea", U + "sea/src_v5/animal_fish_piranha.glb", (0.3, 0.16, 0.06), ["mangrove", "lagoon"], "SEA/Рыбы/Пиранья (готовая модель)", climate=False, no_spawn=True, spawn_id="piranha_user", tags=["v5"]),
        e("sea_whale_humpback", "Горбатый кит", "sea", U + "sea/src_v5/animal_whale_humpback.glb", (13.0, 3.0, 4.0), ["ocean"], "SEA/Кит горбатый (готовая модель)", collision="solid", no_spawn=True, spawn_id="whale_humpback_user", tags=["v5"])]
items = [e("item_flashlight", "Фонарик", "item", U + "items/item_flashlight.glb", (0.2, 0.05, 0.05), [], "Предметы/Фонарик", item="flashlight", tags=["v5"]),
         e("item_water_bottle", "Бутылка воды", "item", U + "items/item_water_bottle.glb", (0.08, 0.25, 0.08), ["beach"], "Предметы/Бутылка для воды пластиковая", item="water_bottle", tags=["v5", "trash"]),
         e("item_lighter", "Зажигалка", "item", U + "items/item_lighter.glb", (0.04, 0.05, 0.015), [], "Предметы/Зажигалка (как Zippo)", item="lighter", tags=["v5"]),
         e("food_meat_skewer", "Жареное мясо на шпажке", "food", U + "items/item_meat_skewer.glb", (0.03, 0.15, 0.02), [], "Еда/Мясо на шпажке", item="meat_cooked", tags=["v5"]),
         e("item_dried_fish", "Сушёная рыба", "food", U + "items/item_dried_fish.glb", (0.3, 0.5, 0.1), [], "Прочее/Сушёная рыба (готовая модель)", item="smoked_fish"),
         e("ammo_box_762", "Патроны 7,62×39 (коробка)", "item", U + "items/ammo/ammo_box_762.glb", (0.07, 0.1, 0.09), [], "Оружие/Патроны и реквизит (Unreal, готовая модель)", item="rifle_ammo", tags=["v5"]),
         e("ammo_box_9mm", "Патроны 9 мм (коробка)", "item", U + "items/ammo/ammo_box_9mm.glb", (0.07, 0.12, 0.03), [], "Оружие/Патроны и реквизит (Unreal, готовая модель)", item="ammo_9mm", tags=["v5"]),
         e("ammo_box_12g", "Патроны 12 калибра (коробка)", "item", U + "items/ammo/ammo_box_12g.glb", (0.11, 0.13, 0.17), [], "Оружие/Патроны и реквизит (Unreal, готовая модель)", item="shotgun_shell", tags=["v5"]),
         e("round_762x39", "Патрон 7,62×39", "item", U + "items/ammo/round_762x39.glb", (0.011, 0.011, 0.058), [], "Оружие/Патроны и реквизит (Unreal, готовая модель)", tags=["v5", "round"]),
         e("case_762x39", "Гильза 7,62×39", "item", U + "items/ammo/round_762x39s.glb", (0.011, 0.011, 0.04), [], "Оружие/Патроны и реквизит (Unreal, готовая модель)", tags=["v5", "casing"]),
         e("round_9mm", "Патрон 9 мм", "item", U + "items/ammo/round_9mm.glb", (0.01, 0.01, 0.029), [], "Оружие/Патроны и реквизит (Unreal, готовая модель)", tags=["v5", "round"]),
         e("case_9mm", "Гильза 9 мм", "item", U + "items/ammo/round_9mms.glb", (0.01, 0.01, 0.019), [], "Оружие/Патроны и реквизит (Unreal, готовая модель)", tags=["v5", "casing"]),
         e("round_12x70", "Патрон 12/70", "item", U + "items/ammo/round_12x70.glb", (0.026, 0.026, 0.069), [], "Оружие/Патроны и реквизит (Unreal, готовая модель)", tags=["v5", "round"]),
         e("case_12x70", "Гильза 12/70", "item", U + "items/ammo/round_12x70s.glb", (0.026, 0.026, 0.076), [], "Оружие/Патроны и реквизит (Unreal, готовая модель)", tags=["v5", "casing"]),
         e("item_turtle_egg", "Черепашье яйцо", "food", U + "items/item_turtle_egg.glb", (0.05, 0.05, 0.05), ["beach"], "Еда/Яйцо (процедурное)", item="turtle_egg", tags=["v5"]),
         e("item_egg", "Птичье яйцо", "food", U + "items/item_egg.glb", (0.04, 0.057, 0.04), ["jungle", "rocks"], "Еда/Яйцо (процедурное)", tags=["v5"]),
         e("item_tourniquet", "Жгут-турникет", "item", U + "items/item_tourniquet.glb", (0.04, 0.16, 0.03), [], "Предметы/Медицина/Турникет", tags=["v5", "medical"], note="текстур в архиве автора нет (там текстуры банана) — простые материалы"),
         e("item_wooden_crate", "Деревянный ящик", "item", U + "items/item_wooden_crate.glb", (1.0, 0.41, 0.41), ["beach"], "Предметы/Ящик деревянный", collision="solid", tags=["v5", "container"]),
         e("item_sticks", "Палки (9 штук)", "item", U + "items/item_sticks.glb", (1.2, 0.07, 0.5), ["jungle", "lowland_forest", "forest_edge"], "Предметы/Палки (ресурс)", item="stick", tags=["v5", "resource"]),
         e("item_stick", "Палка", "item", U + "items/item_stick.glb", (0.07, 0.46, 0.03), ["jungle", "lowland_forest"], "Предметы/Палки (ресурс)", item="stick", tags=["v5", "resource"]),
         e("item_shell_junonia", "Ракушка", "item", U + "items/item_shell_junonia.glb", (0.1, 0.05, 0.05), ["beach"], "SEA/Ракушки/Юнония (готовая модель)", item="seashell")]
weapons = [e("weapon_ak47", "АК-47", "weapon", U + "weapons/ak47/weapon_ak47.glb", (0.05, 0.25, 0.88), [], "Оружие/Автомат АК-47", item="rifle",
             parts=["BoltCarrier", "Trigger", "Selector", "Magazine"], sockets=["muzzle", "ejection_port", "ads_anchor", "Mag", "Forend"], tags=["v5", "contract_3"]),
           e("weapon_machete", "Мачете", "weapon", U + "weapons/melee/weapon_machete.glb", (0.02, 0.67, 0.09), [], "Оружие/Мачете", item="machete", tags=["v5"]),
           e("weapon_axe", "Топор", "weapon", U + "weapons/melee/weapon_axe.glb", (0.07, 0.7, 0.24), [], "Оружие/Топор", item="axe_modern", tags=["v5"]),
           e("weapon_knife", "Нож", "weapon", U + "weapons/melee/weapon_knife.glb", (0.07, 0.3, 0.11), [], "Оружие/Нож", item="knife_combat", tags=["v5"])]
weapons.append(e("weapon_beretta_pmx", "Пистолет-пулемёт Beretta PMX", "weapon", U + "weapons/pmx/weapon_beretta_pmx.glb", (0.07, 0.29, 0.64), [], "Оружие/Пистолет Beretta",
                  parts=["Receiver", "Magazine"], note="это пистолет-пулемёт (SMG), не пистолет 9 мм — предмета пока нет", tags=["v5", "smg"]))
characters = [e("character_male", "Участник шоу (мужчина)", "character", U + "characters/character_male.glb", (0.6, 1.79, 0.36), [], "Персонажи/Мужчина (модель с анимациями)",
                clips=["idle", "walk", "run", "jump", "death"], rig="mixamo", tags=["v5", "bots", "player_body"])]
vehicles = [e("vehicle_wooden_boat", "Деревянная лодка", "vehicle", U + "vehicles/vehicle_wooden_boat.glb", (3.9, 2.9, 6.6), ["beach", "lagoon"], "Транспорт/Лодка деревянная",
                collision="solid", tags=["v5", "boat", "sail"], note="free model, game piggs creators")]
OUT = "assets/catalog"
os.makedirs(OUT, exist_ok=True)
for fn, arr in [("creatures", creatures), ("sea", sea), ("items", items), ("weapons", weapons), ("characters", characters), ("vehicles", vehicles)]:
    with open(os.path.join(OUT, fn + ".json"), "w", encoding="utf-8") as f:
        json.dump({"version": 1, "owner": "B · Существа и предметы", "generated_by": "tools/import_v5/creatures_catalog.py", "entries": arr},
                  f, ensure_ascii=False, indent=1)
        f.write("\n")
    print(fn, len(arr))
