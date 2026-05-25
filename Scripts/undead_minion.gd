extends CharacterBody2D

# Định nghĩa các trạng thái của đệ (Undead Minion)
enum State { APPEAR, SKIRMISH, LUNGE, RETREAT, DEAD }
var current_state: State = State.APPEAR

# Các thuộc tính cân bằng game
@export var max_hp: float = 3.0
var hp: float = 3.0

@export var speed: float = 100.0             # Tốc độ di chuyển nhấp nhả
@export var lunge_speed: float = 235.0       # Tốc độ phóng lao vào đánh
@export var retreat_speed: float = 210.0     # Tốc độ lùi về khi hoàn tất đòn/bị đánh trúng

# Khoảng cách tối ưu để nhấp nhả (SKIRMISH)
var skirmish_ideal_min: float = 100.0
var skirmish_ideal_max: float = 140.0

# Các biến thời gian và điều khiển
var skirmish_timer: float = 1.5
var retreat_timer: float = 0.0

# Tham chiếu các node
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var player: CharacterBody2D = null

# Sát thương gây ra cho player
var damage_dealt: bool = false

# Bất tử tạm thời khi bị thương
var is_invincible: bool = false
var invincibility_timer: float = 0.0

func _ready() -> void:
	add_to_group("enemies") # Thêm vào nhóm enemies để player phát hiện chém trúng
	hp = max_hp
	
	# Khởi đầu với hoạt ảnh xuất hiện 'appear' cực kỳ chất
	current_state = State.APPEAR
	animated_sprite.play("appear")
	
	# Kết nối sự kiện kết thúc hoạt ảnh xuất hiện/biến mất
	animated_sprite.animation_finished.connect(_on_animation_finished)
	
	# Tìm player
	_find_player()

func _find_player() -> void:
	player = get_tree().get_first_node_in_group("player")
	if not player:
		# Tìm thủ công qua Scene tree nếu group chưa kịp sẵn sàng
		var parent = get_parent()
		if parent:
			for child in parent.get_children():
				if child is CharacterBody2D and child != self and child.has_method("take_hit"):
					player = child
					break

func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		velocity = Vector2.ZERO
		return
		
	if not player:
		_find_player()
		return
		
	# Giảm thời gian bất tử
	if invincibility_timer > 0.0:
		invincibility_timer -= delta
		if invincibility_timer <= 0.0:
			is_invincible = false
			animated_sprite.modulate.a = 1.0

	# Lấy hướng mặt sprite (Đầu sprite summonIdle quay sang phải, nên nếu Player ở bên trái thì lật flip_h = true)
	if current_state != State.APPEAR:
		animated_sprite.flip_h = (player.global_position.x < global_position.x)

	match current_state:
		State.APPEAR:
			# Đứng yên tỏa khói xuất hiện
			velocity = Vector2.ZERO
			move_and_slide()

		State.SKIRMISH:
			animated_sprite.play("idle")
			damage_dealt = false
			
			# Tích lũy thời gian đổi sang trạng thái LUNGE
			skirmish_timer -= delta
			
			# Logic nhấp nhả (SKIRMISH_KEEP_DISTANCE):
			var diff = player.global_position - global_position
			var dist = diff.length()
			var dir = diff.normalized()
			
			if dist < skirmish_ideal_min:
				# Quá gần player -> lùi lại nhẹ để giữ khoảng cách
				velocity = -dir * speed
			elif dist > skirmish_ideal_max:
				# Quá xa player -> nhích lại gần để rình rập
				velocity = dir * speed
			else:
				# Đang ở cự ly vàng -> lướt vòng quanh hoặc giảm tốc độ di chuyển
				# Tạo một chút chuyển động ngẫu nhiên theo phương tiếp tuyến để trông AI cực thông minh
				var tangent = Vector2(-dir.y, dir.x)
				velocity = tangent * (speed * 0.4)
				
			move_and_slide()
			
			# Hết thời gian nhấp nhả -> chuyển sang phóng lao (LUNGE) để tấn công
			if skirmish_timer <= 0.0:
				current_state = State.LUNGE
				damage_dealt = false
				# Khởi động lại skirmish_timer cho chu kỳ tiếp theo
				skirmish_timer = randf_range(1.0, 2.0)

		State.LUNGE:
			animated_sprite.play("idle")
			
			var diff = player.global_position - global_position
			var dist = diff.length()
			var dir = diff.normalized()
			
			# Phóng trực tiếp về phía player với tốc độ cao
			velocity = dir * lunge_speed
			move_and_slide()
			
			# Gây sát thương khi chạm vào player
			if dist <= 38.0 and not damage_dealt:
				damage_dealt = true
				if not player.is_invincible:
					player.take_hit(global_position, 200.0)
				# Sau khi chạm trúng, lập tiếp kích hoạt trạng thái lùi về phòng thủ
				start_retreat()
				
			# Nếu lướt quá tầm hoặc lạc lối quá xa mà không chạm được player
			if dist > 300.0:
				start_retreat()

		State.RETREAT:
			animated_sprite.play("idle")
			
			# Lùi nhanh theo hướng ngược lại với player
			var diff = player.global_position - global_position
			var dir = diff.normalized()
			
			velocity = -dir * retreat_speed
			move_and_slide()
			
			# Đếm ngược thời gian lùi
			retreat_timer -= delta
			if retreat_timer <= 0.0:
				current_state = State.SKIRMISH
				# Đặt thời gian nhấp nhả tiếp theo ngẫu nhiên
				skirmish_timer = randf_range(1.2, 2.5)

func start_retreat() -> void:
	current_state = State.RETREAT
	retreat_timer = 0.6 # Lùi nhanh trong 0.6 giây

func take_hit(source_position: Vector2, knockback_force: float = 300.0) -> void:
	if current_state == State.DEAD or current_state == State.APPEAR:
		return
		
	if is_invincible:
		return
		
	# Trừ HP
	hp -= 1.0
	
	# Nhấp nháy màu đỏ báo hiệu dính sát thương
	animated_sprite.modulate = Color(2.5, 0.5, 0.5, 1.0)
	get_tree().create_timer(0.12).timeout.connect(func():
		if current_state != State.DEAD:
			animated_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
	)
	
	# Bất tử ngắn để tránh dính nhiều đòn chồng lên cùng khung hình
	is_invincible = true
	invincibility_timer = 0.22
	
	# Chết nếu hết HP
	if hp <= 0.0:
		trigger_death()
		return
		
	# Bị đẩy lùi (Knockback)
	var knockback_dir = (global_position - source_position).normalized()
	if knockback_dir == Vector2.ZERO:
		knockback_dir = Vector2.LEFT if animated_sprite.flip_h else Vector2.RIGHT
	velocity = knockback_dir * knockback_force
	move_and_slide()
	
	# CƠ CHẾ YÊU CẦU: "nếu đang lao tới mà bị đánh nó sẽ lùi lại"
	# Nếu đang ở trạng thái LUNGE (đang lao vào chém) mà bị chém trúng,
	# nó sẽ lập tức bị hủy lướt chém và cưỡng chế rút lui lùi lại phòng thủ!
	if current_state == State.LUNGE:
		start_retreat()

func trigger_death() -> void:
	current_state = State.DEAD
	velocity = Vector2.ZERO
	# Tắt va chạm vật lý để xác chết không chặn đường người chơi
	collision_shape.set_deferred("disabled", true)
	
	# Phát hoạt ảnh chết rã đám khói mờ ảo 'dead'
	animated_sprite.play("dead")

func _on_animation_finished() -> void:
	if animated_sprite.animation == "appear":
		current_state = State.SKIRMISH
		skirmish_timer = randf_range(1.0, 2.0)
	elif animated_sprite.animation == "dead":
		# Giải phóng tài nguyên xác chết
		queue_free()
