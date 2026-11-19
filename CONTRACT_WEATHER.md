# Контракт «Погода и ветер» (WEATHER)

Владелец: агент ПОГОДЫ (`scripts/world/sky_weather.gd`, `scripts/world/weather/`).
Мир (группа `world`, класс `World`) отдаёт:

| Вызов | Что | Значения |
|---|---|---|
| `wind_dir() -> Vector2` | направление ветра (куда дует), XZ, нормирован | медленно «гуляет» (десятки минут) |
| `wind_speed() -> float` | ветер у поверхности, м/с, с порывами | штиль/ясно 2–4, облачно ~6, дождь 8–12, шторм 18–28 |
| `gust() -> float` | порыв 0..1 (гладкий шум 0.1–0.2 Гц) | |
| `storm_intensity() -> float` | сила шторма 0..1 | ясно 0, облачно 0.1, дождь 0.35, шторм 1 |
| `rain_intensity() -> float` | сила дождя 0..1 (= `rain_factor()`) | |
| `wetness() -> float` | сырость мира 0..1: намокает ~45 с, сохнет ~7 мин | |
| `weather() / set_weather(w, instant)` | `clear/cloudy/rain/fog/storm` | |
| `signal weather_changed(w)` | начало смены погоды | переход длится ~120 с |

Всё детерминировано от `World.seed_value`; скачков нет: смена погоды — плавное
смешивание за 120 с, ветер — гладкий шум.

## Глобальные uniform для шейдеров (`project.godot [shader_globals]`)

```glsl
global uniform vec2 wind_dir;          // нормированное направление (XZ)
global uniform float wind_speed;       // м/с
global uniform float wind_gust;        // 0..1
global uniform float weather_rain;     // 0..1
global uniform float weather_storm;    // 0..1
global uniform float weather_wetness;  // 0..1
```

Обновляются каждый кадр в `SkyWeather._update_wind`.
Рябь от капель на воде — `rain_ripple_tex` / `weather_rain` (см. раздел ниже, когда появится).

## Расписание (авто-режим)
ясно 15–30 мин → облачно 8–15 → дождь 6–12 → шторм 5–10 (с вероятностями),
туман 4–8. На матч 3–4 ч выходит 1–3 дождя и 0–2 шторма.
