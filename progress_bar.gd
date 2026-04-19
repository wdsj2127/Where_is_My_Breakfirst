extends ProgressBar

# ========== 导出参数 ==========
@export var player_path: NodePath = "../.."        # 指向玩家节点的路径
@export var oxygen_max: float = 100.0              # 最大氧气值（百分比）
@export var oxygen_decrease_rate: float = 5.0      # 每秒减少的百分比
@export var max_oxygen_time: float = 120.0         # 最长存活时间（秒）
@export var depth_threshold_pixels: float = 2.0    # 低于初始 Y 坐标多少像素开始扣减

# ========== 内部变量 ==========
var player: CharacterBody2D
var start_y: float                         # 玩家起始 Y 坐标
var current_oxygen: float                  # 当前氧气值（0-100）
var danger_timer: float = 0.0              # 累计处于危险区域的时间
var is_in_danger: bool = false

# ========== 生命周期 ==========
func _ready():
	# 获取玩家节点
	player = get_node(player_path)
	if not player:
		print("错误：OxygenBar 找不到玩家节点，请检查 player_path")
		return
	
	start_y = player.global_position.y
	current_oxygen = oxygen_max
	
	# 设置进度条属性
	min_value = 0
	max_value = oxygen_max
	value = current_oxygen
	show_percentage = true
	
	# 可选：设置初始颜色（通过 theme override 或后续动态样式）
	# 这里先不做复杂样式，只更新文字颜色

func _process(delta):
	if not player:
		return
	
	var current_y = player.global_position.y
	if current_y > start_y + depth_threshold_pixels:
		# 处于危险区域
		if not is_in_danger:
			is_in_danger = true
			print("进入危险区域，氧气开始消耗")
		
		# 累计时间
		danger_timer += delta
		# 减少氧气（连续减少，不使用间隔计时器，更平滑）
		current_oxygen -= oxygen_decrease_rate * delta
		current_oxygen = clamp(current_oxygen, 0.0, oxygen_max)
		
		# 更新 UI
		value = current_oxygen
		update_color()
		
		# 死亡条件：时间到 或 氧气耗尽
		if danger_timer >= max_oxygen_time or current_oxygen <= 0:
			die()
	else:
		# 安全区域，重置
		if is_in_danger:
			is_in_danger = false
			danger_timer = 0.0
			current_oxygen = oxygen_max
			value = current_oxygen
			update_color()
			print("离开危险区域，氧气恢复")

func update_color():
	# 根据氧气百分比改变进度条文字颜色
	var color: Color
	if current_oxygen > 50:
		color = Color.CYAN
	elif current_oxygen > 20:
		color = Color.YELLOW
	else:
		color = Color.RED
	add_theme_color_override("font_color", color)
	
	# 如果要改变进度条的填充颜色，需要使用 StyleBox，这里为了简化，只改文字颜色

func die():
	print("玩家缺氧死亡")
	# 暂停处理（避免重复调用）
	set_process(false)
	
	# 更新 UI
	value = 0
	add_theme_color_override("font_color", Color.RED)
	
	# 调用玩家节点的死亡方法（如果你有）
	if player.has_method("die_from_oxygen"):
		player.die_from_oxygen()
	else:
		# 否则直接停止玩家移动并重载场景
		player.velocity = Vector2.ZERO
		player.set_process_input(false)
		await get_tree().create_timer(3.0).timeout
		get_tree().reload_current_scene()
