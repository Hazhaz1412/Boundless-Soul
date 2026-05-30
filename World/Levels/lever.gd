extends Sprite2D

var is_player_near: bool = false
var is_pulled: bool = false

var interaction_area: Area2D = null
var prompt_label: Label = null

func _ready() -> void:
	# 1. Tự động tạo nhãn gợi ý phím bấm [E] trên đầu cần gạt
	var label = Label.new()
	label.name = "PromptLabel"
	label.text = "[E]"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-35, -35)
	label.scale = Vector2(0.8, 0.8)
	add_child(label)
	prompt_label = label
	prompt_label.hide()

	# 2. Tự động tạo vùng tương tác Area2D bán kính 60px
	var area = Area2D.new()
	area.name = "InteractionArea"
	add_child(area)
	interaction_area = area
	
	var collision = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 60.0
	collision.shape = circle
	area.add_child(collision)

	# 3. Kiểm tra xem cần gạt đã được kích hoạt trước đó chưa
	if GameManager.world_state.get("lever_pulled", false):
		texture = load("res://World/Levels/Assets/lever2.png")
		is_pulled = true
		return

	# 4. Kết nối tín hiệu đi vào / đi ra vùng tương tác
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if is_pulled:
		return
	if body.is_in_group("player"):
		is_player_near = true
		if prompt_label:
			prompt_label.show()

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		is_player_near = false
		if prompt_label:
			prompt_label.hide()

func _input(event: InputEvent) -> void:
	if is_pulled or not is_player_near:
		return
		
	# Nhấn phím E để gạt cần gạt
	if event is InputEventKey and event.pressed and event.keycode == KEY_E:
		pull_lever()

func pull_lever() -> void:
	is_pulled = true
	is_player_near = false
	
	# Đổi sang hình ảnh cần gạt đã gạt (lever2.png)
	texture = load("res://World/Levels/Assets/lever2.png")
	
	# Ẩn gợi ý bấm phím
	if prompt_label:
		prompt_label.hide()
		
	# Lưu trạng thái kích hoạt toàn cục vào world_state
	GameManager.world_state["lever_pulled"] = true
	print("🧠 [Hệ thống]: Cần gạt đã được kích hoạt! Đã lưu trạng thái toàn cục.")
