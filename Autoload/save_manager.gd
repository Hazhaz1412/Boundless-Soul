extends Node

const SAVE_DIR = "user://saves/"
const SAVE_FILE_PATTERN = "save_slot_%d.tres"

func _ready() -> void:
	# Đảm bảo thư mục lưu trữ tồn tại
	var dir = DirAccess.open("user://")
	if not dir.dir_exists("saves"):
		dir.make_dir("saves")

# Hàm thực hiện Save game
func save_game(slot: int) -> bool:
	if slot < 1 or slot > 10:
		print("Lỗi: Chỉ hỗ trợ các slot lưu từ 1 đến 10!")
		return false
		
	EventBus.save_requested.emit(slot)
	
	var save_data = GameSaveData.new()
	save_data.save_slot = slot
	save_data.current_level_path = get_tree().current_scene.scene_file_path
	save_data.save_date = Time.get_datetime_string_from_system()
	
	# Thu thập thông tin từ GameManager toàn cục
	save_data.inventory = GameManager.inventory.duplicate()
	save_data.quest_progress = GameManager.quest_progress.duplicate()
	save_data.world_state = GameManager.world_state.duplicate()
	save_data.defeated_enemies = GameManager.defeated_enemies.duplicate()
	
	# Thu thập thông tin từ player nếu có trong scene
	if GameManager.player:
		var p_data = PlayerSaveData.new()
		p_data.max_hp = GameManager.player.max_hp
		p_data.hp = GameManager.player.hp
		p_data.max_mana = GameManager.player.max_mana
		p_data.mana = GameManager.player.mana
		p_data.max_stamina = GameManager.player.max_stamina
		p_data.stamina = GameManager.player.stamina
		p_data.position = GameManager.player.global_position
		p_data.flip_h = GameManager.player.animated_sprite.flip_h
		
		save_data.player_data = p_data
	
	var file_path = SAVE_DIR + (SAVE_FILE_PATTERN % slot)
	var err = ResourceSaver.save(save_data, file_path)
	
	if err == OK:
		print("Đã lưu game vào slot %d thành công!" % slot)
		EventBus.save_completed.emit(slot, true)
		return true
	else:
		print("Lưu game vào slot %d thất bại: %s" % [slot, err])
		EventBus.save_completed.emit(slot, false)
		return false

# Hàm thực hiện Load game
func load_game(slot: int) -> bool:
	if slot < 1 or slot > 10:
		print("Lỗi: Slot load không hợp lệ (1-10)!")
		EventBus.load_completed.emit(slot, false)
		return false
		
	EventBus.load_requested.emit(slot)
	
	var file_path = SAVE_DIR + (SAVE_FILE_PATTERN % slot)
	if not FileAccess.file_exists(file_path):
		print("Không tìm thấy file save ở slot %d" % slot)
		EventBus.load_completed.emit(slot, false)
		return false
		
	var save_data = ResourceLoader.load(file_path) as GameSaveData
	if not save_data:
		print("Không thể parse file save ở slot %d" % slot)
		EventBus.load_completed.emit(slot, false)
		return false
		
	# Khôi phục dữ liệu toàn cục GameManager trước
	GameManager.inventory = save_data.inventory.duplicate()
	GameManager.quest_progress = save_data.quest_progress.duplicate()
	GameManager.world_state = save_data.world_state.duplicate()
	GameManager.defeated_enemies = save_data.defeated_enemies.duplicate()
		
	# Bắt đầu chuyển cảnh sang màn chơi đã save
	if save_data.current_level_path != "":
		# Chuyển cảnh sang scene đó
		GameManager.transition_to_level(save_data.current_level_path)
		
		# Đợi chuyển màn hoàn thành để player spawn ra
		await EventBus.level_transition_completed
		
		# Áp dụng chỉ số save lên player
		if save_data.player_data and GameManager.player:
			var p = GameManager.player
			p.max_hp = save_data.player_data.max_hp
			p.hp = save_data.player_data.hp
			p.max_mana = save_data.player_data.max_mana
			p.mana = save_data.player_data.mana
			p.max_stamina = save_data.player_data.max_stamina
			p.stamina = save_data.player_data.stamina
			p.global_position = save_data.player_data.position
			p.animated_sprite.flip_h = save_data.player_data.flip_h
			
			# Cập nhật UI
			var combat_ui = get_tree().get_first_node_in_group("combat_ui")
			if combat_ui and combat_ui.has_method("update_bars"):
				combat_ui.update_bars()
				
	print("Đã tải game từ slot %d thành công!" % slot)
	EventBus.load_completed.emit(slot, true)
	return true

# Kiểm tra slot có dữ liệu save không
func has_save(slot: int) -> bool:
	var file_path = SAVE_DIR + (SAVE_FILE_PATTERN % slot)
	return FileAccess.file_exists(file_path)
