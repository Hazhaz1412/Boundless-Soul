extends CharacterBody2D

signal arrived

@export var speed: float = 120.0
@export var target_position: Vector2 = Vector2.ZERO

@export var ignore_collision: bool = false

var is_walking: bool = false
var last_position: Vector2 = Vector2.ZERO
var stuck_timer: float = 0.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	animated_sprite.play("idle")

# Hàm điều khiển Bruna đi tới vị trí đích
func walk_to(pos: Vector2) -> void:
	target_position = pos
	is_walking = true
	stuck_timer = 0.0
	last_position = global_position
	animated_sprite.play("walk")

func _physics_process(delta: float) -> void:
	if is_walking:
		var dir = (target_position - global_position).normalized()
		var dist = global_position.distance_to(target_position)
		
		# Quay mặt sprite dựa theo hướng di chuyển ngang (x)
		if dir.x < 0:
			animated_sprite.flip_h = true  # Quay sang trái (hướng đi tới từ góc phải)
		elif dir.x > 0:
			animated_sprite.flip_h = false # Quay sang phải
			
		# Phát hiện kẹt vật lý (không thay đổi vị trí đáng kể trong 1 frame)
		var movement = global_position.distance_to(last_position)
		last_position = global_position
		
		if movement < 0.2:
			stuck_timer += delta
			if stuck_timer >= 1.0: # Nếu bị kẹt cứng tại chỗ trong 1 giây
				print("🧠 Bruna bị kẹt vật lý! Tự động dừng di chuyển để tránh soft-lock hội thoại.")
				_arrive()
				return
		else:
			stuck_timer = 0.0 # Reset bộ đếm nếu vẫn di chuyển được
			
		if dist <= 4.0:
			_arrive()
		else:
			if ignore_collision:
				# Di chuyển trực tiếp bằng tọa độ để đi xuyên tường biên khi rời đi
				global_position = global_position.move_toward(target_position, speed * delta)
			else:
				# Di chuyển bằng vật lý va chạm bình thường khi đi tới người chơi để tránh đi xuyên tường
				velocity = dir * speed
				move_and_slide()

func _arrive() -> void:
	global_position = target_position
	velocity = Vector2.ZERO
	is_walking = false
	animated_sprite.play("idle")
	emit_signal("arrived")
