extends Node2D

const DIALOGUE_BOX_SCENE = preload("res://UI/Dialogue/DialogueBox.tscn")

var bruna_npc: CharacterBody2D = null

func _ready() -> void:
	# Tìm node Bruna mà người chơi kéo thả thủ công vào Scene
	bruna_npc = get_node_or_null("Bruna")
	if not bruna_npc:
		bruna_npc = find_child("Bruna") # Tìm kiếm đệ quy đề phòng cấu trúc phân cấp khác
		
	# Kiểm tra xem sự kiện Bruna mở cửa đã hoàn thành trước đó chưa (Tránh lặp lại khi quay lại map)
	if GameManager.world_state.get("dung_1_bruna_event_completed", false):
		print("🧠 GameManager: Sự kiện Bruna đã hoàn thành từ trước. Đang dọn dẹp map...")
		
		# Xóa rào chắn cửa lập tức
		var door = get_node_or_null("PlayerDoor")
		if not door:
			door = get_node_or_null("Sprite2D/PlayerDoor")
		if not door:
			door = find_child("PlayerDoor")
		if door:
			door.queue_free()
			print("🧠 [Hệ thống]: Cửa đã được mở sẵn.")
			
		# Xóa Bruna lập tức vì cô ấy đã đi mất
		if bruna_npc:
			bruna_npc.queue_free()
		return # Kết thúc sớm, không chạy cutscene nữa
		
	# Ẩn Bruna đi ngay khi vừa vào màn chơi để chuẩn bị hiệu ứng xuất hiện
	if bruna_npc:
		bruna_npc.hide()
		print("Đã tìm thấy Bruna thủ công trong Scene. Ẩn chuẩn bị spawn...")
	else:
		print("Cảnh báo: Chưa kéo thả node Bruna vào màn chơi dung_1!")
		
	print("Màn chơi khởi động. Chờ 3 giây...")
	# Đợi 3 giây
	await get_tree().create_timer(3.0).timeout
	
	start_bruna_walk_in()

func start_bruna_walk_in() -> void:
	if not is_instance_valid(bruna_npc):
		print("Không tìm thấy node Bruna hợp lệ để chạy cutscene!")
		return
		
	print("Bắt đầu di chuyển Bruna từ góc phải vào...")
	
	# Tìm vị trí hiện tại của Player
	var player = get_tree().get_first_node_in_group("player")
	var player_pos = Vector2(-271, -197) # Vị trí mặc định phòng hờ
	if player:
		player_pos = player.global_position
		
	# Đặt Bruna về đúng vị trí xuất phát SpawnPoint_FromDung2 (tương ứng x: 209.5, y: 4.5 trong Editor)
	var spawn_point = find_child("SpawnPoint_FromDung2")
	if spawn_point:
		bruna_npc.global_position = spawn_point.global_position
		print("Spawn Bruna tại vị trí: ", spawn_point.global_position)
		
	bruna_npc.show()
	
	# Cho Bruna đi thẳng tới vị trí đứng trước mặt Player theo trục ngang X, nhưng giữ nguyên cao độ Y của chính cô ấy để tránh đâm vào tường phân tầng
	var target_pos = Vector2(player_pos.x + 60, bruna_npc.global_position.y)
	bruna_npc.walk_to(target_pos)
	
	# Kết nối tín hiệu khi Bruna đi tới đích lần đầu để nói chuyện
	if not bruna_npc.arrived.is_connected(_on_bruna_arrived):
		bruna_npc.arrived.connect(_on_bruna_arrived)

func _on_bruna_arrived() -> void:
	print("Bruna đã đi tới đích! Bắt đầu hội thoại...")
	trigger_dialogue()

func trigger_dialogue() -> void:
	# Tự động cắt 1 khung hình từ Idle sheet của Bruna làm ảnh đại diện (Avatar)
	var bruna_avatar = AtlasTexture.new()
	bruna_avatar.atlas = load("res://Entities/NPC/Bruna/Assets/SeveredFangIdle001-Sheet.png")
	bruna_avatar.region = Rect2(0, 0, 128, 128)
	
	# Định nghĩa các câu thoại (Bạn có thể tự thay đổi nội dung ở đây)
	var lines: Array[Dictionary] = [
		{
			"name": "Bruna",
			"text": "Chào cậu, tôi là Bruna. Đội trưởng đội kỵ sĩ, theo lệnh của đức vua ân xá thì tôi đến để giải thoát cho cậu!",
			"avatar": bruna_avatar
		},
		{
			"name": "Bruna",
			"text": "Sau khi có được tự do, nhiệm vụ của cậu là đi tìm và giải cứu công chúa.",
			"avatar": bruna_avatar
		},
		{
			"name": "Bruna",
			"text": "Tôi sẽ mở cửa ngay bây giờ, hành trình phía trước hãy bảo trọng nhé.",
			"avatar": bruna_avatar
		}
	]
	
	# Khởi tạo hộp thoại hội thoại
	var dialogue_box = DIALOGUE_BOX_SCENE.instantiate()
	add_child(dialogue_box)
	
	# Bắt đầu chạy hội thoại
	dialogue_box.start_dialogue(lines)
	
	# Đón nhận tín hiệu khi câu thoại thay đổi để bắt đầu cắt cảnh ở câu thoại cuối cùng
	dialogue_box.line_displayed.connect(func(idx: int):
		if idx == lines.size() - 1: # Câu thoại cuối cùng!
			# Khóa không cho người chơi nhấn Z để đi tiếp
			dialogue_box.next_line_allowed = false
			
			# Kích hoạt chuỗi cắt cảnh di chuyển tới cửa, mở khóa và rời đi
			start_door_opening_sequence(dialogue_box)
	)
	
	# Đón nhận tín hiệu khi người chơi đọc xong toàn bộ hội thoại và nhấn Z cuối cùng
	dialogue_box.dialogue_finished.connect(func():
		# Giải phóng giao diện hộp thoại khỏi bộ nhớ
		dialogue_box.queue_free()
		print("Hội thoại kết thúc hoàn toàn. Người chơi bắt đầu di chuyển.")
	)

func start_door_opening_sequence(dialogue_box: CanvasLayer) -> void:
	# Ngắt kết nối sự kiện arrived cũ để tránh kích hoạt lại hội thoại khi đi tới cửa
	if bruna_npc.arrived.is_connected(_on_bruna_arrived):
		bruna_npc.arrived.disconnect(_on_bruna_arrived)
		
	# Tìm nút PlayerDoor bằng nhiều cơ chế tìm kiếm
	var door = get_node_or_null("PlayerDoor")
	if not door:
		door = get_node_or_null("Sprite2D/PlayerDoor") # Hỗ trợ cấu hình phân cấp mới
	if not door:
		door = find_child("PlayerDoor") # Tìm kiếm đệ quy
		
	if door:
		print("Bruna đang đi tới trước rào chắn để mở cửa...")
		
		# Tìm tọa độ X thực tế của cánh cửa (bởi vì node cha ở gốc 0,0 còn Sprite và Collider con của nó bị lệch)
		var target_x = door.global_position.x
		var sprite = door.find_child("HangRao2")
		if sprite:
			target_x = sprite.global_position.x
			
		# Đi tới trước cửa (cách tọa độ X thực tế của cửa 50px về bên phải, giữ nguyên Y)
		var target_pos = Vector2(target_x + 50, bruna_npc.global_position.y)
		bruna_npc.walk_to(target_pos)
		
		# Sử dụng await để chờ cho tới khi Bruna hoàn thành bước di chuyển tới cửa
		await bruna_npc.arrived
		
		print("Bruna đã tới trước rào chắn. Đứng nhìn rào chắn để hóa giải phép thuật...")
		# Đứng im nhìn cửa trong 1.0 giây đầy cinematic
		await get_tree().create_timer(1.0).timeout
		
		# Xóa rào chắn cửa
		door.queue_free()
		print("🧠 [Hệ thống]: Rào chắn PlayerDoor đã được hóa giải! Cửa đã mở.")
		
		# Lưu trạng thái sự kiện đã hoàn thành vào world_state để tránh lặp lại
		GameManager.world_state["dung_1_bruna_event_completed"] = true
		
		# Đợi thêm 0.5 giây nữa rồi mới bắt đầu quay bước ra về
		await get_tree().create_timer(0.5).timeout
		
	else:
		# Hỗ trợ lưu trạng thái kể cả khi không tìm thấy cửa để tránh kẹt
		GameManager.world_state["dung_1_bruna_event_completed"] = true
		
	# Tiến hành cho Bruna rời đi và chờ cô ấy biến mất hoàn toàn ngoài màn hình
	await bruna_leave()
	
	# Mở khóa phím Z của hộp thoại để người chơi có thể nhấn Z kết thúc và di chuyển
	if is_instance_valid(dialogue_box):
		dialogue_box.next_line_allowed = true

func bruna_leave() -> void:
	if not is_instance_valid(bruna_npc):
		return
		
	print("Bruna đang rời đi về phía bên phải...")
	
	# Bật chế độ xuyên tường vật lý khi Bruna ra về để cô ấy lướt qua bức tường biên bên phải
	bruna_npc.ignore_collision = true
	
	# Ra lệnh cho Bruna đi bộ ngược lại về phía bên phải (ngoài màn hình x = 550)
	bruna_npc.walk_to(Vector2(550, bruna_npc.global_position.y))
	
	# Chờ cho tới khi Bruna đi tới đích (ngoài rìa màn hình) thành công
	await bruna_npc.arrived
	
	print("Bruna đã rời khỏi bản đồ. Đang giải phóng nhân vật...")
	bruna_npc.queue_free()

