extends CharacterBody2D

var speed: float = 200.0
var direction: Vector2 = Vector2.RIGHT
var map_controller: Node2D = null
var solid_map: TileMapLayer = null

# 波的检测半径（像素）
var detection_radius: float = 10.0
# 是否已经初始化（用于跳过初始位置的空气检测）
var initialized: bool = false
# 初始位置
var initial_position: Vector2 = Vector2.ZERO

func _ready():
	# 获取地图控制器节点
	map_controller = get_node_or_null("/root/Map")
	if map_controller == null:
		# 尝试其他可能的路径
		map_controller = get_node_or_null("../Map")
	
	if map_controller:
		# 获取SolidMap节点
		solid_map = map_controller.get_node_or_null("SolidMap")
	
	# 设置碰撞层和掩码
	collision_layer = 2  # 设置波的碰撞层
	collision_mask = 1   # 只检测与第1层（地图）的碰撞
	
	# 设置渲染层级为最前面
	z_index = 100
	
	# 保存初始位置
	initial_position = global_position
	# 标记为已初始化
	initialized = true

# 检查指定位置是否是固体（泥土、石头、地基）
func is_solid_at_position(world_pos: Vector2) -> bool:
	if not solid_map:
		return false
	
	# 将世界坐标转换为地图格子坐标
	var local_pos = solid_map.to_local(world_pos)
	var cell_pos = solid_map.local_to_map(local_pos)
	
	# 检查solid_map是否有get_block_type方法
	if solid_map.has_method("get_block_type"):
		# 将TileMap格子坐标转换为数组索引
		# 需要从map_controller获取HALF_WIDTH
		var idx_x = cell_pos.x
		var idx_y = cell_pos.y
		
		if map_controller:
			idx_x += map_controller.HALF_WIDTH
		
		# 获取块类型
		var block_type = solid_map.get_block_type(idx_x, idx_y)
		
		# 检查是否是固体（不是空气）
		# BlockType.AIR = 0, BlockType.DIRT = 1, BlockType.STONE = 2, BlockType.FOUNDATION = 3
		return block_type != 0  # 不是空气就是固体
	
	return false

# 检查波的前方是否是空气
func check_front_for_air() -> bool:
	if not solid_map:
		return false
	
	# 计算波前方的检测点
	var front_pos = global_position + direction * detection_radius
	
	# 检查前方点是否是空气
	var local_pos = solid_map.to_local(front_pos)
	var cell_pos = solid_map.local_to_map(local_pos)
	
	# 检查solid_map是否有get_block_type方法
	if solid_map.has_method("get_block_type"):
		# 将TileMap格子坐标转换为数组索引
		var idx_x = cell_pos.x
		var idx_y = cell_pos.y
		
		if map_controller:
			idx_x += map_controller.HALF_WIDTH
		
		# 获取块类型
		var block_type = solid_map.get_block_type(idx_x, idx_y)
		
		# 检查是否是空气
		return block_type == 0  # BlockType.AIR
	
	return false

# 获取碰撞点的法线（基于空气边界）
func get_air_boundary_normal(world_pos: Vector2) -> Vector2:
	if not solid_map:
		return Vector2.ZERO
	
	# 检查solid_map是否有get_block_type方法
	if not solid_map.has_method("get_block_type"):
		return Vector2.ZERO
	
	# 检查四个方向的相邻块
	var directions = [
		Vector2.LEFT,   # 左
		Vector2.RIGHT,  # 右
		Vector2.UP,     # 上
		Vector2.DOWN    # 下
	]
	
	# 将世界坐标转换为地图格子坐标
	var local_pos = solid_map.to_local(world_pos)
	var cell_pos = solid_map.local_to_map(local_pos)
	
	# 将TileMap格子坐标转换为数组索引
	var base_x = cell_pos.x
	var base_y = cell_pos.y
	
	if map_controller:
		base_x += map_controller.HALF_WIDTH
	
	# 检查当前位置是否是空气
	var current_block_type = solid_map.get_block_type(base_x, base_y)
	var is_current_air = current_block_type == 0
	
	# 查找固体边界
	for dir in directions:
		var check_x = base_x + int(dir.x)
		var check_y = base_y + int(dir.y)
		
		var neighbor_block_type = solid_map.get_block_type(check_x, check_y)
		var is_neighbor_air = neighbor_block_type == 0
		
		# 如果当前位置是空气而相邻位置是固体，或者当前位置是固体而相邻位置是空气
		# 那么边界法线就是从这个位置指向相邻位置的方向
		if is_current_air != is_neighbor_air:
			# 返回从固体指向空气的法线
			if is_current_air:
				# 当前位置是空气，相邻是固体，法线指向空气（从固体指向空气）
				return dir.normalized()
			else:
				# 当前位置是固体，相邻是空气，法线指向固体（从空气指向固体）
				return -dir.normalized()
	
	# 如果没有找到明显的边界，返回零向量
	return Vector2.ZERO

func _physics_process(delta):
	# 检查波是否在固体中传播
	var current_pos = global_position
	var is_in_solid = is_solid_at_position(current_pos)
	
	# 如果不是在初始位置，才检查是否在固体中
	# 这允许波从空气位置开始（比如玩家在空气中发射波）
	if not is_in_solid and initialized and current_pos.distance_to(initial_position) > detection_radius:
		# 波不在固体中，应该消失（因为波只能在固体中传播）
		queue_free()
		return
	
	# 检查波的前方是否是空气
	if check_front_for_air():
		# 前方是空气，需要反弹
		var normal = get_air_boundary_normal(current_pos)
		if normal != Vector2.ZERO:
			# 按照物理定律反弹：反射速度向量
			direction = direction.bounce(normal)
			
			# 小距离移动避免卡住
			global_position += direction * speed * delta * 0.1
		else:
			# 无法确定边界法线，直接消失
			queue_free()
		return
	
	# 正常移动
	global_position += direction * speed * delta
	
	# 使用move_and_collide检测与实体的碰撞
	var collision = move_and_collide(direction * speed * delta)
	if collision:
		# 如果与实体碰撞，消失
		queue_free()
		return
	
	# 超出屏幕一定范围自动删除，防止堆积
	if abs(global_position.x) > 3000 or abs(global_position.y) > 3000:
		queue_free()
