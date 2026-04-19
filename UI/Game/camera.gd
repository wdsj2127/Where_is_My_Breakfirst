extends Camera2D

@export var target: Node2D  # 镜头跟随的目标

var smooth_speed = 8 # 平滑系数

func _physics_process(delta: float) -> void :
	if target:
		# 当前坐标 = 当前坐标.lerp(目标坐标, 速度 * 时间间隔)
		# 使用 delta * smooth_speed 可以保证在不同帧率下平滑速度一致
		position = position.lerp(target.position, delta * smooth_speed)
