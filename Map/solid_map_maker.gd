extends TileMapLayer

## 地形生成算法：泥土、石头、地基填充，噪声驱动空腔和目标点
## _block_data索引: x=[0, WORLD_WIDTH), y=[0, WORLD_HEIGHT)
## TileMapLayer格子坐标: x=[-HALF_WIDTH, HALF_WIDTH), y=[0, WORLD_HEIGHT)

enum BlockType { AIR, DIRT, STONE, FOUNDATION }

## 挖掘成功时发射，参数: 坐标x, 坐标y, 被挖掘的地块类型
signal block_dug(x: int, y: int, block_type: int)

# TileSet source ID
const _SOURCE_FOUNDATION = 0
const _SOURCE_STONE = 1
const _SOURCE_DIRT = 2
const _STONE_UD = 3
const _STONE_U = 4
const _STONE_D = 5
const _STONE_R = 6
const _STONE_CROSS = 7
const _STONE_LR = 8
const _STONE_L = 9
const _DIRT_UD = 10
const _DIRT_U = 11
const _DIRT_D = 12
const _DIRT_R = 13
const _DIRT_CROSS = 14
const _DIRT_LR = 15
const _DIRT_L = 16

var map: Node2D  # Map根节点，提供常量
var _block_data = []
var target_position = Vector2i(-1, -1)

var _dirt_stone_noise: FastNoiseLite
var _cavity_noise: FastNoiseLite

# 挖掘进度（使用数组索引，非格子坐标）
var _dig_target := Vector2i(-1, -1)
var _dig_progress := 0.0
var _dig_time := 0.0
var _crack_sprite: Sprite2D = null

# 裂纹贴图
var _dirt_cracks: Array[Texture2D] = []
var _stone_cracks: Array[Texture2D] = []


func _ready() -> void:
	map = get_parent()
	_load_crack_textures()
	_init_noises()

## 数组索引x → TileMapLayer格子坐标x
func _to_cell_x(x: int) -> int:
	return x - map.HALF_WIDTH

## TileMapLayer格子坐标x → 数组索引x
func _to_index_x(cell_x: int) -> int:
	return cell_x + map.HALF_WIDTH

## 加载裂纹贴图
func _load_crack_textures() -> void:
	for i in range(1, 4):
		_dirt_cracks.append(load("res://Map/Texture/裂纹/泥土裂纹%d.png" % i))
		_stone_cracks.append(load("res://Map/Texture/裂纹/岩石裂纹%d.png" % i))

## 初始化噪声实例
func _init_noises() -> void:
	var base_seed := randi()
	_dirt_stone_noise = _create_noise(base_seed, map.DIRT_STONE_NOISE_FREQ)
	_cavity_noise = _create_noise(base_seed + 1, map.CAVITY_NOISE_FREQ)

## 创建FBM分形噪声实例
@warning_ignore("shadowed_global_identifier")
static func _create_noise(seed: int, freq: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = freq
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5
	return noise

## 世界生成主流程
func generate_world() -> void:
	_init_block_data()
	_fill_base_terrain()
	_generate_cavities()
	_generate_target_point()
	_render_to_tilemap()

## 初始化地块数据为全AIR
func _init_block_data() -> void:
	_block_data.clear()
	_block_data.resize(map.WORLD_HEIGHT)
	for y in range(map.WORLD_HEIGHT):
		_block_data[y] = []
		_block_data[y].resize(map.WORLD_WIDTH)
		_block_data[y].fill(BlockType.AIR)

## 填充基础地形
func _fill_base_terrain() -> void:
	for y in range(map.WORLD_HEIGHT):
		for x in range(map.WORLD_WIDTH):
			if x < map.FOUNDATION_WIDTH or x >= map.WORLD_WIDTH - map.FOUNDATION_WIDTH:
				_block_data[y][x] = BlockType.FOUNDATION
				continue
			if y == 0:
				_block_data[y][x] = BlockType.DIRT
				continue
			var depth_ratio: float = float(y) / map.WORLD_HEIGHT
			var threshold := lerpf(0.15, -0.5, depth_ratio)
			var noise_val := _dirt_stone_noise.get_noise_2d(x, y)
			_block_data[y][x] = BlockType.STONE if noise_val > threshold else BlockType.DIRT

## 噪声驱动空腔生成
func _generate_cavities() -> void:
	for y in range(map.CAVITY_MIN_DEPTH, map.WORLD_HEIGHT):
		for x in range(map.FOUNDATION_WIDTH + 2, map.WORLD_WIDTH - map.FOUNDATION_WIDTH - 2):
			if _cavity_noise.get_noise_2d(x, y) > map.CAVITY_THRESHOLD:
				_block_data[y][x] = BlockType.AIR

## 从底部向前搜索，找到最深空腔即为目标点
func _generate_target_point() -> void:
	var min_x: int = map.FOUNDATION_WIDTH + 1
	var max_x: int = map.WORLD_WIDTH - map.FOUNDATION_WIDTH - 1
	for y in range(map.WORLD_HEIGHT - 1, map.CAVITY_MIN_DEPTH - 1, -1):
		for x in range(min_x, max_x):
			if _block_data[y][x] == BlockType.AIR:
				target_position = Vector2i(x, y)
				return
	target_position = Vector2i(-1, -1)

## 将地块数据渲染到TileMapLayer（x偏移-HALF_WIDTH）
func _render_to_tilemap() -> void:
	clear()
	for y in range(map.WORLD_HEIGHT):
		for x in range(map.WORLD_WIDTH):
			var block_type: int = _block_data[y][x]
			if block_type == BlockType.AIR:
				continue
			var source_id: int
			var atlas_coords := Vector2i(0, 0)
			match block_type:
				BlockType.DIRT:
					var result := _get_dirt_render(x, y)
					source_id = result[0]
					atlas_coords = result[1]
				BlockType.STONE:
					var result := _get_stone_render(x, y)
					source_id = result[0]
					atlas_coords = result[1]
				BlockType.FOUNDATION:
					source_id = _SOURCE_FOUNDATION
				_:
					continue
			set_cell(Vector2i(_to_cell_x(x), y), source_id, atlas_coords, 0)

## 挖掘指定数组索引坐标的地块，返回是否成功
func dig(x: int, y: int) -> bool:
	if x < 0 or x >= map.WORLD_WIDTH or y < 0 or y >= map.WORLD_HEIGHT:
		return false
	var block_type: int = _block_data[y][x]
	if block_type == BlockType.AIR or block_type == BlockType.FOUNDATION:
		return false
	_block_data[y][x] = BlockType.AIR
	set_cell(Vector2i(_to_cell_x(x), y), -1)
	_update_neighbor_render(x, y - 1)
	_update_neighbor_render(x, y + 1)
	_update_neighbor_render(x - 1, y)
	_update_neighbor_render(x + 1, y)
	block_dug.emit(x, y, block_type)
	return true

## 处理玩家挖掘请求
func handle_dig_request(world_pos: Vector2, player: CharacterBody2D) -> void:
	var local_pos := to_local(world_pos)
	var cell_pos := local_to_map(local_pos)
	# 格子坐标转数组索引
	var idx_x := _to_index_x(cell_pos.x)
	var idx_y: int = cell_pos.y
	# 距离检测
	var cell_world_center := to_global(map_to_local(cell_pos))
	var player_center := player.global_position + Vector2(0, -69)
	if player_center.distance_to(cell_world_center) > map.DIG_MAX_DISTANCE:
		_cancel_dig()
		return
	# 射线检测
	if not _is_reachable(player_center, idx_x, idx_y):
		_cancel_dig()
		return
	# 目标不可挖掘
	if not can_dig(idx_x, idx_y):
		_cancel_dig()
		return
	# 切换目标时重置进度
	var idx := Vector2i(idx_x, idx_y)
	if idx != _dig_target:
		_cancel_dig()
		_dig_target = idx
		_dig_progress = 0.0
		_dig_time = map.DIG_TIME_STONE if _block_data[idx_y][idx_x] == BlockType.STONE else map.DIG_TIME_DIRT
		if player.has_method("_on_dig_target_changed"):
			player._on_dig_target_changed(cell_world_center)
	# 累积进度
	_dig_progress += get_process_delta_time()
	_update_crack_overlay()
	# 进度满，执行挖掘
	if _dig_progress >= _dig_time:
		_cancel_dig()
		if dig(idx_x, idx_y):
			player._on_dig_success()
	else:
		player._on_dig_success()

## 取消当前挖掘
func _cancel_dig() -> void:
	_dig_target = Vector2i(-1, -1)
	_dig_progress = 0.0
	_dig_time = 0.0
	if _crack_sprite:
		_crack_sprite.queue_free()
		_crack_sprite = null

## 更新裂纹覆盖精灵
func _update_crack_overlay() -> void:
	if _dig_target.x < 0:
		return
	var block_type: int = _block_data[_dig_target.y][_dig_target.x]
	var cracks: Array[Texture2D] = _stone_cracks if block_type == BlockType.STONE else _dirt_cracks
	if cracks.is_empty():
		return
	var ratio := _dig_progress / _dig_time
	var crack_index := int(ratio * cracks.size())
	crack_index = clampi(crack_index, 0, cracks.size() - 1)
	if not _crack_sprite:
		_crack_sprite = Sprite2D.new()
		_crack_sprite.z_index = 1
		add_child(_crack_sprite)
	_crack_sprite.texture = cracks[crack_index]
	_crack_sprite.position = map_to_local(Vector2i(_to_cell_x(_dig_target.x), _dig_target.y))

## 射线检测：从世界坐标origin到数组索引(idx_x, idx_y)之间是否有实心方块阻挡
func _is_reachable(origin: Vector2, idx_x: int, idx_y: int) -> bool:
	var target_cell := Vector2i(_to_cell_x(idx_x), idx_y)
	var target_world := to_global(map_to_local(target_cell))
	var dir := target_world - origin
	var length := dir.length()
	if length < 1.0:
		return true
	dir = dir.normalized()
	var step_size := 16.0 * scale.x
	var steps := int(length / step_size) + 1
	for i in range(1, steps):
		var check_pos := origin + dir * step_size * i
		var check_local := to_local(check_pos)
		var check_cell := local_to_map(check_local)
		if check_cell == target_cell:
			return true
		var cx := _to_index_x(check_cell.x)
		var cy: int = check_cell.y
		if cx < 0 or cx >= map.WORLD_WIDTH or cy < 0 or cy >= map.WORLD_HEIGHT:
			continue
		if _block_data[cy][cx] != BlockType.AIR:
			return false
	return true

## 查询指定数组索引坐标是否可挖掘
func can_dig(x: int, y: int) -> bool:
	if x < 0 or x >= map.WORLD_WIDTH or y < 0 or y >= map.WORLD_HEIGHT:
		return false
	var block_type: int = _block_data[y][x]
	return block_type != BlockType.AIR and block_type != BlockType.FOUNDATION

## 获取指定数组索引坐标的地块类型
func get_block_type(x: int, y: int) -> int:
	if x < 0 or x >= map.WORLD_WIDTH or y < 0 or y >= map.WORLD_HEIGHT:
		return BlockType.AIR
	return _block_data[y][x]

## 更新单个格子的渲染
func _update_neighbor_render(x: int, y: int) -> void:
	if x < 0 or x >= map.WORLD_WIDTH or y < 0 or y >= map.WORLD_HEIGHT:
		return
	var block_type: int = _block_data[y][x]
	if block_type == BlockType.AIR:
		return
	var source_id: int
	var atlas_coords := Vector2i(0, 0)
	match block_type:
		BlockType.DIRT:
			var result := _get_dirt_render(x, y)
			source_id = result[0]
			atlas_coords = result[1]
		BlockType.STONE:
			var result := _get_stone_render(x, y)
			source_id = result[0]
			atlas_coords = result[1]
		BlockType.FOUNDATION:
			source_id = _SOURCE_FOUNDATION
		_:
			return
	set_cell(Vector2i(_to_cell_x(x), y), source_id, atlas_coords, 0)

## 泥土渲染
func _get_dirt_render(x: int, y: int) -> Array:
	var same_u := _is_same_type(x, y - 1, BlockType.DIRT)
	var same_d := _is_same_type(x, y + 1, BlockType.DIRT)
	var same_l := _is_same_type(x - 1, y, BlockType.DIRT)
	var same_r := _is_same_type(x + 1, y, BlockType.DIRT)
	var source := _pick_connect_source(same_u, same_d, same_l, same_r,
		_DIRT_UD, _DIRT_U, _DIRT_D, _DIRT_R, _DIRT_CROSS, _DIRT_LR, _DIRT_L)
	if source >= 0:
		return [source, Vector2i(0, 0)]
	return [_SOURCE_DIRT, _get_atlas_coords(x, y, BlockType.DIRT)]

## 岩石渲染
func _get_stone_render(x: int, y: int) -> Array:
	var same_u := _is_same_type(x, y - 1, BlockType.STONE)
	var same_d := _is_same_type(x, y + 1, BlockType.STONE)
	var same_l := _is_same_type(x - 1, y, BlockType.STONE)
	var same_r := _is_same_type(x + 1, y, BlockType.STONE)
	var source := _pick_connect_source(same_u, same_d, same_l, same_r,
		_STONE_UD, _STONE_U, _STONE_D, _STONE_R, _STONE_CROSS, _STONE_LR, _STONE_L)
	if source >= 0:
		return [source, Vector2i(0, 0)]
	return [_SOURCE_STONE, _get_atlas_coords(x, y, BlockType.STONE)]

## 连接材质选择
func _pick_connect_source(same_u: bool, same_d: bool, same_l: bool, same_r: bool,
		s_ud: int, s_u: int, s_d: int, s_r: int, s_cross: int, s_lr: int, s_l: int) -> int:
	if not same_u and not same_d and not same_l and not same_r:
		return s_cross
	if same_u and not same_d and not same_l and not same_r:
		return s_u
	if same_d and not same_u and not same_l and not same_r:
		return s_d
	if same_l and not same_u and not same_d and not same_r:
		return s_l
	if same_r and not same_u and not same_d and not same_l:
		return s_r
	if same_l and same_r and not same_u and not same_d:
		return s_ud
	if same_u and same_d and not same_l and not same_r:
		return s_lr
	return -1

## 3x3图集坐标
func _get_atlas_coords(x: int, y: int, block_type: int) -> Vector2i:
	var has_top := _is_same_type(x, y - 1, block_type)
	var has_bottom := _is_same_type(x, y + 1, block_type)
	var has_left := _is_same_type(x - 1, y, block_type)
	var has_right := _is_same_type(x + 1, y, block_type)
	var ax := 1
	var ay := 1
	if not has_left and not has_top:
		ax = 0; ay = 0
	elif not has_right and not has_top:
		ax = 2; ay = 0
	elif not has_left and not has_bottom:
		ax = 0; ay = 2
	elif not has_right and not has_bottom:
		ax = 2; ay = 2
	elif not has_top:
		ay = 0
	elif not has_bottom:
		ay = 2
	elif not has_left:
		ax = 0
	elif not has_right:
		ax = 2
	return Vector2i(ax, ay)

## 判断数组索引坐标处是否为指定类型
func _is_same_type(x: int, y: int, block_type: int) -> bool:
	if x < 0 or x >= map.WORLD_WIDTH or y < 0 or y >= map.WORLD_HEIGHT:
		return false
	return _block_data[y][x] == block_type

## 获取目标点的世界像素坐标
func get_target_world_position() -> Vector2:
	return map_to_local(Vector2i(_to_cell_x(target_position.x), target_position.y))

## 重新生成世界
func regenerate() -> void:
	_cancel_dig()
	_init_noises()
	generate_world()
