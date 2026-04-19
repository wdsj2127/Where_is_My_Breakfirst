extends GPUParticles2D


# Called when the node enters the scene tree for the first time.


func _ready():
	set_breakfast_position()
	emitting = true

func set_breakfast_position():
	var map_controller = get_node_or_null("/root/Map")
	if map_controller and map_controller.back_map:
		var breakfast_pos = map_controller.back_map.get_breakfast_world_position()
		if breakfast_pos != Vector2.ZERO:
			global_position = breakfast_pos
		else:
			randomize_position()  # 如果找不到早餐，随机位置
	else:
		randomize_position()

func randomize_position():
	# 边界定义
	var left = -832
	var right = 832
	var min_y = 600
	var max_y = 1000   # 底部以上64是4096-64=4032，所以取4032作为上限
	
	# 生成随机坐标
	var random_x = randf_range(left, right)
	var random_y = randf_range(min_y, max_y)
	
	global_position = Vector2(random_x, random_y)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
