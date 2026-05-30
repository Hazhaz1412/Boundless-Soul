extends Node2D

func _ready() -> void:
	# Kiểm tra xem cần gạt ở dung_1_2 đã được gạt chưa
	if GameManager.world_state.get("lever_pulled", false):
		print("🧠 GameManager: Phát hiện cần gạt đã kích hoạt. Tiến hành gỡ bỏ TrapGai...")
		
		# Tìm và xóa bẫy gai
		var trap = get_node_or_null("Sprite2D/TrapGai")
		if not trap:
			trap = get_node_or_null("Sprite2D/StaticBody2D2") # Hỗ trợ tên gốc trước khi đổi tên
		if not trap:
			trap = find_child("TrapGai") # Tìm kiếm đệ quy đề phòng cấu trúc khác
			
		if trap:
			trap.queue_free()
			print("🧠 [Hệ thống]: TrapGai đã được gỡ bỏ an toàn.")
		else:
			print("Cảnh báo: Không tìm thấy node TrapGai hoặc StaticBody2D2 trong scene để xóa!")
