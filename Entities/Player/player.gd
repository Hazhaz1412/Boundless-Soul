extends CharacterBody2D

@export var speed : float = 300.0
@export var roll_speed : float = 350.0 # Tốc độ lăn (nhanh hơn tốc độ chạy)

# --- CHỈ SỐ NHÂN VẬT (PLAYER STATS) ---
@export var max_hp: float = 150.0
@export var hp: float = 150.0
@export var max_mana: float = 60.0
@export var mana: float = 60.0
@export var max_stamina: float = 100.0
@export var stamina: float = 100.0

@export var stamina_regen_rate: float = 35.0   # Tốc độ hồi phục thể lực mỗi giây
@export var mana_regen_rate: float = 6.0       # Tốc độ hồi phục mana mỗi giây

const DASH_EFFECT_SCENE = preload("res://VFX/DashEffect/DashEffect.tscn")
const PARRY_DODGE_VFX_SCENE = preload("res://VFX/ParryDodge/parry_dodge_vfx.tscn")

# Các trạng thái hoạt động của nhân vật
enum State { NORMAL, ATTACK_1, ATTACK_2, ROLL, HIT, BLOCK }
var current_state: State = State.NORMAL

# Biến để xếp hàng đòn đánh tiếp theo trong combo
var combo_next_attack_queued: bool = false

# Hướng di chuyển khi thực hiện lăn
var roll_direction: Vector2 = Vector2.ZERO
var roll_time_elapsed: float = 0.0

# Biến theo dõi khung thời gian phản đòn (Parry Window)
var parry_window_timer: float = 0.0
var _time_freeze_active: bool = false

# Thuộc tính bất tử (i-frame) để các thực thể khác (quái, đạn) kiểm tra trước khi gây sát thương
var is_invincible: bool = false

# Gọi node AnimatedSprite2D vào trong code
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var camera: Camera2D = $Camera2D
@onready var sound_manager: Node = $SoundManager

# Các thuộc tính rung màn hình (Camera Shake)
var shake_intensity: float = 0.0
var shake_decay: float = 12.0 # Độ giảm rung nhanh chóng để rung cảm giác sắc nét

func _ready() -> void:
	add_to_group("player")
	# Cấu hình phím di chuyển WASD, mũi tên và Space để lăn
	_setup_input_actions()
	
	# Đảm bảo hoạt ảnh block lặp lại mượt mà khi giữ nút
	if animated_sprite.sprite_frames.has_animation("block"):
		animated_sprite.sprite_frames.set_animation_loop("block", true)
	
	# Kết nối các tín hiệu thay đổi khung hình và hoàn thành hoạt ảnh để kiểm soát combo và lăn
	animated_sprite.frame_changed.connect(_on_frame_changed)
	animated_sprite.animation_finished.connect(_on_animation_finished)
	
	# Phát tín hiệu toàn cục thông báo Player đã sẵn sàng trong scene
	EventBus.player_spawned.emit(self)
	
	# Tự động cập nhật giới hạn camera theo kích thước map mới
	update_camera_limits()
	EventBus.level_transition_completed.connect(func(_level_name): update_camera_limits())

# Hàm cấu hình tự động các nút di chuyển (WASD + Arrows), Lăn (Space) và Đỡ (F)
func _setup_input_actions() -> void:
	var actions = {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"roll": [KEY_SPACE, KEY_SHIFT],
		"block": [KEY_F]
	}
	for action in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		else:
			InputMap.action_erase_events(action)
			
		for key in actions[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)

func _physics_process(delta: float) -> void:
	# Tự động hồi phục Stamina và Mana theo thời gian
	if current_state != State.ROLL: # Không hồi thể lực khi đang lăn nhào lộn
		stamina = min(max_stamina, stamina + stamina_regen_rate * delta)
	mana = min(max_mana, mana + mana_regen_rate * delta)

	# Xử lý Rung màn hình (Camera Shake)
	if shake_intensity > 0.0:
		shake_intensity = move_toward(shake_intensity, 0.0, shake_decay * delta)
		if camera:
			camera.offset = Vector2(
				randf_range(-shake_intensity, shake_intensity),
				randf_range(-shake_intensity, shake_intensity)
			)
		if shake_intensity <= 0.0 and camera:
			camera.offset = Vector2.ZERO

	if current_state == State.NORMAL:
		# Lấy hướng di chuyển dựa trên các phím đã được cấu hình (WASD / Mũi tên)
		var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		
		if direction != Vector2.ZERO:
			velocity = direction * speed
			# Khi chạy thì phát hoạt ảnh "run"
			animated_sprite.play("run")
			
			# Tự động quay mặt (Flip) dựa theo hướng di chuyển trái/phải
			if direction.x < 0:
				animated_sprite.flip_h = true  # Quay sang trái
			elif direction.x > 0:
				animated_sprite.flip_h = false # Quay sang phải
		else:
			velocity = velocity.move_toward(Vector2.ZERO, speed)
			# Khi đứng yên thì phát hoạt ảnh "idle"
			animated_sprite.play("idle")
	elif current_state == State.ROLL:
		# Di chuyển liên tục theo hướng lăn với tốc độ lăn
		velocity = roll_direction * roll_speed
		roll_time_elapsed += delta
	elif current_state == State.BLOCK:
		# Đứng yên phòng thủ, triệt tiêu vận tốc di chuyển
		velocity = Vector2.ZERO
		if parry_window_timer > 0.0:
			parry_window_timer -= delta
			
		# Nếu nhả phím F (block), quay về trạng thái bình thường
		if not Input.is_action_pressed("block"):
			current_state = State.NORMAL
			animated_sprite.play("idle")
	elif current_state == State.HIT:
		# Trong trạng thái HIT, giữ nguyên vận tốc đẩy lùi (sẽ giảm dần hoặc dừng khi hết thời gian)
		pass
	else:
		# Khi đang vung đao tấn công, giảm dần vận tốc về 0 nhanh chóng
		velocity = velocity.move_toward(Vector2.ZERO, speed * 2)

	move_and_slide()

func _input(event: InputEvent) -> void:
	# Phát hiện người chơi nhấn phím Space để Lăn
	if event.is_action_pressed("roll"):
		if current_state == State.NORMAL or current_state == State.BLOCK:
			# Chỉ cho phép lăn khi có đủ thể lực (25.0 Stamina)
			if stamina >= 25.0:
				stamina -= 25.0
				current_state = State.ROLL
				is_invincible = true # Kích hoạt trạng thái bất tử (i-frame) ngay khi bắt đầu lăn
				roll_time_elapsed = 0.0 # Reset bộ đếm thời gian bắt đầu lăn
				
				# Xác định hướng lăn:
				# Nếu đang giữ nút di chuyển, lăn theo hướng di chuyển. Nếu đứng yên, lăn theo hướng đang quay mặt.
				var move_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
				if move_dir != Vector2.ZERO:
					roll_direction = move_dir.normalized()
				else:
					roll_direction = Vector2.LEFT if animated_sprite.flip_h else Vector2.RIGHT
				
				# Phát hoạt ảnh lăn
				animated_sprite.play("roll")
				_spawn_dash_effect() # Tạo ngay đám mây khói đầu tiên tại vạch xuất phát
				if sound_manager:
					sound_manager.play_dash()
				
				# Đồng bộ hướng quay mặt của sprite theo hướng lăn (nếu lăn sang trái/phải)
				if roll_direction.x < 0:
					animated_sprite.flip_h = true
				elif roll_direction.x > 0:
					animated_sprite.flip_h = false
					
				return # Không xử lý các hành động khác cùng khung hình

	# Phát hiện người chơi nhấn giữ phím F để Đỡ đòn
	if event.is_action_pressed("block"):
		if current_state == State.NORMAL:
			current_state = State.BLOCK
			parry_window_timer = 0.20 # 0.20 giây vàng để kích hoạt Parry hoàn hảo
			animated_sprite.play("block")
			return

	# Phát hiện người chơi nhấn chuột trái để tấn công
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if current_state == State.NORMAL or current_state == State.BLOCK:
			# Chỉ cho phép tấn công khi có đủ thể lực (15.0 Stamina)
			if stamina >= 15.0:
				stamina -= 15.0
				current_state = State.ATTACK_1
				combo_next_attack_queued = false
				animated_sprite.play("attack")
				animated_sprite.frame = 0
				if sound_manager:
					sound_manager.play_sword_1()
		elif current_state == State.ATTACK_1:
			# Xếp hàng Đòn 2 khi bấm chuột trái lần nữa trong lúc Đòn 1 chưa kết thúc
			# Thể lực cho Đòn 2 sẽ được kiểm tra và trừ ở frame_changed khi bắt đầu vung kiếm đòn 2
			combo_next_attack_queued = true

# Hàm công khai để quái vật hoặc bẫy gọi khi đánh trúng nhân vật
func take_hit(source_position: Vector2, knockback_force: float = 500.0) -> void:
	# 1. Kiểm tra Né đòn hoàn hảo (Perfect Dodge) khi người chơi vừa bấm nút lăn né đúng khoảnh khắc nguy hiểm
	if current_state == State.ROLL:
		if roll_time_elapsed <= 0.15:
			_trigger_perfect_dodge()
		return

	# 2. Kiểm tra Đỡ đòn (Block / Parry)
	if current_state == State.BLOCK:
		# Xác định hướng quay mặt hiện tại của nhân vật
		var facing_dir = Vector2.LEFT if animated_sprite.flip_h else Vector2.RIGHT
		# Hướng từ nhân vật đến kẻ tấn công
		var to_attacker = (source_position - global_position).normalized()
		
		# Tích vô hướng để kiểm tra góc đón đòn (chỉ đỡ góc 135 độ phía trước mặt)
		# Góc mở 135 độ tương đương với cos(67.5 độ) ≈ 0.38
		var dot_product = facing_dir.dot(to_attacker)
		
		if dot_product >= 0.38:
			if parry_window_timer > 0.0:
				_trigger_parry()
			else:
				_trigger_normal_block()
			return
		# Nếu dot_product < 0.38, tức đòn đánh xuất phát từ sau lưng hoặc góc khuất 225 độ phía sau,
		# người chơi sẽ bị trúng đòn hoàn toàn và mất máu/bị đẩy lùi như bình thường!

	# Nếu đang bất tử (vừa bị trúng đòn trước đó), bỏ qua đòn này
	if is_invincible:
		return
		
	# Giảm máu thực tế của người chơi
	hp = max(0.0, hp - 25.0)
	if hp <= 0.0:
		_handle_player_death()
		return

	# Chuyển trạng thái sang HIT và bật chế độ bất tử
	current_state = State.HIT
	is_invincible = true
	
	# Xác định hướng đẩy lùi (ngược hướng với nguồn sát thương)
	var knockback_direction = (global_position - source_position).normalized()
	if knockback_direction == Vector2.ZERO:
		knockback_direction = Vector2.LEFT if animated_sprite.flip_h else Vector2.RIGHT
		
	# Gán vận tốc đẩy lùi
	velocity = knockback_direction * knockback_force
	
	# Phát hoạt ảnh bị thương nếu có, nếu không thì tạm dừng hoặc giữ nguyên
	if animated_sprite.sprite_frames.has_animation("get_hit"):
		animated_sprite.play("get_hit")
	
	# Bắt đầu nhấp nháy bất tử trong vòng 1 giây
	_flash_invincibility(1.0)
	
	# 1. Thời gian đẩy lùi: Vô hiệu hóa di chuyển trong 0.2 giây
	await get_tree().create_timer(0.2).timeout
	if current_state == State.HIT:
		current_state = State.NORMAL
		animated_sprite.play("idle")
		
	# 2. Thời gian bất tử: Đợi thêm 0.8 giây nữa (đủ 1.0 giây từ lúc dính đòn) thì tắt bất tử
	await get_tree().create_timer(0.8).timeout
	is_invincible = false

# Hàm tạo hiệu ứng nhấp nháy bất tử nhịp nhàng
func _flash_invincibility(duration: float) -> void:
	var flash_timer = 0.0
	var flash_interval = 0.1
	while flash_timer < duration:
		if not is_invincible:
			break
		# Thay đổi độ mờ của Sprite liên tục
		animated_sprite.modulate.a = 0.3 if animated_sprite.modulate.a == 1.0 else 1.0
		await get_tree().create_timer(flash_interval).timeout
		flash_timer += flash_interval
	animated_sprite.modulate.a = 1.0 # Trả lại sprite rõ nét bình thường

func _handle_player_death() -> void:
	print("Player Died! Đang tải lại màn chơi...")
	current_state = State.HIT
	is_invincible = true
	velocity = Vector2.ZERO
	if animated_sprite.sprite_frames.has_animation("get_hit"):
		animated_sprite.play("get_hit")
	
	# Chờ 1.5 giây để người chơi nhận biết cái chết rồi mới reload màn chơi
	await get_tree().create_timer(1.5).timeout
	get_tree().reload_current_scene()

# --- CÁC CƠ CHẾ CHIẾN ĐẤU CAO CẤP: PARRY & PERFECT DODGE ---

func _trigger_perfect_dodge() -> void:
	# Sinh ra hiệu ứng parry_dodge_vfx tại vị trí nhân vật
	_spawn_parry_dodge_vfx()
	# Tạo hiệu ứng ngưng đọng thời gian (slow-mo) cực kỳ chất để WOW người chơi
	_trigger_time_freeze(0.25, 0.2) # giảm tốc độ game xuống 0.25x trong 0.2 giây thực
	print("Perfect Dodge!")

func _trigger_parry() -> void:
	# Sinh ra hiệu ứng parry_dodge_vfx tại vị trí nhân vật
	_spawn_parry_dodge_vfx()
	# Tạo hiệu ứng ngưng đọng thời gian (Slow-motion hitstop) phản đòn rất nặng
	_trigger_time_freeze(0.15, 0.35) # giảm tốc độ game xuống 0.15x trong 0.35 giây thực
	if sound_manager:
		sound_manager.play_sword_critical()
	print("Parry!")

func _trigger_normal_block() -> void:
	# Đỡ đòn thường tiêu tốn 15.0 thể lực
	stamina = max(0.0, stamina - 15.0)
	var block_knockback = Vector2.RIGHT if animated_sprite.flip_h else Vector2.LEFT
	velocity = block_knockback * 150.0
	move_and_slide()
	print("Normal Block!")

func _spawn_parry_dodge_vfx() -> void:
	if not PARRY_DODGE_VFX_SCENE:
		return
	var vfx = PARRY_DODGE_VFX_SCENE.instantiate()
	# Đặt vị trí VFX ngay giữa thân người chơi (dịch lên Y một chút)
	vfx.global_position = global_position + Vector2(0, -10)
	# Đặt hướng quay mặt của VFX đồng nhất với người chơi
	vfx.flip_h = animated_sprite.flip_h
	# Thêm vào parent để không bị trôi theo người chơi khi di chuyển
	var parent = get_parent()
	if parent:
		parent.add_child(vfx)
	else:
		get_tree().current_scene.add_child(vfx)

func _trigger_time_freeze(time_scale: float, duration: float) -> void:
	if _time_freeze_active:
		return
	_time_freeze_active = true
	Engine.time_scale = time_scale
	# Sử dụng ignore_time_scale = true (tham số thứ 4) để đếm đúng thời gian thực của con người
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
	_time_freeze_active = false

func _perform_sword_hit_sweep() -> void:
	# Cấu hình tầm chém của kiếm
	var attack_range: float = 85.0
	
	# Hướng mặt của player (flip_h = true là quay sang trái, flip_h = false là quay sang phải)
	var facing_dir = Vector2.LEFT if animated_sprite.flip_h else Vector2.RIGHT
	
	# Tìm tất cả kẻ địch thuộc nhóm boss và nhóm đệ trong scene
	var targets = []
	targets.append_array(get_tree().get_nodes_in_group("enemies"))
	targets.append_array(get_tree().get_nodes_in_group("boss"))
	
	var hit_connected: bool = false
	for target in targets:
		if target == self or not is_instance_valid(target):
			continue
			
		# Khoảng cách elip nén trục Y giống như Boss để tạo góc nhìn 2.5D premium
		var diff = target.global_position - global_position
		var diff_visual = Vector2(diff.x, diff.y * 0.6)
		var dist = diff_visual.length()
		
		# Tích vô hướng để kiểm tra góc nhìn (dot >= 0.1 nghĩa là góc chém khoảng 160 độ phía trước mặt)
		var dot = facing_dir.dot(diff_visual.normalized())
		
		if dist <= attack_range and dot >= 0.1:
			if target.has_method("take_hit"):
				# Thực hiện đòn chém trúng, đẩy lùi nhẹ đối thủ
				target.take_hit(global_position, 280.0)
				hit_connected = true
				
	if hit_connected:
		# Cảm giác đòn đánh (Hitstop & Camera Shake) cực kỳ meaty
		shake_intensity = 3.5 # Rung nhẹ màn hình
		_trigger_time_freeze(0.04, 0.06) # Khựng game lại 0.06 giây thực ở 4% tốc độ

func _on_frame_changed() -> void:
	if animated_sprite.animation == "attack":
		if current_state == State.ATTACK_1:
			# Chém trúng địch ở frame chém kiếm đẹp nhất của đòn 1
			if animated_sprite.frame == 2:
				_perform_sword_hit_sweep()
			# Đòn 1 (frames 0-5) hoàn thành và bắt đầu bước qua khung hình 6
			elif animated_sprite.frame == 5:
				if combo_next_attack_queued and stamina >= 15.0:
					stamina -= 15.0
					# Chuyển tiếp mượt mà sang Đòn 2
					current_state = State.ATTACK_2
					combo_next_attack_queued = false
					# Hoạt ảnh sẽ tự động tiếp tục phát từ khung hình 6 đến hết
					if sound_manager:
						sound_manager.play_sword_2()
				else:
					# Nếu không xếp hàng đòn tiếp theo hoặc không đủ thể lực, kết thúc tấn công và về NORMAL
					current_state = State.NORMAL
					animated_sprite.play("idle")
		elif current_state == State.ATTACK_2:
			# Chém trúng địch ở frame chém kiếm đẹp nhất của đòn 2
			if animated_sprite.frame == 8:
				_perform_sword_hit_sweep()
			# Nếu hoạt ảnh lặp lại và quay về 0
			elif animated_sprite.frame == 0:
				current_state = State.NORMAL
				animated_sprite.play("idle")
	elif animated_sprite.animation == "roll":
		# Tạo khoảng hở tổn thương (Window of vulnerability)
		# Tắt bất tử khi chuẩn bị kết thúc hoạt ảnh lăn (ở khung hình thứ 9 trên tổng số 12 khung hình: 0-11)
		if animated_sprite.frame == 9:
			is_invincible = false
		# Đề phòng hoạt ảnh lăn bị lặp ngoài ý muốn (tự ngắt ở frame cuối 11)
		elif animated_sprite.frame == 11:
			current_state = State.NORMAL
			is_invincible = false
			animated_sprite.play("idle")

func _on_animation_finished() -> void:
	# Đảm bảo trả nhân vật về trạng thái NORMAL và tắt bất tử sau khi hoạt ảnh kết thúc
	if animated_sprite.animation == "attack" or animated_sprite.animation == "roll":
		current_state = State.NORMAL
		is_invincible = false
		animated_sprite.play("idle")

# Tạo hiệu ứng khói lướt dash/roll đẹp mắt
func _spawn_dash_effect() -> void:
	if not DASH_EFFECT_SCENE:
		return
	var effect = DASH_EFFECT_SCENE.instantiate()
	var parent = get_parent()
	if parent:
		parent.add_child(effect)
	else:
		get_tree().current_scene.add_child(effect)
	
	# Đặt khói ở PHÍA SAU hướng lăn của nhân vật một chút (offset 24px)
	# và dịch xuống chân (Y + 10) để khói tự nhiên tỏa ra từ gót chân lướt đi của player
	var offset_dist = 24.0
	effect.global_position = global_position - roll_direction * offset_dist + Vector2(0, 10)
	effect.flip_h = animated_sprite.flip_h

# --- HỆ THỐNG GIỚI HẠN CAMERA TỰ ĐỘNG (AUTO CAMERA LIMITS) ---
func update_camera_limits() -> void:
	if not is_inside_tree() or not camera:
		return
		
	# Chờ 1 frame ngắn để các Node trong scene mới được load hoàn toàn vào Tree
	await get_tree().process_frame
	
	if not is_inside_tree():
		return
	
	# 1. Tìm node thuộc nhóm "camera_limit" để lấy giới hạn tùy biến trước (nếu người dùng tự vẽ)
	var limit_nodes = get_tree().get_nodes_in_group("camera_limit")
	if limit_nodes.size() > 0:
		var limit_node = limit_nodes[0]
		if limit_node is Sprite2D:
			_set_camera_limits_from_sprite(limit_node)
			return
		elif limit_node is ReferenceRect:
			camera.limit_left = int(limit_node.global_position.x)
			camera.limit_top = int(limit_node.global_position.y)
			camera.limit_right = int(limit_node.global_position.x + limit_node.size.x * limit_node.global_scale.x)
			camera.limit_bottom = int(limit_node.global_position.y + limit_node.size.y * limit_node.global_scale.y)
			print("📸 Camera: Đã cập nhật giới hạn từ ReferenceRect")
			return
			
	# 2. Tự động tìm kiếm đệ quy Sprite2D làm nền của scene hiện tại (kể cả khi bị lồng nhiều lớp)
	var current_scene = get_tree().current_scene
	if not current_scene:
		return
		
	var map_sprite = _find_map_sprite(current_scene)
	if map_sprite:
		_set_camera_limits_from_sprite(map_sprite)

func _find_map_sprite(node: Node) -> Sprite2D:
	if node is Sprite2D and node.texture != null:
		# Nhận diện ảnh nền map lớn thông qua kích thước texture (> 200px)
		if node.texture.get_width() > 200:
			return node
	for child in node.get_children():
		var found = _find_map_sprite(child)
		if found:
			return found
	return null

func _set_camera_limits_from_sprite(sprite: Sprite2D) -> void:
	var texture = sprite.texture
	if not texture:
		return
		
	var sprite_size = texture.get_size() * sprite.scale
	
	if sprite.centered:
		camera.limit_left = int(sprite.global_position.x - sprite_size.x / 2)
		camera.limit_top = int(sprite.global_position.y - sprite_size.y / 2)
		camera.limit_right = int(sprite.global_position.x + sprite_size.x / 2)
		camera.limit_bottom = int(sprite.global_position.y + sprite_size.y / 2)
	else:
		camera.limit_left = int(sprite.global_position.x)
		camera.limit_top = int(sprite.global_position.y)
		camera.limit_right = int(sprite.global_position.x + sprite_size.x)
		camera.limit_bottom = int(sprite.global_position.y + sprite_size.y)
		
	print("📸 Camera: Tự động giới hạn theo Sprite2D (", sprite.name, "): ", 
		  "L:", camera.limit_left, " T:", camera.limit_top, 
		  " R:", camera.limit_right, " B:", camera.limit_bottom)
