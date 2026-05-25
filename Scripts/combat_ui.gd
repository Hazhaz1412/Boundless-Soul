extends CanvasLayer

var player: CharacterBody2D = null

@onready var health_bar: TextureProgressBar = $MarginContainer/HBoxContainer/TextureRect/BarContainer/HealthBar
@onready var mana_bar: TextureProgressBar = $MarginContainer/HBoxContainer/TextureRect/BarContainer/ManaBar
@onready var stamina_bar: TextureProgressBar = $MarginContainer/HBoxContainer/TextureRect/BarContainer/Stamina

func _ready() -> void:
	# Đợi 1 frame để đảm bảo toàn bộ cây Node trong màn chơi đã được tạo đầy đủ
	await get_tree().process_frame
	
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
		_setup_ui_bars()
	else:
		push_warning("CombatUI: Không tìm thấy người chơi thuộc nhóm 'player'!")

func _setup_ui_bars() -> void:
	if not player:
		return
		
	# Cấu hình giá trị tối đa (Max Value) cho từng thanh ProgressBar từ thuộc tính của Player
	health_bar.max_value = player.max_hp
	mana_bar.max_value = player.max_mana
	stamina_bar.max_value = player.max_stamina
	
	# Khởi tạo giá trị hiện tại ngay lập tức tránh độ trễ lúc bắt đầu game
	health_bar.value = player.hp
	mana_bar.value = player.mana
	stamina_bar.value = player.stamina
	
	# PHẦN TỰ ĐỘNG SCALE ĐỘ RỘNG VẬT LÝ (DYNAMIC VISUAL SCALE):
	# Dựa vào giá trị tối đa của từng thuộc tính để kéo giãn kích thước thanh bằng Nine-Patch
	# HP (150) -> Rộng 150px
	# Stamina (100) -> Rộng 100px
	# Mana (60) -> Rộng 60px
	# Tỷ lệ 1.0px mỗi đơn vị chỉ số cực kỳ cân đối và hài hòa bên trong khung HUD status frame
	health_bar.custom_minimum_size.x = player.max_hp
	mana_bar.custom_minimum_size.x = player.max_mana
	stamina_bar.custom_minimum_size.x = player.max_stamina
	
	print("CombatUI: Đã thiết lập kích thước thanh tự động thành công! HP=%dpx, Stamina=%dpx, Mana=%dpx" % [player.max_hp, player.max_stamina, player.max_mana])

func _process(delta: float) -> void:
	if not player or not is_instance_valid(player):
		return
		
	# Nội suy mượt mà (smooth lerp) để các thanh máu/mana/stamina trôi chảy, cao cấp cực đã mắt
	health_bar.value = lerp(health_bar.value, player.hp, 15.0 * delta)
	mana_bar.value = lerp(mana_bar.value, player.mana, 15.0 * delta)
	stamina_bar.value = lerp(stamina_bar.value, player.stamina, 15.0 * delta)
