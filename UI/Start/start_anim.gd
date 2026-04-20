# ============================================================
# start_anim.gd - 开始界面动画
# ============================================================
# 功能：播放起手动画后切换到循环动画
# 方法：
#   _ready()                    - 连接动画完成信号，播放起手动画
#   _on_animation_finished()    - 起手动画完成后切换到循环动画
# ============================================================

extends AnimatedSprite2D

## 初始化：连接动画完成信号，播放起手动画"1_start"
func _ready():
	animation_finished.connect(_on_animation_finished)
	play("1_start")

## 起手动画完成后切换到循环动画"1_loop"
func _on_animation_finished():
	if animation == "1_start":
		play("1_loop")
