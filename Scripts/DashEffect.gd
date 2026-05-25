extends AnimatedSprite2D

func _ready() -> void:
	# Đảm bảo hoạt ảnh khói không bị lặp lại vô hạn
	if sprite_frames:
		sprite_frames.set_animation_loop("default", false)
	
	# Tăng tốc độ hoạt ảnh khói lên 1.8x để tan biến cực kỳ gọn gàng và snappy
	speed_scale = 1.8
	
	# Phát hoạt ảnh khói mặc định
	play("default")
	
	# Tạo hiệu ứng phai màu (fade-out) mượt mà kết hợp tự động giải phóng bộ nhớ
	var tween = create_tween()
	# Phai mờ cực nhanh độ trong suốt (modulate:a) về 0 trong vòng 0.22 giây
	tween.tween_property(self, "modulate:a", 0.0, 0.22)

func _on_animation_finished() -> void:
	# Khi hoạt ảnh hoàn tất, tự hủy để giải phóng tài nguyên hệ thống
	queue_free()
