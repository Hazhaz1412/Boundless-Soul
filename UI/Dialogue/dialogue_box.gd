extends CanvasLayer

signal dialogue_finished
signal line_displayed(index: int)

@onready var avatar: TextureRect = $Control/Avatar
@onready var name_label: Label = $Control/NamePanel/NameLabel
@onready var text_label: RichTextLabel = $Control/TextLabel
@onready var prompt_label: Label = $Control/PromptLabel

var dialogue_lines: Array[Dictionary] = [] # Array of {"name": String, "text": String, "avatar": Texture}
var current_line_idx: int = 0
var is_active: bool = false

# Biến khóa cho phép nhấn nút Z tiếp theo (dùng cho cắt cảnh cuối thoại)
var next_line_allowed: bool = true:
	set(value):
		next_line_allowed = value
		if is_inside_tree() and prompt_label:
			if next_line_allowed:
				prompt_label.show()
			else:
				prompt_label.hide()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # Cho phép hoạt động cả khi game bị pause
	hide_dialogue()

# Bắt đầu hiển thị chuỗi hội thoại
func start_dialogue(lines: Array[Dictionary]) -> void:
	dialogue_lines = lines
	current_line_idx = 0
	is_active = true
	next_line_allowed = true
	show()
	get_tree().paused = true # Pause game để người chơi tập trung đọc thoại
	display_current_line()

# Hiển thị câu thoại hiện tại
func display_current_line() -> void:
	if current_line_idx >= dialogue_lines.size():
		end_dialogue()
		return
		
	var line = dialogue_lines[current_line_idx]
	name_label.text = line.get("name", "???")
	text_label.text = line.get("text", "")
	
	if line.get("avatar") != null:
		avatar.texture = line.get("avatar")
		avatar.show()
	else:
		avatar.hide()
		
	if next_line_allowed:
		prompt_label.show()
	else:
		prompt_label.hide()
		
	emit_signal("line_displayed", current_line_idx)

# Kết thúc hội thoại
func end_dialogue() -> void:
	is_active = false
	hide()
	get_tree().paused = false # Chạy lại game bình thường
	emit_signal("dialogue_finished")

func hide_dialogue() -> void:
	hide()
	is_active = false

func _input(event: InputEvent) -> void:
	if not is_active or not next_line_allowed:
		return
		
	# Nhấn Z hoặc phím Enter/Space để tiếp tục hội thoại
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_Z or event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			# Chống lặp phím bằng cách ngắt event
			get_viewport().set_input_as_handled()
			current_line_idx += 1
			display_current_line()
