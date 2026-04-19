extends CharacterBody2D
@export var animated_sprite_2d: AnimatedSprite2D

const SPEED = 400
const GRAVITY = 2400
const MAX_LIFT = 1200

enum PlayerState { IDLE, RUN, LIFT, FALL, DIE, GET, DIG }
var state: PlayerState = PlayerState.IDLE
signal state_changed(new_state: PlayerState)
## 玩家请求挖掘，参数: 世界坐标
signal dig_requested(world_pos: Vector2)
## 玩家取消挖掘
signal dig_cancelled

const MAX_OXYGEN = 100
var oxygen = MAX_OXYGEN

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


## 重力逻辑
func gravity(delta: float) -> void:
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


# TODO: 氧气逻辑
func update_oxygen() -> void:
	pass
