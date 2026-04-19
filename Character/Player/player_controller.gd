extends CharacterBody2D
@export var animated_sprite_2d: AnimatedSprite2D

const SPEED = 400 # 移动速度
const GRAVITY = 2400 # 重力
const LIFT = 3600 # 升力
const MAX_LIFT = 1200 # 最大升力

enum PlayerState { IDLE, RUN, LIFT, FALL, DIE, GET, DIG }
var state: PlayerState = PlayerState.IDLE
signal state_changed(new_state: PlayerState)

const MAX_OXYGEN = 100 # 氧气值上限
var oxygen = MAX_OXYGEN # 氧气值，归零死亡

# 主要逻辑
func _physics_process(delta: float) -> void :
	update_oxygen() # 更新氧气
	update_state() # 更新状态机
	gravity(delta) # 重力逻辑
	# 获取方向和速度
	if state == PlayerState.RUN :
		velocity.x = Input.get_axis("Left", "Right") * SPEED * 1.5
	else :
		velocity.x = Input.get_axis("Left", "Right") * SPEED
	
	move_and_slide() # 移动并处理碰撞
	update_animation() # 播放动画
	pass

# TODO: 氧气逻辑
func update_oxygen() :
	pass

# 重力逻辑
# 包括下落和上升
func gravity(delta) :
	# 下落
	if state == PlayerState.FALL :
		if velocity.y < GRAVITY : # 下落加速度
			velocity.y += GRAVITY * delta
		if velocity.y > GRAVITY : # 下落最大速度
			velocity.y = GRAVITY
	# 地面上重置速度
	if is_on_floor() :
		velocity.y = 0
	# 上升
	if state == PlayerState.LIFT :
		if is_on_ceiling() and velocity.y < 0 : # 碰头重置速度
			velocity.y = 0
		else :
			if - velocity.y < MAX_LIFT : # 上升加速度
				if is_on_floor() :
					velocity.y -= MAX_LIFT * delta
				else :
					velocity.y -= (MAX_LIFT + GRAVITY) * delta
			if - velocity.y > MAX_LIFT : # 上升最大速度
				velocity.y = - MAX_LIFT
	return

# 角色动画
func update_animation() :
	# 朝向
	if velocity.x > 0 :
		animated_sprite_2d.flip_h = false # 面向右边
	elif velocity.x < 0 :
		animated_sprite_2d.flip_h = true # 面向左边
		
	# 动画
	match state :
		PlayerState.IDLE :
			animated_sprite_2d.play("idle")
		PlayerState.RUN :
			animated_sprite_2d.play("run")
		PlayerState.LIFT :
			animated_sprite_2d.play("lift")
		PlayerState.FALL :
			animated_sprite_2d.play("fall")
		PlayerState.DIG :
			animated_sprite_2d.play("dig")
		PlayerState.GET :
			animated_sprite_2d.play("get")
		PlayerState.DIE :
			animated_sprite_2d.play("die")
	return

# 更新状态机
# TODO: 挖掘和获取
func update_state() :
	var previous_state = state # 记录上一帧状态
	if state == PlayerState.DIE :
		return
	if is_on_floor() :
		if velocity.x == 0 :
			state = PlayerState.IDLE
		else :
			state = PlayerState.RUN
		# TODO: PlayerState.DIG
		# TODO: PlayerState.GET
	else :
		state = PlayerState.FALL
	if Input.is_action_pressed("Lift") :
		state = PlayerState.LIFT
	
	# 发出信号
	if previous_state != state :
		state_changed.emit(state)
	pass
