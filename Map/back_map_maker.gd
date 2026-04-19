extends TileMapLayer

## 背景地图：与SolidMap共享噪声种子，空腔更小，无碰撞，偏暗

@export var solid_map: TileMapLayer

# TileSet source ID（与SolidMap相同）
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

enum BlockType { AIR, DIRT, STONE, FOUNDATION }

var map: Node2D  # Map根节点，提供常量
var _block_data = []


func _ready() -> void:
	map = get_parent()
	collision_enabled = false


## 生成背景世界：复用SolidMap的噪声，空腔阈值更高
func _generate_back_world() -> void:
	var sm := solid_map
	var w: int = map.WORLD_WIDTH
	var h: int = map.WORLD_HEIGHT
	var fw: int = map.FOUNDATION_WIDTH
	var cmd: int = map.CAVITY_MIN_DEPTH

	# 初始化地块数据
	_block_data.clear()
	_block_data.resize(h)
	for y in range(h):
		_block_data[y] = []
		_block_data[y].resize(w)
		_block_data[y].fill(BlockType.AIR)

	# 填充基础地形（与SolidMap相同）
	for y in range(h):
		for x in range(w):
			if x < fw or x >= w - fw:
				_block_data[y][x] = BlockType.FOUNDATION
				continue
			if y == 0:
				_block_data[y][x] = BlockType.DIRT
				continue
			var depth_ratio := float(y) / h
			var threshold := lerpf(0.15, -0.5, depth_ratio)
			var noise_val: float = sm._dirt_stone_noise.get_noise_2d(x, y)
			_block_data[y][x] = BlockType.STONE if noise_val > threshold else BlockType.DIRT

	# 空腔生成：使用更高的阈值，空腔更小
	for y in range(cmd, h):
		for x in range(fw + 2, w - fw - 2):
			if sm._cavity_noise.get_noise_2d(x, y) > map.BACK_CAVITY_THRESHOLD:
				_block_data[y][x] = BlockType.AIR

	_render_to_tilemap()


## 将地块数据渲染到TileMapLayer
func _render_to_tilemap() -> void:
	clear()
	var w: int = map.WORLD_WIDTH
	var h: int = map.WORLD_HEIGHT
	for y in range(h):
		for x in range(w):
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
			set_cell(Vector2i(x - map.HALF_WIDTH, y), source_id, atlas_coords, 0)


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


## 判断坐标处是否为指定类型
func _is_same_type(x: int, y: int, block_type: int) -> bool:
	if x < 0 or x >= map.WORLD_WIDTH or y < 0 or y >= map.WORLD_HEIGHT:
		return false
	return _block_data[y][x] == block_type
