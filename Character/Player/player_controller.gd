extends CharacterBody2D
@export var animated_sprite_2d: AnimatedSprite2D

const SPEED = 400
const GRAVITY = 2400
const MAX_LIFT = 1200

# 氧气系统常量
const OXYGEN_MAX_TIME = 120.0  # 2分钟，单位：秒
const OXYGEN_DEPTH_THRESHOLD = 2.0  # 深度阈值，单位：像素
const OXYGEN_DECREASE_RATE = 1.0  # 氧气减少速率，百分比/1.2秒
const OXYGEN_UPDATE_INTERVAL = 1.2  # 氧气更新间隔，单位：秒

# 空气墙边界（以像素为单位）
var left_wall_limit: float = 0.0
var right_wall_limit: float = 0.0
var top_wall_limit: float = 0.0
var bottom_wall_limit: float = 0.0

# 氧气系统变量
var initial_y_position: float = 0.0  # 初始y坐标
var oxygen_timer: float = 0.0  # 氧气计时器
var oxygen_percentage: float = 100.0  # 氧气百分比
var is_oxygen_active: bool = false  # 氧气系统是否激活
var oxygen_update_timer: float = 0.0  # 氧气更新计时器
var oxygen_label: Label = null  # 氧气显示标签

func _ready():
	# 初始化空气墙边界
	initial_y_position = global_position.y
	# 从地图控制器获取世界尺寸
	var map_controller = get_node_or_null("/root/Map")
	if map_controller:
		# 获取地图常量
		var tile_size = 32  # TileMap格子大小
		
		# 直接从地图控制器读取常量
		var world_half_width = map_controller.HALF_WIDTH  # 地图半宽（16格子）
		var world_height = map_controller.WORLD_HEIGHT    # 地图高度（128格子）
		
		# 计算空气墙边界（像素单位）
		# 左右边界：地图宽度两倍（-32 到 +32 格子）
		var extra_tiles = 16  # 额外扩大16个格子，使总宽度为地图宽度的两倍
		left_wall_limit = -(world_half_width + extra_tiles) * tile_size
		right_wall_limit = (world_half_width + extra_tiles) * tile_size
		
		# 顶部空气墙：从世界顶部向上20个格子，防止玩家飞出上方
		var top_extra_tiles = 40
		top_wall_limit = -top_extra_tiles * tile_size
		
		# 底部空气墙：地图底部，防止掉出下方
		bottom_wall_limit = world_height * tile_size
		
		# 调试输出：显示边界设置信息
		print("空气墙边界设置完成：")
		print("地图半宽（格子）: ", world_half_width)
		print("左右边界宽度（格子）: ", (world_half_width + extra_tiles) * 2)
		print("地图高度（格子）: ", world_height)
		print("顶部额外高度（格子）: ", top_extra_tiles)
		print("左边界（像素）: ", left_wall_limit)
		print("右边界（像素）: ", right_wall_limit)
		print("顶部边界（像素）: ", top_wall_limit)
		print("底部边界（像素）: ", bottom_wall_limit)
	else:
		# 如果找不到地图控制器，使用默认值
		var tile_size = 32
		var world_half_width = 16  # 默认半宽
		var world_height = 128     # 默认高度
		var extra_tiles = 32       # 额外扩大16个格子
		
		left_wall_limit = -(world_half_width + extra_tiles) * tile_size
		right_wall_limit = (world_half_width + extra_tiles) * tile_size
		
		# 顶部空气墙：从世界顶部向上20个格子
		var top_extra_tiles = 20
		top_wall_limit = -top_extra_tiles * tile_size
		
		# 底部空气墙：地图底部
		bottom_wall_limit = world_height * tile_size
		
		print("警告：找不到地图控制器，使用默认空气墙边界")
		print("左边界（像素）: ", left_wall_limit)
		print("右边界（像素）: ", right_wall_limit)
		print("顶部边界（像素）: ", top_wall_limit)
		print("底部边界（像素）: ", bottom_wall_limit)
	

enum PlayerState { IDLE, RUN, LIFT, FALL, DIE, GET, DIG }
var state: PlayerState = PlayerState.IDLE
signal state_changed(new_state: PlayerState)
## 玩家请求挖掘，参数: 世界坐标
signal dig_requested(world_pos: Vector2)
## 玩家取消挖掘
signal dig_cancelled

# 上一帧挖掘是否成功（由地图通过 _on_dig_success 回复）
var _last_dig_ok: bool = false
# 挖掘期间锁定的朝向
var _dig_facing_left: bool = false


func _physics_process(delta: float) -> void:
	_last_dig_ok = false
	update_state()
	gravity(delta)
	_update_movement()
	move_and_slide()
	update_animation()
	


## 地图挖掘成功后调用此方法通知玩家
func _on_dig_success() -> void:
	_last_dig_ok = true


## 挖掘目标方块切换时更新朝向
func _on_dig_target_changed(target_world_pos: Vector2) -> void:
	_dig_facing_left = target_world_pos.x < global_position.x


## 更新状态机
func update_state() -> void:
	var previous_state = state
	if state == PlayerState.DIE:
		return

	# 挖掘中松开鼠标左键或挖掘失败则退出DIG
	if state == PlayerState.DIG:
		if Input.is_action_pressed("Dig"):
			dig_requested.emit(get_global_mouse_position())
			if _last_dig_ok:
				if previous_state != state:
					state_changed.emit(state)
				return
		# 退出挖掘，通知地图取消
		dig_cancelled.emit()
		state = PlayerState.IDLE

	# 基础状态判断
	if is_on_floor():
		if velocity.x == 0:
			state = PlayerState.IDLE
		else:
			state = PlayerState.RUN
	else:
		state = PlayerState.FALL
	if Input.is_action_pressed("Lift"):
		state = PlayerState.LIFT

	# IDLE/RUN状态下按住鼠标左键可进入挖掘
	if (state == PlayerState.IDLE or state == PlayerState.RUN) and Input.is_action_pressed("Dig"):
		dig_requested.emit(get_global_mouse_position())
		if _last_dig_ok:
			state = PlayerState.DIG
			_dig_facing_left = get_global_mouse_position().x < global_position.x

	if previous_state != state:
		state_changed.emit(state)


## 更新移动速度
func _update_movement() -> void:
	if state == PlayerState.DIG:
		velocity.x = 0
		return

	if state == PlayerState.RUN or state == PlayerState.IDLE:
		velocity.x = Input.get_axis("Left", "Right") * SPEED * 1.5
	elif state == PlayerState.LIFT or state == PlayerState.FALL:
		velocity.x = Input.get_axis("Left", "Right") * SPEED
	
	# 空气墙限制：检查玩家是否会超出左右边界
	var next_x = global_position.x + velocity.x * get_physics_process_delta_time()
	
	# 左边界限制
	if next_x < left_wall_limit:
		velocity.x = max(velocity.x, 0)  # 不允许向左移动超出边界
		# 如果已经超出边界，将其推回
		if global_position.x < left_wall_limit:
			global_position.x = left_wall_limit
	
	# 右边界限制
	if next_x > right_wall_limit:
		velocity.x = min(velocity.x, 0)  # 不允许向右移动超出边界
		# 如果已经超出边界，将其推回
		if global_position.x > right_wall_limit:
			global_position.x = right_wall_limit


## 重力逻辑
func gravity(delta: float) -> void:
	# 检查是否超出顶部边界
	if global_position.y < top_wall_limit:
		# 如果超出顶部边界，将其推回并停止上升
		global_position.y = top_wall_limit
		velocity.y = max(velocity.y, 0)  # 不允许向上移动超出边界
		return
	
	# 检查是否超出底部边界
	if global_position.y > bottom_wall_limit:
		# 如果超出底部边界，将其推回并停止下落
		global_position.y = bottom_wall_limit
		velocity.y = 0
		return
	
	if state == PlayerState.FALL:
		if velocity.y < GRAVITY:
			velocity.y += GRAVITY * delta
		if velocity.y > GRAVITY:
			velocity.y = GRAVITY
	if is_on_floor():
		velocity.y = 0
	if state == PlayerState.LIFT:
		if is_on_ceiling() and velocity.y < 0:
			velocity.y = 0
		else:
			if -velocity.y < MAX_LIFT:
				if is_on_floor():
					velocity.y -= MAX_LIFT * delta
				else:
					velocity.y -= (MAX_LIFT + GRAVITY) * delta
			if -velocity.y > MAX_LIFT:
				velocity.y = -MAX_LIFT


## 角色动画
func update_animation() -> void:
	if state == PlayerState.DIG:
		animated_sprite_2d.flip_h = _dig_facing_left
	else:
		if velocity.x > 0:
			animated_sprite_2d.flip_h = false
		elif velocity.x < 0:
			animated_sprite_2d.flip_h = true

	match state:
		PlayerState.IDLE:
			animated_sprite_2d.play("idle")
		PlayerState.RUN:
			animated_sprite_2d.play("run")
		PlayerState.LIFT:
			animated_sprite_2d.play("lift")
		PlayerState.FALL:
			animated_sprite_2d.play("fall")
		PlayerState.DIG:
			animated_sprite_2d.play("dig")
		PlayerState.GET:
			animated_sprite_2d.play("get")
		PlayerState.DIE:
			animated_sprite_2d.play("die")


# TODO: 波纹的形成

@export var wave_scene: PackedScene   # 待会拖入 WaveFront.tscn
@export var wave_count: int = 24

func _input(event):
	if event.is_action_pressed("ui_f"):   # 假设 F 键对应 "ui_f"，需要在输入映射中设置
		emit_wave_ring()

func emit_wave_ring():
	if wave_scene == null:
		print("错误：请将 WaveFront.tscn 拖到玩家的 wave_scene 属性")
		return
	for i in range(wave_count):
		var angle = deg_to_rad(i * 360.0 / wave_count)
		var dir = Vector2(cos(angle), sin(angle))
		var wave = wave_scene.instantiate()
		wave.global_position = global_position
		wave.direction = dir
		get_tree().current_scene.add_child(wave)
