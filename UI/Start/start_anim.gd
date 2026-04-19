extends AnimatedSprite2D

func _ready():
	# 连接动画完成信号
	animation_finished.connect(_on_animation_finished)
	play("1_start")

func _on_animation_finished():
	# 如果播放完的是起手动作，就切换到循环动作
	if animation == "1_start":
		play("1_loop")
