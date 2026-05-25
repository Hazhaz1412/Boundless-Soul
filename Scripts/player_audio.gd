extends Node

const SWORD_1 = preload("res://SFX/Player/07_human_atk_sword_1.wav")
const SWORD_2 = preload("res://SFX/Player/07_human_atk_sword_2.wav")
const DASH = preload("res://SFX/Player/15_human_dash_1.wav")
const SWORD_CRITICAL = preload("res://SFX/Player/DSGNTonl_MELEE-Sword Critical_HY_PC-003.wav")

func play_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
	if not stream:
		return
	var player = AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	player.play()
	player.finished.connect(func(): player.queue_free())

func play_sword_1() -> void:
	play_sfx(SWORD_1, -4.0)

func play_sword_2() -> void:
	play_sfx(SWORD_2, -4.0)

func play_dash() -> void:
	play_sfx(DASH, -2.0)

func play_sword_critical() -> void:
	play_sfx(SWORD_CRITICAL, 0.0)
