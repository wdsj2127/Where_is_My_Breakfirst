# ============================================================
# camera.gd - 游戏摄像机
# ============================================================
# 功能：平滑跟随目标节点的2D摄像机
# 方法：
#   _physics_process(delta) - 每物理帧平滑插值到目标位置
# ============================================================

extends Camera2D

@export var target: Node2D  # 镜头跟随的目标

var smooth_speed = 8 # 平滑系数

## 每物理帧平滑插值到目标位置
## 参数 delta: 帧间隔时间（秒）
func _physics_process(delta: float) -> void :
	if target:
		position = position.lerp(target.position, delta * smooth_speed)
