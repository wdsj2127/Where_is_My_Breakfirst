extends CharacterBody2D
@export var animated_sprite_2d: AnimatedSprite2D

const SPEED = 400 # 移动速度
const GRAVITY = 2400 # 重力
const LIFT = 3600 # 升力
const MAX_LIFT = 1200 # 最大升力

enum PlayerState { IDLE, RUN, LIFT, FALL, DIE, GET, DIG }
var state: PlayerState

func _physics_process(delta: float) -> void :
	# 重力
	if is_on_floor() :
		velocity.y = 0 # 地面上重置速度
	else :
		if velocity.y < GRAVITY : # 重力加速度
			velocity.y += GRAVITY * delta
		if velocity.y > GRAVITY : # 下落最大速度
			velocity.y = GRAVITY
	
	# 喷气背包升力
	if Input.is_action_pressed("Lift") :
		if is_on_ceiling() and velocity.y < 0 : # 碰头重置速度
			velocity.y = 0
		else :
			if - velocity.y < MAX_LIFT : # 喷气背包加速度
				if is_on_floor() :
					velocity.y -= LIFT * delta
				else :
					velocity.y -= (LIFT + GRAVITY) * delta
			if - velocity.y > MAX_LIFT : # 喷气背包最大速度
				velocity.y = - MAX_LIFT
	
	velocity.x = Input.get_axis("Left", "Right") * SPEED # 获取方向和速度
	
	update_animation() # 播放动画
	
	move_and_slide() # 移动并处理碰撞
	pass

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
	pass

func update_state() :
	if state == PlayerState.DIE :
		pass
	if is_on_floor() :
		if velocity.x == 0 :
			state = PlayerState.IDLE
		else :
			state = PlayerState.RUN
	else :
		state = PlayerState.FALL
	if Input.is_action_pressed("Lift") :
		state = PlayerState.LIFT
	pass
