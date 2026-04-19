extends AnimatedSprite2D

func _ready():
	print("Start animation ready")
	# 连接动画完成信号
	animation_finished.connect(_on_animation_finished)
	play("1_start")

func _on_animation_finished():
	print("Animation finished: ", animation)
	# 如果播放完的是起手动作，就切换到主游戏场景
	if animation == "1_start":
		print("Switching to main scene")
		get_tree().change_scene_to_file("res://main.tscn")
