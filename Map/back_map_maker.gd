# ============================================================
# back_map_maker.gd - 背景地图层（BackMap）
# ============================================================
# 功能：与SolidMap共享噪声种子的背景地形，空腔更小，无碰撞，偏暗显示
# 方法：
#   _ready()                                  - 初始化map引用，禁用碰撞
#   _generate_back_world()                    - 生成背景世界（由map_controller调用）
#   _render_to_tilemap()                      - 将地块数据渲染到TileMapLayer
#   _get_dirt_render(x, y) -> Array           - 泥土渲染选择
#   _get_stone_render(x, y) -> Array          - 岩石渲染选择
#   _pick_connect_source(...) -> int          - 连接材质选择
#   _get_atlas_coords(x, y, type) -> Vector2i - 3x3图集坐标
#   _is_same_type(x, y, type) -> bool         - 判断是否为指定类型
# ============================================================

extends TileMapLayer

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


## 初始化：缓存map引用，禁用碰撞
func _ready() -> void:
	map = get_parent()
	collision_enabled = false


## 生成背景世界：复用SolidMap的噪声，空腔阈值更高（空腔更小）
## 由map_controller在SolidMap生成完毕后调用
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


## 将地块数据渲染到TileMapLayer（x偏移-HALF_WIDTH）
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
				BlockType.DIRT, BlockType.STONE:
					var result := _get_block_render(x, y, block_type)
					source_id = result[0]
					atlas_coords = result[1]
				BlockType.FOUNDATION:
					source_id = _SOURCE_FOUNDATION
				_:
					continue
			set_cell(Vector2i(x - map.HALF_WIDTH, y), source_id, atlas_coords, 0)


## 地块渲染：根据邻居同类型情况选择连接材质或图集坐标
## 参数 x: 数组索引x  参数 y: 数组索引y  参数 block_type: DIRT或STONE
## 返回: [source_id, atlas_coords]
func _get_block_render(x: int, y: int, block_type: int) -> Array:
	var same_u := _is_same_type(x, y - 1, block_type)
	var same_d := _is_same_type(x, y + 1, block_type)
	var same_l := _is_same_type(x - 1, y, block_type)
	var same_r := _is_same_type(x + 1, y, block_type)
	var ids: Array = [_DIRT_UD, _DIRT_U, _DIRT_D, _DIRT_R, _DIRT_CROSS, _DIRT_LR, _DIRT_L, _SOURCE_DIRT] \
		if block_type == BlockType.DIRT \
		else [_STONE_UD, _STONE_U, _STONE_D, _STONE_R, _STONE_CROSS, _STONE_LR, _STONE_L, _SOURCE_STONE]
	var source := _pick_connect_source(same_u, same_d, same_l, same_r,
		ids[0], ids[1], ids[2], ids[3], ids[4], ids[5], ids[6])
	if source >= 0:
		return [source, Vector2i(0, 0)]
	return [ids[7], _get_atlas_coords(x, y, block_type)]


## 连接材质选择：根据上下左右同类型邻居选择对应连接贴图
## 返回: source ID，-1表示无匹配需用图集
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


## 3x3图集坐标：根据邻居分布选择图集中的子图位置
## 参数 x: 数组索引x  参数 y: 数组索引y  参数 block_type: 地块类型
## 返回: 图集坐标Vector2i
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
## 参数 x: 数组索引x  参数 y: 数组索引y  参数 block_type: 目标类型
## 返回: 是否匹配
func _is_same_type(x: int, y: int, block_type: int) -> bool:
	if x < 0 or x >= map.WORLD_WIDTH or y < 0 or y >= map.WORLD_HEIGHT:
		return false
	return _block_data[y][x] == block_type
