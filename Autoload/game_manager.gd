extends Node

# Trạng thái hiện tại của game
enum GameState { MENU, PLAYING, PAUSED, GAME_OVER }
var current_state: GameState = GameState.MENU

# Lưu trữ tham chiếu đến player hiện tại để dễ dàng truy cập từ bất kỳ đâu
var player: CharacterBody2D = null

# ID điểm spawn tiếp theo mà player cần được định vị sau khi chuyển cảnh
var target_spawn_id: String = ""

# --- DỮ LIỆU TOÀN CỤC (GLOBAL GAME DATA & STATE) ---
var inventory: Array[String] = []
var quest_progress: Dictionary = {}
var world_state: Dictionary = {}
var defeated_enemies: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # Luôn chạy kể cả khi game bị pause
	EventBus.player_spawned.connect(_on_player_spawned)
	EventBus.player_died.connect(_on_player_died)

func _on_player_spawned(player_node: CharacterBody2D) -> void:
	player = player_node
	current_state = GameState.PLAYING
	
	# Nếu có cấu hình điểm spawn tiếp theo
	if target_spawn_id != "":
		var spawn_points = get_tree().get_nodes_in_group("spawn_points")
		var found_spawn = false
		
		for sp in spawn_points:
			if "spawn_id" in sp and sp.spawn_id == target_spawn_id:
				# Dịch chuyển Player đến tọa độ của SpawnPoint này
				player.global_position = sp.global_position
				print("🧠 GameManager: Đã định vị Player tại SpawnPoint ID: ", target_spawn_id)
				found_spawn = true
				break
				
		if not found_spawn:
			print("🧠 GameManager Cảnh báo: Không tìm thấy SpawnPoint nào có ID: ", target_spawn_id)
			
		# Xoá ID để tránh tự động dịch chuyển trong các lần spawn sau (ví dụ: hồi sinh, load game...)
		target_spawn_id = ""

func _on_player_died() -> void:
	current_state = GameState.GAME_OVER

# Hàm chuyển đổi trạng thái Pause/Resume game
func toggle_pause() -> void:
	if current_state == GameState.PLAYING:
		get_tree().paused = true
		current_state = GameState.PAUSED
	elif current_state == GameState.PAUSED:
		get_tree().paused = false
		current_state = GameState.PLAYING

# Hàm chuyển sang màn chơi mới có hiệu ứng chuyển cảnh
func transition_to_level(level_path: String) -> void:
	EventBus.level_transition_started.emit(level_path)
	
	# Pause game trong lúc chuyển màn
	get_tree().paused = true
	
	# Chờ một khoảng ngắn (để UI fade out nếu có)
	await get_tree().create_timer(0.5).timeout
	
	# Đổi scene
	var error = get_tree().change_scene_to_file(level_path)
	if error == OK:
		get_tree().paused = false
		var level_name = level_path.get_file().get_basename()
		EventBus.level_transition_completed.emit(level_name)
	else:
		print("Lỗi chuyển màn: ", error)
		get_tree().paused = false
