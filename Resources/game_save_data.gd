class_name GameSaveData
extends Resource

@export var save_slot: int = 1
@export var current_level_path: String = ""
@export var player_data: PlayerSaveData = null
@export var play_time: float = 0.0
@export var save_date: String = ""

# Lưu trữ thông tin tiến trình game
@export var defeated_enemies: Array[String] = []
@export var opened_chests: Array[String] = []
@export var inventory: Array[String] = []
@export var quest_progress: Dictionary = {}
@export var world_state: Dictionary = {}
