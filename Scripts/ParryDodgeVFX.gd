extends AnimatedSprite2D

func _ready() -> void:
	# Đảm bảo hoạt ảnh không bị lặp lại
	if sprite_frames:
		sprite_frames.set_animation_loop("default", false)
	
	# VFX sắc bén, chớp nhoáng (speed_scale = 2.0) để tạo cảm giác phản đòn tức thì
	speed_scale = 2.0
	play("default")

func _on_animation_finished() -> void:
	# Tự hủy khi phát xong để giải phóng tài nguyên
	queue_free()
