extends Node

# --- PLAYER SIGNALS ---
signal player_health_changed(new_hp: float, max_hp: float)
signal player_mana_changed(new_mana: float, max_mana: float)
signal player_stamina_changed(new_stamina: float, max_stamina: float)
signal player_died
signal player_spawned(player_node: CharacterBody2D)

# --- COMBAT SIGNALS ---
signal hit_landed(attacker: Node2D, target: Node2D, damage: float)
signal perfect_dodge_triggered
signal parry_triggered

# --- ENEMY SIGNALS ---
signal enemy_spawned(enemy_node: CharacterBody2D)
signal enemy_died(enemy_node: CharacterBody2D)
signal boss_spawned(boss_node: CharacterBody2D)
signal boss_died(boss_node: CharacterBody2D)

# --- GAME & SAVE SIGNALS ---
signal save_requested(slot: int)
signal load_requested(slot: int)
signal save_completed(slot: int, success: bool)
signal load_completed(slot: int, success: bool)
signal level_transition_started(next_level_path: String)
signal level_transition_completed(level_name: String)
