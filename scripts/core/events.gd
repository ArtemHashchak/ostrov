extends Node
## Глобальная сигнальная шина. Модули НЕ ссылаются друг на друга напрямую —
## они шлют и слушают сигналы здесь. Добавлять сигналы можно (только дописывать
## в конец своего блока, не переименовывать чужие).

# --- матч ---
signal match_started(config: Dictionary)
signal match_ended(winner_team: int)
signal flag_placed(team: int, position: Vector3)
signal flag_damaged(team: int, hp: float, max_hp: float)
signal flag_destroyed(team: int, by: Node)
signal team_eliminated(team: int)

# --- персонажи ---
signal character_spawned(ch: Node)
signal character_damaged(ch: Node, amount: float, source: Node)
signal character_died(ch: Node, killer: Node)

# --- игрок / интерфейс ---
signal interact_hint_changed(text: String)
signal player_swing(player: Node, hit: Dictionary)
signal player_stamina_changed(value: float, max_value: float, tired: bool)
signal pause_toggled(paused: bool)
signal toast(text: String)

# --- инвентарь / крафт ---
signal inventory_changed(owner: Node)
signal item_crafted(owner: Node, item_id: StringName, count: int)
