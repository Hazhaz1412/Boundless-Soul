extends AnimatedSprite2D

# Định nghĩa các trạng thái của Boss
enum State { IDLE, CHASE, TELEPORT_ATTACK, RAW_ATTACK, COOLDOWN, SUMMON, DASH_ATTACK, VANISH_SWEEP }
var current_state: State = State.IDLE

# Thuộc tính của Boss
@export var speed: float = 140.0              # Tốc độ bay đuổi theo Player
@export var attack_range: float = 95.0         # Tầm đánh bình thường/kích hoạt chiêu thức
@export var skill_cooldown: float = 4.0        # Thời gian hồi của Skill 1
@export var teleport_distance: float = 60.0    # Khoảng cách dịch chuyển áp sát Player (gần hơn để chém trúng)
@export var hit_box_range: float = 100.0        # Tầm quét lưỡi hái thực tế cực kỳ phù hợp với scale 1.6

# Chiêu thức triệu hồi đệ (Summon Skill)
var summon_cooldown_timer: float = 16.0        # Tăng thời gian hồi lúc đầu trận lên 12 giây để người chơi nhập cuộc thở dễ hơn
var summon_cooldown_duration: float = 32.0     # Tăng thời gian hồi giữa các lần summon lên 28 giây (tránh spam gây ức chế)
var active_minions: Array = []
const MINION_SCENE = preload("res://Entities/Enemies/UndeadMinion/undead_minion.tscn")

# Tham chiếu các node
@onready var boss: CharacterBody2D = get_parent()
var player: CharacterBody2D = null

# Các biến điều khiển thời gian và đòn đánh
var cooldown_timer: float = 0.0
var cooldown_duration: float = 0.0
var teleports_remaining: int = 0
var is_striking: bool = false
var attack_has_damaged: bool = false
var is_backing_away: bool = false
var has_hit_during_combo: bool = false

func _ready() -> void:
	add_to_group("boss")
	# Khởi đầu trạng thái IDLE
	play("idle")
	
	# Đảm bảo các hoạt ảnh tấn công không bị lặp lại (loop) để tín hiệu animation_finished hoạt động chính xác
	if sprite_frames:
		sprite_frames.set_animation_loop("attack", false)
		sprite_frames.set_animation_loop("skill1", false)
	
	# Tìm tham chiếu đến player
	_find_player()
	
	# Kết nối các tín hiệu thay đổi khung hình và hoàn thành hoạt ảnh
	frame_changed.connect(_on_frame_changed)
	animation_finished.connect(_on_animation_finished)

# Hàm tìm kiếm Player trong Scene
func _find_player() -> void:
	player = get_tree().get_first_node_in_group("player")
	if not player:
		# Tìm thủ công nếu group chưa được nạp kịp thời
		var parent_node = boss.get_parent()
		if parent_node:
			for child in parent_node.get_children():
				if child is CharacterBody2D and child != boss and child.has_method("take_hit"):
					player = child
					break

func _physics_process(delta: float) -> void:
	# Nếu chưa tìm thấy player thì tiếp tục tìm kiếm
	if not player:
		_find_player()
		return

	# Cập nhật thời gian hồi chiêu
	if cooldown_timer > 0:
		cooldown_timer -= delta
		
	# Cập nhật thời gian hồi chiêu triệu hồi
	if summon_cooldown_timer > 0:
		summon_cooldown_timer -= delta

	match current_state:
		State.IDLE:
			# Đứng yên uy nghi quan sát đối thủ
			boss.velocity = Vector2.ZERO
			play("idle")
			
			var dist = _get_visual_dist_to_player()
			# Luôn hướng mặt về phía Player (Đầu sprite gốc quay sang phải, nên nếu Player ở bên trái thì lật flip_h = true)
			flip_h = (player.global_position.x < boss.global_position.x)
			
			# CƠ CHẾ TRIỆU HỒI ĐỆ: Kiểm tra khi đã hồi chiêu và số đệ sống dưới 2
			if summon_cooldown_timer <= 0:
				_clean_active_minions()
				if active_minions.size() < 2:
					start_summon()
					return
			
			# Kiểm tra kích hoạt chiêu thức khi đã hồi chiêu
			if cooldown_timer <= 0:
				var is_player_far = (dist > 150.0)
				var is_player_passive = (player.current_state == 4) # 4 tương ứng với State.HIT trong player.gd
				
				# Tỷ lệ 30% kích hoạt Ultimate lao chém quét bản đồ cực chất khi ở tầm xa!
				if dist >= 180.0 and randf() < 0.35:
					start_vanish_sweep()
				# Tỷ lệ 45% kích hoạt đòn tụ lực lướt chém siêu tốc cực ngầu khi ở khoảng cách trung bình-xa!
				elif dist >= 120.0 and dist <= 240.0 and randf() < 0.45:
					start_dash_attack()
				elif is_player_far or is_player_passive:
					# Canh lúc player ở xa hoặc đang bị động (ăn đòn/choáng) -> Dịch chuyển chém liên tục gap-close!
					start_teleport_attack()
				elif dist <= attack_range:
					# Nếu đang ở gần -> Chém chay đột kích trực tiếp!
					start_raw_attack()
			
			# Chuyển sang đuổi bắt nếu player xa tầm đánh và chưa thể kích hoạt teleport/summon
			if dist > attack_range and (cooldown_timer > 0 or (dist <= 150.0 and player.current_state != 4)) and summon_cooldown_timer > 0:
				current_state = State.CHASE
				
			# Nếu đã hồi chiêu và player nằm trong tầm, chém ngay lập tức
			elif dist <= attack_range and cooldown_timer <= 0:
				start_raw_attack()

		State.CHASE:
			# Bay đuổi theo player
			var to_player = (player.global_position - boss.global_position)
			var dist = _get_visual_dist_to_player()
			
			# Hướng mặt về phía Player (Đầu sprite gốc quay sang phải, nên nếu Player ở bên trái thì lật flip_h = true)
			flip_h = (player.global_position.x < boss.global_position.x)
			
			# CƠ CHẾ TRIỆU HỒI ĐỆ: Kiểm tra khi đang di chuyển đuổi theo player
			if summon_cooldown_timer <= 0:
				_clean_active_minions()
				if active_minions.size() < 2:
					boss.velocity = Vector2.ZERO
					start_summon()
					return
			
			# Kiểm tra kích hoạt chiêu thức khi đang đuổi theo
			if cooldown_timer <= 0:
				var is_player_far = (dist > 150.0)
				var is_player_passive = (player.current_state == 4)
				
				if dist >= 180.0 and randf() < 0.35:
					boss.velocity = Vector2.ZERO
					start_vanish_sweep()
					return
				elif dist >= 120.0 and dist <= 240.0 and randf() < 0.45:
					boss.velocity = Vector2.ZERO
					start_dash_attack()
					return
				elif is_player_far or is_player_passive:
					boss.velocity = Vector2.ZERO
					start_teleport_attack()
					return
			
			if dist <= attack_range:
				# Tiếp cận gần hơn nữa để đảm bảo lưỡi hái chém trúng người chơi tuyệt đối (tầm chém visual rất đẹp)
				if dist > 70.0:
					play("idle2")
					boss.velocity = to_player.normalized() * speed
					boss.move_and_slide()
				else:
					boss.velocity = Vector2.ZERO
					if cooldown_timer <= 0:
						start_raw_attack()
					else:
						current_state = State.IDLE
			else:
				# Sử dụng hoạt ảnh bay tuyệt đẹp 'idle2' khi di chuyển
				play("idle2")
				boss.velocity = to_player.normalized() * speed
				boss.move_and_slide()
 
		State.TELEPORT_ATTACK:
			# Không tự động di chuyển vật lý khi đang dịch chuyển tấn công
			boss.velocity = Vector2.ZERO
			boss.move_and_slide()
 
		State.RAW_ATTACK:
			# Chém chay trực tiếp không dịch chuyển
			boss.velocity = Vector2.ZERO
			boss.move_and_slide()
 
		State.DASH_ATTACK:
			# Lướt chém tụ lực (di chuyển được quản lý riêng bằng tween/lực lướt)
			boss.velocity = Vector2.ZERO
			boss.move_and_slide()
 
		State.VANISH_SWEEP:
			# Đòn ultimate quét bản đồ (di chuyển được quản lý riêng bằng tween)
			boss.velocity = Vector2.ZERO
			boss.move_and_slide()
 
		State.SUMMON:
			# Đứng yên thực hiện nghi thức triệu hồi đệ
			boss.velocity = Vector2.ZERO
			boss.move_and_slide()
 
		State.COOLDOWN:
			# Nghỉ ngơi sau chuỗi skill
			if is_backing_away:
				# Nếu chém hụt, sử dụng hoạt ảnh lướt idle2 lùi ra sau để giữ cự ly
				play("idle2")
				var back_dir = (boss.global_position - player.global_position).normalized()
				boss.velocity = back_dir * (speed * 1.5) # Lùi về phía sau nhanh hơn bình thường
				boss.move_and_slide()
				
				# Vẫn hướng mặt về phía Player trong lúc lùi
				flip_h = (player.global_position.x < boss.global_position.x)
			else:
				# Nếu hoàn thành combo bình thường hoặc đứng yên, tự động lùi nhẹ nếu player áp sát quá sát sườn (< 75px)
				var dist = _get_visual_dist_to_player()
				if dist < 75.0:
					var back_dir = (boss.global_position - player.global_position).normalized()
					boss.velocity = back_dir * (speed * 0.5)
					boss.move_and_slide()
				else:
					boss.velocity = Vector2.ZERO
					
				play("idle")
				
				# Vẫn hướng mặt về phía Player
				flip_h = (player.global_position.x < boss.global_position.x)
			
			cooldown_duration -= delta
			if cooldown_duration <= 0:
				is_backing_away = false
				current_state = State.IDLE

# Kích hoạt đòn tấn công chém chay không dịch chuyển để gây bất ngờ khi người chơi tiến lại gần
func start_raw_attack() -> void:
	current_state = State.RAW_ATTACK
	is_striking = true
	attack_has_damaged = false
	
	# Hướng mặt về phía player ngay lập tức
	flip_h = (player.global_position.x < boss.global_position.x)
	
	# Phát hoạt ảnh đánh trực tiếp tại chỗ
	play("attack")

# Kích hoạt đòn tụ lực lướt chém siêu tốc cực kỳ uy lực khi ở cự ly xa
func start_dash_attack() -> void:
	current_state = State.DASH_ATTACK
	is_striking = true
	attack_has_damaged = false
	
	# Hướng mặt về phía player ngay lập tức
	flip_h = (player.global_position.x < boss.global_position.x)
	
	# Bắt đầu phát hoạt ảnh tấn công
	play("attack")
	speed_scale = 0.85 # Hơi chậm một chút ở phase chuẩn bị giơ đao tụ lực

# Kích hoạt chiêu Ultimate: Biến mất và lao chém càn quét bản đồ với đường cảnh báo đỏ
# Kích hoạt chiêu Ultimate: Biến mất và lao chém càn quét bản đồ LIÊN TỤC 4 LẦN từ các góc ngẫu nhiên cực ngầu!
func start_vanish_sweep() -> void:
	current_state = State.VANISH_SWEEP
	is_striking = true
	
	for sweep_index in range(4):
		if current_state != State.VANISH_SWEEP or not player:
			break
			
		attack_has_damaged = false # Reset cờ gây sát thương cho mỗi cú quét lẻ để trúng nhiều lần
		
		# 1. Biến mất trước mặt người chơi (nhanh hơn ở các lượt sau)
		var fade_tween = create_tween()
		fade_tween.tween_property(self, "modulate:a", 0.0, 0.15)
		await fade_tween.finished
		
		if current_state != State.VANISH_SWEEP or not player:
			break
			
		# 2. Định vị điểm xuất phát ngoài rìa và điểm đích lướt xuyên qua player
		# Lấy góc quét ngẫu nhiên để mỗi lần lao tới từ các hướng chéo/ngang hoàn toàn khác nhau!
		var sweep_angle = randf_range(0.0, 2.0 * PI)
		var start_offset = Vector2.from_angle(sweep_angle) * 350.0 # Bắt đầu từ xa rìa
		var start_pos = player.global_position + start_offset
		var target_pos = player.global_position - start_offset.normalized() * 250.0 # Lao xuyên sâu qua sau lưng player
		
		# Đặt vị trí boss tại start_pos
		boss.global_position = start_pos
		
		# 3. Hướng mặt về phía player
		flip_h = (player.global_position.x < boss.global_position.x)
		
		# 4. Tạo đường cảnh báo đỏ Line2D cực kỳ trực quan và đẹp mắt
		var warning_line = Line2D.new()
		boss.get_parent().add_child(warning_line)
		
		warning_line.width = 90.0 # Chiều rộng 90px cực kỳ uy phong
		warning_line.default_color = Color(2.0, 0.2, 0.2, 0.10)
		warning_line.points = [start_pos, target_pos]
		
		# Hiệu ứng chớp nháy siêu tốc cảnh báo nguy hiểm khẩn cấp (3 nhịp nháy siêu tốc = 0.48s chuẩn bị)
		var warning_tween = create_tween().set_loops(3)
		warning_tween.tween_property(warning_line, "default_color:a", 0.85, 0.08)
		warning_tween.tween_property(warning_line, "default_color:a", 0.10, 0.08)
		
		# Chờ 0.5 giây để người chơi phản xạ né tránh
		await get_tree().create_timer(0.5).timeout
		
		# Xoá đường cảnh báo trước khi lao
		warning_line.queue_free()
		
		if current_state != State.VANISH_SWEEP or not player:
			break
			
		# 5. Lao chém càn quét siêu tốc!
		modulate.a = 1.0
		play("attack")
		speed_scale = 2.5
		
		# Dịch chuyển trơn tru lướt qua bằng Tween
		var dash_tween = create_tween()
		dash_tween.tween_property(boss, "global_position", target_pos, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		
		# Gây sát thương liên tục dọc đường lao chém
		var start_time = Time.get_ticks_msec()
		while Time.get_ticks_msec() - start_time < 200:
			if not is_instance_valid(player) or attack_has_damaged:
				break
			# Nếu player ở gần đường lướt của Boss và Boss đang quét qua (Phạm vi 115px đồng bộ Line2D)
			if boss.global_position.distance_to(player.global_position) < 115.0:
				var is_player_rolling = (player.current_state == 3)
				if not is_player_rolling and not player.is_invincible:
					attack_has_damaged = true
					player.take_hit(boss.global_position, 480.0) # Sát thương cao, đẩy lùi mạnh
			await get_tree().process_frame
			
		# Chờ 0.15 giây ngắn nghỉ giữa các lần lướt chém tiếp theo
		await get_tree().create_timer(0.15).timeout
		
	# 6. Kết thúc toàn bộ 4 lượt chém càn quét
	modulate.a = 1.0
	is_striking = false
	speed_scale = 1.0
	cooldown_timer = skill_cooldown * 2.2 # Tăng thời gian hồi chiêu lên 2.2 lần cho chiêu thức ultimate càn quét 4 lần
	current_state = State.COOLDOWN
	cooldown_duration = 1.2
	is_backing_away = false

# Kích hoạt Skill 1: Dịch chuyển tấn công liên hoàn
func start_teleport_attack() -> void:
	current_state = State.TELEPORT_ATTACK
	# Random số lần dịch chuyển từ 1 đến 4 lần
	teleports_remaining = randi_range(1, 4)
	has_hit_during_combo = false # Reset cờ hiệu đòn trúng của combo
	
	# Tạo hiệu ứng nháy/mờ để boss biến mất trước khi xuất hiện
	modulate.a = 0.0
	await get_tree().create_timer(0.15).timeout
	modulate.a = 1.0
	
	perform_next_teleport()

# Thực hiện từng bước dịch chuyển và tấn công
func perform_next_teleport() -> void:
	if not player:
		current_state = State.IDLE
		return
		
	if teleports_remaining <= 0:
		# Kết thúc chuỗi dịch chuyển, bắt đầu hồi chiêu
		cooldown_timer = skill_cooldown
		current_state = State.COOLDOWN
		
		# AI THÔNG MINH: Nếu TRONG CẢ CHUỖI DỊCH CHUYỂN chém liên hoàn 
		# mà người chơi đều né được tất cả (không bị dính phát nào),
		# Boss sẽ lướt lùi phòng thủ giữ cự ly trong 0.8 giây.
		if not has_hit_during_combo:
			cooldown_duration = 0.8
			is_backing_away = true
		else:
			# Đã chém trúng ít nhất 1 lần, chỉ lùi nhẹ hoặc giữ khoảng cách ngắn
			cooldown_duration = randf_range(0.25, 0.5)
			is_backing_away = false
			
		return
		
	teleports_remaining -= 1
	is_striking = true
	attack_has_damaged = false
	
	# Chọn ngẫu nhiên bên trái hoặc bên phải của player để dịch chuyển đến
	# Giới hạn góc lệch gần ngang (tối đa 30 độ) để boss luôn xuất hiện đối mặt đẹp mắt với player
	var is_left = (randf() < 0.5)
	var angle_offset = randf_range(-PI / 6, PI / 6) # Lệch tối đa 30 độ
	var random_angle = (PI + angle_offset) if is_left else (0.0 + angle_offset)
	var target_pos = player.global_position + Vector2.from_angle(random_angle) * teleport_distance
	
	# Dịch chuyển vị trí của Boss
	boss.global_position = target_pos
	
	# Quay mặt về phía player ngay lập tức (Đầu sprite gốc quay sang phải, nên nếu Player ở bên trái thì lật flip_h = true)
	flip_h = (player.global_position.x < boss.global_position.x)
	
	# Báo hiệu dịch chuyển bằng hiệu ứng phát sáng mờ nhẹ
	modulate = Color(1.5, 1.2, 2.0, 1.0) # Có chút màu tím huyền bí/ảo diệu
	
	# Phát hoạt ảnh đánh (dùng animation 'attack')
	play("attack")
	
	# Trở lại màu sắc bình thường sau khoảnh khắc teleport
	get_tree().create_timer(0.1).timeout.connect(func(): modulate = Color(1.0, 1.0, 1.0, 1.0))

# Kích hoạt chiêu thức triệu hồi đệ
func start_summon() -> void:
	current_state = State.SUMMON
	# Phát hoạt ảnh niệm chú lung linh 'skill1'
	play("skill1")
	summon_cooldown_timer = summon_cooldown_duration

# Sinh 2 đệ ở hai bên cánh tả hữu của Boss
func spawn_minions() -> void:
	_clean_active_minions()
	var spawn_slots = [
		Vector2(-55, 15), # Slot bên tả
		Vector2(55, 15)   # Slot bên hữu
	]
	
	for slot in spawn_slots:
		if active_minions.size() >= 2:
			break
		var minion = MINION_SCENE.instantiate()
		minion.global_position = boss.global_position + slot
		
		# Đưa đệ vào parent của Boss trong map để tọa độ hoạt động độc lập
		var parent = boss.get_parent()
		if parent:
			parent.add_child(minion)
		else:
			get_tree().current_scene.add_child(minion)
			
		active_minions.append(minion)

# Lọc bỏ các đệ đã bị tiêu diệt khỏi mảng
func _clean_active_minions() -> void:
	var alive = []
	for minion in active_minions:
		if is_instance_valid(minion) and not minion.is_queued_for_deletion():
			alive.append(minion)
	active_minions = alive

# Phương thức nhận sát thương từ người chơi (Chớp đỏ đẹp mắt phản hồi vật lý cực chất)
func take_hit(source_position: Vector2, _knockback_force: float = 0.0) -> void:
	# Nháy màu đỏ chói lòa báo hiệu trúng kiếm
	modulate = Color(2.5, 0.5, 0.5, 1.0)
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.15)

# Xử lý sự kiện thay đổi khung hình để gây sát thương hoặc đẻ đệ
func _on_frame_changed() -> void:
	if animation == "skill1" and current_state == State.SUMMON:
		# Triệu hồi đệ ở khung hình thứ 6 (đỉnh điểm tư thế giơ trượng niệm pháp)
		if frame == 6:
			spawn_minions()
			
	elif animation == "attack" and frame == 1 and current_state == State.DASH_ATTACK:
		pause() # Tạm dừng hoạt ảnh tại khung hình 1 để tụ lực
		
		# Tạo hiệu ứng phát sáng tụ lực màu cam rực cháy báo hiệu nguy hiểm
		modulate = Color(2.5, 1.2, 0.4, 1.0)
		
		if player:
			var target_dir = (player.global_position - boss.global_position).normalized()
			
			# Chờ 0.4 giây tụ lực để người chơi phản xạ (né tránh hoặc đỡ)
			await get_tree().create_timer(0.4).timeout
			
			if current_state == State.DASH_ATTACK:
				modulate = Color(1.0, 1.0, 1.0, 1.0)
				
				# Phát hoạt ảnh chém cực kỳ nhanh (speed_scale = 2.2)
				play("attack")
				speed_scale = 2.2
				
				# Thực hiện cú lướt chém siêu tốc bằng Tween
				# Lao trực diện để áp sát mục tiêu hoàn hảo và kết thúc ở sau lưng người chơi 30px cực đẹp!
				var dash_target = player.global_position + target_dir * 30.0
				var tween = create_tween()
				tween.tween_property(boss, "global_position", dash_target, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			
	elif animation == "attack" and is_striking and not attack_has_damaged:
		# Khung hình gây sát thương chính của đòn đánh thường nằm ở khung hình 6-9
		if frame >= 6 and frame <= 9:
			if player:
				# Tăng tầm quét hitbox lên 1.2x khi đang lướt chém siêu tốc
				var check_range = hit_box_range * 1.2 if current_state == State.DASH_ATTACK else hit_box_range
				var to_player_visual = _get_visual_vector_to_player()
				var dist = to_player_visual.length()
				
				# Xác định hướng mặt của Boss (flip_h = true là quay sang trái, flip_h = false là quay sang phải)
				var facing_dir = Vector2.LEFT if flip_h else Vector2.RIGHT
				
				# Sử dụng tích vô hướng (dot product) để kiểm tra xem Player có đứng trước mặt Boss hay không.
				var dot_product = facing_dir.dot(to_player_visual.normalized())
				
				# Cho phép quét góc rộng hơn một chút khi đang xoay lướt siêu tốc (dot_product >= -0.3)
				var required_dot = -0.3 if current_state == State.DASH_ATTACK else -0.1
				
				if dot_product >= required_dot and dist <= check_range:
					var is_player_rolling = (player.current_state == 3) # State.ROLL trong player.gd
					
					if not is_player_rolling:
						attack_has_damaged = true
						has_hit_during_combo = true # Ghi nhận trúng đòn ít nhất một lần trong combo
						
						# Chỉ thực sự gây sát thương và giật hình nếu người chơi không ở trong trạng thái bất tử phục hồi
						if not player.is_invincible:
							player.take_hit(boss.global_position, 400.0 if current_state == State.DASH_ATTACK else 350.0) # Đẩy lùi mạnh hơn khi lướt chém

# Xử lý sự kiện khi kết thúc hoạt ảnh đánh và summon
func _on_animation_finished() -> void:
	if animation == "skill1" and current_state == State.SUMMON:
		current_state = State.COOLDOWN
		cooldown_duration = 0.6 # Nghỉ ngơi ngắn sau khi niệm chú đẻ đệ
		
	elif animation == "attack":
		if current_state == State.TELEPORT_ATTACK:
			is_striking = false
			
			# Nháy mờ khi biến mất chuẩn bị cho teleport tiếp theo (không dừng chuỗi đòn nữa)
			var tween = create_tween()
			tween.tween_property(self, "modulate:a", 0.0, 0.1)
			
			# Đợi 0.25 giây giữa các lần dịch chuyển liên tục để tạo cảm giác nhịp điệu boss đòn đánh rất ảo và dồn dập
			await get_tree().create_timer(0.25).timeout
			
			# Hiện lại sprite và thực hiện đòn tiếp theo
			modulate.a = 1.0
			if current_state == State.TELEPORT_ATTACK:
				perform_next_teleport()
				
		elif current_state == State.RAW_ATTACK or current_state == State.DASH_ATTACK:
			is_striking = false
			speed_scale = 1.0 # Luôn khôi phục tốc độ animation về mặc định
			
			if current_state == State.DASH_ATTACK:
				# Đòn lướt chém siêu tốc có thời gian nghỉ cố định
				cooldown_timer = skill_cooldown * 0.95 # Cooldown chuẩn chiêu thức
				current_state = State.COOLDOWN
				cooldown_duration = 0.8
				is_backing_away = false # Đứng yên sau cú lướt chém để tạo cảm giác hồi chiêu/mệt mỏi
			else:
				# Nếu chém chay hụt, Boss cũng lướt lùi nhanh phòng thủ giữ cự ly
				if not attack_has_damaged:
					cooldown_timer = skill_cooldown * 0.5 # Hồi chiêu chém chay nhanh hơn
					current_state = State.COOLDOWN
					cooldown_duration = 0.8
					is_backing_away = true
				else:
					# Nếu chém trúng, hồi chiêu ngắn bình thường
					cooldown_timer = skill_cooldown * 0.4
					current_state = State.COOLDOWN
					cooldown_duration = randf_range(0.25, 0.5)

# Tính toán khoảng cách có điều chỉnh góc nhìn top-down (nén trục dọc Y)
func _get_visual_dist_to_player() -> float:
	if not player:
		return 9999.0
	var diff = player.global_position - boss.global_position
	# Nén trục Y bằng 0.6 để tạo hitbox hình elip dẹt, khớp với góc nhìn 2.5D
	var diff_visual = Vector2(diff.x, diff.y * 0.6)
	return diff_visual.length()

# Tính toán vector khoảng cách có nén trục Y
func _get_visual_vector_to_player() -> Vector2:
	if not player:
		return Vector2.ZERO
	var diff = player.global_position - boss.global_position
	return Vector2(diff.x, diff.y * 0.6)
