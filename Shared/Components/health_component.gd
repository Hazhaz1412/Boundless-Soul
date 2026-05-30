class_name HealthComponent
extends Node

signal health_changed(current_health: float, max_health: float)
signal health_depleted
signal hit_received(damage: float, source_position: Vector2)

@export var max_health: float = 100.0
@onready var current_health: float = max_health:
	set(value):
		current_health = clamp(value, 0.0, max_health)
		health_changed.emit(current_health, max_health)
		if current_health <= 0.0:
			health_depleted.emit()

@export var is_invincible: bool = false

func _ready() -> void:
	current_health = max_health

func damage(amount: float, source_position: Vector2 = Vector2.ZERO) -> void:
	if is_invincible or current_health <= 0.0:
		return
		
	current_health -= amount
	hit_received.emit(amount, source_position)

func heal(amount: float) -> void:
	if current_health <= 0.0:
		return # Đã chết thì không hồi máu
		
	current_health += amount
